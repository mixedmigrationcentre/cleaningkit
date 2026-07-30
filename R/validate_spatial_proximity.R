#' Validate Spatial Proximity Between Surveys
#'
#' Checks how close together surveys were conducted by computing the geodesic
#' distance between every pair of GPS coordinates. Flags pairs whose interviews
#' were conducted within \code{distance_threshold_m} metres of each other, which
#' may indicate that surveys were collected from the same household or location
#' rather than from distinct respondents.
#'
#' @details
#' When \code{enumerator_column} is supplied, pairwise distances are computed
#' only within each enumerator's own surveys — a proximity flag is only raised
#' if the same enumerator conducted two nearby interviews. When
#' \code{enumerator_column} is \code{NULL}, all surveys in the dataset are
#' compared against each other regardless of who collected them.
#'
#' GPS coordinates from ONA exports are decimal degrees on the WGS84 datum
#' (EPSG:4326). Distances are computed as geodesic metres using
#' \code{sf::st_distance()}, which accounts for the curvature of the earth.
#'
#' Each flagged \emph{pair} produces two log rows (one per survey), sharing a
#' \code{check_binding} so both surveys are coloured as a group in the review
#' workbook. A survey that is close to multiple others produces multiple pairs,
#' each with its own binding.
#'
#' Surveys with missing or non-numeric coordinates are excluded from comparison
#' and a warning is issued with the count.
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
#'   proximity is checked only within each enumerator's surveys. When
#'   \code{NULL}, all surveys are compared globally. Default \code{"username"}.
#' @param log_name Name of the log element in the returned list. Default
#'   \code{"spatial_proximity_log"}.
#' @param distance_threshold_m Numeric. Surveys closer than this many metres
#'   are flagged. Default \code{50} (roughly the footprint of one household
#'   compound).
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row
#'   of the dataset is treated as the ONA label/description row and excluded
#'   from all calculations.
#'
#' @return A list containing:
#'   \item{checked_dataset}{The original dataset, unchanged.}
#'   \item{<log_name>}{A dataframe with columns \code{uuid},
#'     \code{old_value} (the coordinate pair as \code{"lat, lon"}),
#'     \code{question} (\code{"gps_location"}),
#'     \code{issue} (distance in metres to the nearest flagged neighbour,
#'     with enumerator and paired uuid),
#'     and \code{check_binding} (shared between both surveys in a flagged pair).}
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

  # ---- handle missing coordinates ----
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

  # ---- pairwise distance computation per group ----
  log_parts <- list()

  groups <- unique(enum_v[!is.na(enum_v) & enum_v != ""])

  for (grp in groups) {
    grp_idx <- which(enum_v == grp)
    if (length(grp_idx) < 2) {
      next
    }

    grp_pts <- pts[grp_idx, ]
    grp_uuids <- uuids_v[grp_idx]
    grp_lats <- lats_v[grp_idx]
    grp_lons <- lons_v[grp_idx]

    # compute full n×n geodesic distance matrix (metres)
    dist_mat <- sf::st_distance(grp_pts)
    class(dist_mat) <- "matrix" # strip units for numeric comparison
    storage.mode(dist_mat) <- "numeric"

    n <- length(grp_idx)

    for (i in seq_len(n - 1L)) {
      for (j in seq(i + 1L, n)) {
        d_m <- dist_mat[i, j]
        if (is.na(d_m) || d_m > distance_threshold_m) {
          next
        }

        uuid_i <- grp_uuids[i]
        uuid_j <- grp_uuids[j]

        d_label <- round(d_m, 1)
        enum_tag <- if (use_enumerator) {
          paste0(" by enumerator '", grp, "'")
        } else {
          ""
        }

        issue_i <- paste0(
          "Survey is ",
          d_label,
          "m from survey ",
          uuid_j,
          enum_tag,
          " — possible same-household or fabricated interview ",
          "(threshold: ",
          distance_threshold_m,
          "m)"
        )
        issue_j <- paste0(
          "Survey is ",
          d_label,
          "m from survey ",
          uuid_i,
          enum_tag,
          " — possible same-household or fabricated interview ",
          "(threshold: ",
          distance_threshold_m,
          "m)"
        )

        # binding: lexicographic min/max of the pair so both share one colour
        binding <- paste0(
          "proximity ~/~ ",
          min(uuid_i, uuid_j),
          " ~/~ ",
          max(uuid_i, uuid_j)
        )

        log_parts[[paste0(uuid_i, "__", uuid_j)]] <- data.frame(
          uuid = c(uuid_i, uuid_j),
          old_value = c(
            paste0(round(grp_lats[i], 6), ", ", round(grp_lons[i], 6)),
            paste0(round(grp_lats[j], 6), ", ", round(grp_lons[j], 6))
          ),
          question = "gps_location",
          issue = c(issue_i, issue_j),
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

  n_pairs <- length(log_parts)
  n_surveys <- length(unique(log$uuid))
  message(
    "validate_spatial_proximity: ",
    n_pairs,
    " flagged pair(s) involving ",
    n_surveys,
    " survey(s)",
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
