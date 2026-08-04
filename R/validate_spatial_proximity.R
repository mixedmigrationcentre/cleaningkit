#' Validate Spatial Proximity Between Surveys
#'
#' Checks how close together surveys were conducted by computing the geodesic
#' distance between every pair of GPS coordinates and grouping nearby surveys
#' into spatial clusters. Each survey that belongs to a cluster of two or more
#' surveys within \code{distance_threshold_m} metres is flagged with one log
#' row, regardless of how many other surveys are in the same cluster.
#'
#' @details
#' \strong{Why clusters instead of pairs?}
#' A naive pairwise approach flags every combination of nearby surveys: a camp
#' with 20 surveys within 50 m of each other produces 20×19/2 = 190 pairs and
#' 380 log rows. The cluster approach groups all transitively connected surveys
#' (connected components in the proximity graph) and emits exactly one row per
#' survey in a cluster, so the same 20 surveys produce 20 rows. The output size
#' is therefore proportional to the number of suspicious surveys, not to the
#' square of them.
#'
#' \strong{What is a cluster?}
#' Two surveys are \emph{directly} connected if they are within
#' \code{distance_threshold_m} metres of each other. A cluster is the maximal
#' set of surveys where every survey is reachable from every other via a chain
#' of direct connections (a connected component in graph terms). A cluster of
#' size 1 is not flagged.
#'
#' \strong{Enumerator grouping:}
#' When \code{enumerator_column} is supplied, clustering is performed
#' independently within each enumerator's surveys. A proximity flag is only
#' raised when the same enumerator collected multiple nearby interviews. When
#' \code{enumerator_column} is \code{NULL}, all surveys are compared globally.
#'
#' \strong{check_binding:}
#' All surveys in the same cluster share one \code{check_binding} value
#' (\code{"proximity ~/~ <cluster_id>"}), so they are coloured as a group in
#' the review workbook.
#'
#' @param dataset A dataframe or a list containing a dataframe named
#'   \code{checked_dataset}.
#' @param lat_column Name of the latitude column (decimal degrees, WGS84).
#'   Default \code{"_location_latitude"}.
#' @param lon_column Name of the longitude column (decimal degrees, WGS84).
#'   Default \code{"_location_longitude"}.
#' @param uuid_column Name of the unique-identifier column. Default
#'   \code{"_uuid"}.
#' @param enumerator_column Name of the enumerator column. When supplied,
#'   clustering is performed within each enumerator's surveys only. When
#'   \code{NULL}, all surveys are compared globally. Default \code{"username"}.
#' @param log_name Name of the log element in the returned list. Default
#'   \code{"spatial_proximity_log"}.
#' @param distance_threshold_m Numeric. Two surveys are considered in proximity
#'   if they are within this many metres of each other. Default \code{50}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row
#'   of the dataset is treated as the ONA label/description row and excluded.
#'
#' @return A list containing:
#'   \item{checked_dataset}{The original dataset, unchanged.}
#'   \item{<log_name>}{A dataframe with one row per survey that belongs to a
#'     spatial cluster, with columns \code{uuid},
#'     \code{old_value} (coordinates as \code{"lat, lon"}),
#'     \code{question} (\code{"gps_location"}),
#'     \code{issue} (cluster size, nearest neighbour distance, and all cluster
#'     member UUIDs), and \code{check_binding} (shared by all surveys in the
#'     same cluster).}
#' @export
validate_spatial_proximity <- function(
  dataset,
  lat_column = "_location_latitude",
  lon_column = "_location_longitude",
  uuid_column = "_uuid",
  enumerator_column = "username",
  log_name = "spatial_proximity_log",
  distance_threshold_m = 50,
  skip_label_row = TRUE
) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop(
      "The 'sf' package is required for validate_spatial_proximity(). ",
      "Install it with: install.packages('sf')"
    )
  }

  # ---- normalise input ----
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list.")
  }

  df <- dataset[["checked_dataset"]]

  for (col in c(uuid_column, lat_column, lon_column)) {
    if (!(col %in% names(df))) {
      stop(paste0("Cannot find '", col, "' in the names of the dataset."))
    }
  }

  use_enumerator <- !is.null(enumerator_column)
  if (use_enumerator && !(enumerator_column %in% names(df))) {
    warning(paste0(
      "'",
      enumerator_column,
      "' not found in the dataset. ",
      "Falling back to global (whole-dataset) comparison."
    ))
    use_enumerator <- FALSE
    enumerator_column <- NULL
  }

  # ---- drop ONA label row ----
  if (skip_label_row && nrow(df) > 0) {
    df <- df[-1, , drop = FALSE]
  }

  if (nrow(df) < 2) {
    warning(
      "Dataset has fewer than 2 records after dropping the label row; nothing to compare."
    )
    dataset[[log_name]] <- .empty_proximity_log()
    return(dataset)
  }

  uuids <- trimws(as.character(df[[uuid_column]]))
  lats <- suppressWarnings(as.numeric(df[[lat_column]]))
  lons <- suppressWarnings(as.numeric(df[[lon_column]]))

  # ---- handle missing / invalid coordinates ----
  valid_coords <- !is.na(lats) &
    !is.na(lons) &
    is.finite(lats) &
    is.finite(lons) &
    lats >= -90 &
    lats <= 90 &
    lons >= -180 &
    lons <= 180

  n_missing <- sum(!valid_coords)
  if (n_missing > 0) {
    warning(paste0(
      n_missing,
      " survey(s) have missing or invalid coordinates ",
      "and will be excluded from the spatial proximity check."
    ))
  }

  df_valid <- df[valid_coords, , drop = FALSE]
  uuids_v <- uuids[valid_coords]
  lats_v <- lats[valid_coords]
  lons_v <- lons[valid_coords]

  if (nrow(df_valid) < 2) {
    warning("Fewer than 2 surveys have valid coordinates; nothing to compare.")
    dataset[[log_name]] <- .empty_proximity_log()
    return(dataset)
  }

  enum_v <- if (use_enumerator) {
    trimws(as.character(df_valid[[enumerator_column]]))
  } else {
    rep("__all__", nrow(df_valid))
  }

  # ---- build sf point geometry (WGS84 / EPSG:4326) ----
  pts <- sf::st_as_sf(
    data.frame(lon = lons_v, lat = lats_v),
    coords = c("lon", "lat"),
    crs = 4326
  )

  # ---- union-find helpers for connected-component clustering ----
  # Each survey starts in its own component. When two surveys are within the
  # threshold, their components are merged. The result is a cluster ID per survey.
  uf_find <- function(parent, i) {
    while (parent[i] != i) {
      parent[i] <- parent[parent[i]] # path compression
      i <- parent[i]
    }
    i
  }
  uf_union <- function(parent, rank, i, j) {
    ri <- uf_find(parent, i)
    rj <- uf_find(parent, j)
    if (ri == rj) {
      return(list(parent = parent, rank = rank))
    }
    if (rank[ri] < rank[rj]) {
      tmp <- ri
      ri <- rj
      rj <- tmp
    }
    parent[rj] <- ri
    if (rank[ri] == rank[rj]) {
      rank[ri] <- rank[ri] + 1L
    }
    list(parent = parent, rank = rank)
  }

  # ---- cluster per enumerator group ----
  log_parts <- list()
  groups <- unique(enum_v[!is.na(enum_v) & nzchar(enum_v)])

  for (grp in groups) {
    grp_idx <- which(enum_v == grp)
    if (length(grp_idx) < 2) {
      next
    }

    grp_pts <- pts[grp_idx, ]
    grp_uuids <- uuids_v[grp_idx]
    grp_lats <- lats_v[grp_idx]
    grp_lons <- lons_v[grp_idx]
    n <- length(grp_idx)

    # geodesic distance matrix (metres)
    dist_mat <- sf::st_distance(grp_pts)
    class(dist_mat) <- "matrix"
    storage.mode(dist_mat) <- "numeric"

    # union-find: one component per survey initially
    parent <- seq_len(n)
    rank <- integer(n)

    # record the minimum distance each survey has to any neighbour within threshold
    min_dist <- rep(NA_real_, n)

    for (i in seq_len(n - 1L)) {
      for (j in seq(i + 1L, n)) {
        d <- dist_mat[i, j]
        if (is.na(d) || d > distance_threshold_m) {
          next
        }
        # merge the two surveys into the same cluster
        uf_res <- uf_union(parent, rank, i, j)
        parent <- uf_res$parent
        rank <- uf_res$rank
        # track nearest neighbour distance
        if (is.na(min_dist[i]) || d < min_dist[i]) {
          min_dist[i] <- d
        }
        if (is.na(min_dist[j]) || d < min_dist[j]) min_dist[j] <- d
      }
    }

    # resolve cluster IDs (canonical root for each survey)
    cluster_ids <- vapply(
      seq_len(n),
      function(i) uf_find(parent, i),
      integer(1)
    )

    # only keep clusters of size >= 2
    cluster_sizes <- table(cluster_ids)
    multi_clusters <- as.integer(names(cluster_sizes[cluster_sizes >= 2]))

    if (length(multi_clusters) == 0) {
      next
    }

    enum_tag <- if (use_enumerator) paste0(" (enumerator: '", grp, "')") else ""

    for (cid in multi_clusters) {
      members <- which(cluster_ids == cid)
      cluster_size <- length(members)
      member_uuids <- grp_uuids[members]

      # stable cluster identifier: sorted UUIDs collapsed
      cluster_key <- paste(sort(member_uuids), collapse = "_")
      binding <- paste0("proximity ~/~ ", cluster_key)

      for (k in members) {
        nearest_m <- if (!is.na(min_dist[k])) {
          round(min_dist[k], 1)
        } else {
          NA_real_
        }

        # list the other members so the reviewer can see the full cluster
        other_uuids <- member_uuids[member_uuids != grp_uuids[k]]
        others_str <- paste(other_uuids, collapse = ", ")

        issue <- paste0(
          "Survey belongs to a spatial cluster of ",
          cluster_size,
          " surveys within ",
          distance_threshold_m,
          "m",
          enum_tag,
          ". Nearest neighbour: ",
          nearest_m,
          "m. ",
          "Other surveys in cluster: ",
          others_str,
          " — possible same-household or fabricated interviews."
        )

        log_parts[[paste0(cluster_key, "__", grp_uuids[k])]] <- data.frame(
          uuid = grp_uuids[k],
          old_value = paste0(
            round(grp_lats[k], 6),
            ", ",
            round(grp_lons[k], 6)
          ),
          question = "gps_location",
          issue = issue,
          check_binding = binding,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  # ---- assemble log ----
  if (length(log_parts) == 0) {
    log <- .empty_proximity_log()
  } else {
    log <- do.call(rbind, log_parts)
    rownames(log) <- NULL
    log <- log[order(log$check_binding, log$uuid), ]
  }

  n_clusters <- length(unique(log$check_binding[log$check_binding != ""]))
  n_surveys <- length(unique(log$uuid))
  message(
    "validate_spatial_proximity: ",
    n_surveys,
    " survey(s) across ",
    n_clusters,
    " spatial cluster(s) flagged",
    if (use_enumerator) " (checked per enumerator)" else " (checked globally)",
    "."
  )

  dataset[[log_name]] <- log
  return(dataset)
}

#' @keywords internal
.empty_proximity_log <- function() {
  data.frame(
    uuid = character(0),
    old_value = character(0),
    question = character(0),
    issue = character(0),
    check_binding = character(0),
    stringsAsFactors = FALSE
  )
}
