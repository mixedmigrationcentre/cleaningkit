#' Validate Interview Location Against Claimed Country and City
#'
#' Checks whether the GPS coordinates recorded during an in-person interview
#' are plausibly consistent with the country and city the respondent claims
#' the interview was conducted in. Two independent checks are performed:
#'
#' \enumerate{
#'   \item \strong{Country check} (requires \code{rnaturalearthdata}): tests
#'     whether the GPS point falls inside the polygon of the claimed country,
#'     allowing a small tolerance for points just outside the border.
#'   \item \strong{City check}: geocodes each unique city+country combination
#'     in the dataset once via the Nominatim/OpenStreetMap API, then checks
#'     whether the GPS point is within \code{city_radius_km} kilometres of the
#'     city centre. Requires an internet connection.
#' }
#'
#' \strong{Phone interviews are skipped.} A survey conducted by phone records
#' no geopoint, so both coordinate columns come back empty. Those surveys are
#' identified up front and excluded from all three checks — there is nothing
#' to validate and flagging them would bury the real problems. Surveys whose
#' GPS is present but unusable are a different matter and are still flagged:
#' one coordinate filled and the other empty, non-numeric text, out-of-range
#' values, or the \code{(0, 0)} device default. Set
#' \code{treat_blank_gps_as_phone = FALSE} to flag fully-empty coordinates
#' too, which is appropriate for a round that was entirely face-to-face.
#'
#' @details
#' \strong{Nominatim usage policy:} this function respects the
#' \href{https://operations.osmfoundation.org/policies/nominatim/}{Nominatim
#' Acceptable Use Policy} by geocoding only unique city+country pairs (not
#' every row), adding a 1-second delay between requests, and identifying
#' itself via the \code{User-Agent} header. For large datasets with many
#' unique city combinations, geocoding may take a few minutes.
#'
#' \strong{City matching}: city names are passed to Nominatim as-is from the
#' dataset. Spelling must be in English and must reasonably match OSM data
#' (e.g. "Kampala", "Nairobi", "Addis Ababa"). Each pair is first tried as a
#' structured query (\code{city=} + \code{country=}); if that returns nothing
#' the pair is retried as a free-form query (\code{q="city, country"}), which
#' resolves many small towns, border crossings and settlements that are not
#' tagged as cities in OSM. If a pair still cannot be geocoded, those surveys
#' are excluded from the city check and a warning is issued.
#'
#' \strong{Country matching}: the claimed country is matched
#' case-insensitively against several Natural Earth name fields
#' (\code{admin}, \code{name}, \code{name_long}, \code{sovereignt},
#' \code{formal_en}, \code{name_en}) as well as the ISO2 and ISO3 code
#' columns, so either a country name or an ISO code works. A small alias
#' table covers common humanitarian variants (e.g. "DRC", "Ivory Coast",
#' "Syria", "UAE"). Field names in \code{rnaturalearthdata} are resolved
#' case-insensitively, so both the older lower-case and any upper-case
#' variants of the package are supported.
#'
#' @param dataset A dataframe or a list containing a dataframe named
#'   \code{checked_dataset}.
#' @param uuid_column Name of the uuid column. Default \code{"_uuid"}.
#' @param lat_column Name of the GPS latitude column. Default
#'   \code{"_location_latitude"}.
#' @param lon_column Name of the GPS longitude column. Default
#'   \code{"_location_longitude"}.
#' @param country_question Column containing the claimed country of interview.
#'   Default \code{"Q13"}.
#' @param city_question Column containing the claimed city of interview.
#'   Default \code{"Q14"}.
#' @param log_name Name of the log element in the returned list. Default
#'   \code{"interview_location_log"}.
#' @param city_radius_km Maximum acceptable distance in kilometres between the
#'   GPS point and the geocoded city centre. Default \code{75} — large enough
#'   to cover outer suburbs of most cities while still detecting GPS points
#'   that are clearly in the wrong location. Adjust per context: use a smaller
#'   value (e.g. 30) for small cities, larger (e.g. 150) for sprawling
#'   metropolitan areas.
#' @param border_tolerance_km Numeric. How far outside the claimed country's
#'   border a GPS point may fall before it is flagged, in kilometres. Absorbs
#'   ordinary GPS error and coarse border geometry. Default \code{10}.
#' @param check_country Logical. If \code{TRUE} (the default), perform the
#'   country-level polygon containment check. Requires the
#'   \code{rnaturalearthdata} and \code{sf} packages.
#' @param check_city Logical. If \code{TRUE} (the default), perform the
#'   city-level distance check via Nominatim geocoding. Requires an internet
#'   connection and the \code{httr} and \code{jsonlite} packages.
#' @param flag_missing_gps Logical. If \code{TRUE} (the default), surveys
#'   whose GPS coordinates are present but unusable are flagged in the log.
#'   Phone interviews (both coordinate columns empty) are governed by
#'   \code{treat_blank_gps_as_phone}, not by this argument.
#' @param treat_blank_gps_as_phone Logical. If \code{TRUE} (the default), a
#'   survey with \emph{both} coordinate columns empty is taken to be a phone
#'   interview and is excluded from every check, including the missing-GPS
#'   flag. Set to \code{FALSE} for a round known to be entirely in person, so
#'   that a completely absent geopoint is flagged instead.
#' @param nominatim_delay_s Numeric. Seconds to wait between Nominatim API
#'   requests. Must be at least 1 to comply with the usage policy. Default
#'   \code{1}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row
#'   of the dataset is treated as the ONA label/description row and excluded
#'   from all checks.
#'
#' @return A list containing:
#'   \item{checked_dataset}{The original dataset, unchanged.}
#'   \item{<log_name>}{A dataframe with columns \code{uuid},
#'     \code{old_value} (the GPS coordinates or "NA"),
#'     \code{question} (the relevant column),
#'     \code{issue} (description of the problem),
#'     \code{check_binding} (shared within each check type per survey).
#'     Three possible \code{check_binding} prefixes:
#'     \code{"location_missing_gps"}, \code{"location_country"},
#'     \code{"location_city"}.}
#' @export
validate_interview_location <- function(
  dataset,
  uuid_column = "_uuid",
  lat_column = "_location_latitude",
  lon_column = "_location_longitude",
  country_question = "Q13",
  city_question = "Q14",
  log_name = "interview_location_log",
  city_radius_km = 75,
  border_tolerance_km = 10,
  check_country = TRUE,
  check_city = TRUE,
  flag_missing_gps = TRUE,
  treat_blank_gps_as_phone = TRUE,
  nominatim_delay_s = 1,
  skip_label_row = TRUE
) {
  # ---- dependency checks ----
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("The 'sf' package is required. Install with: install.packages('sf')")
  }
  if (check_country && !requireNamespace("rnaturalearthdata", quietly = TRUE)) {
    warning(paste0(
      "'rnaturalearthdata' is required for the country check but is not installed. ",
      "Install with: install.packages('rnaturalearthdata'). ",
      "Skipping country check."
    ))
    check_country <- FALSE
  }
  if (check_city) {
    missing_pkgs <- c("httr", "jsonlite")[
      !c(
        requireNamespace("httr", quietly = TRUE),
        requireNamespace("jsonlite", quietly = TRUE)
      )
    ]
    if (length(missing_pkgs) > 0) {
      warning(paste0(
        "The following package(s) are required for the city check but are not ",
        "installed: ",
        paste(missing_pkgs, collapse = ", "),
        ". Skipping city check."
      ))
      check_city <- FALSE
    }
  }

  # ---- normalise input ----
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list.")
  }

  df_full <- dataset[["checked_dataset"]]

  required_cols <- c(
    uuid_column,
    lat_column,
    lon_column,
    country_question,
    city_question
  )
  missing_cols <- setdiff(required_cols, names(df_full))
  if (length(missing_cols) > 0) {
    stop(paste0(
      "Cannot find the following column(s) in the dataset: ",
      paste(missing_cols, collapse = ", ")
    ))
  }

  # ---- drop ONA label row ----
  if (skip_label_row && nrow(df_full) > 0) {
    df <- df_full[-1, , drop = FALSE]
  } else {
    df <- df_full
  }

  if (nrow(df) == 0) {
    warning("Dataset has no records after dropping the label row.")
    dataset[[log_name]] <- .empty_location_log()
    return(dataset)
  }

  uuids <- trimws(as.character(df[[uuid_column]]))
  lats <- suppressWarnings(as.numeric(df[[lat_column]]))
  lons <- suppressWarnings(as.numeric(df[[lon_column]]))
  countries <- trimws(as.character(df[[country_question]]))
  cities <- trimws(as.character(df[[city_question]]))

  # ---- phone interviews: BOTH coordinate columns empty ----
  # A phone interview records no geopoint at all, so both columns come back
  # empty. That is expected, not a data quality problem, and the whole
  # function has nothing to check for those surveys. Judged on the raw
  # column values (before as.numeric) so that a text value such as "n/a"
  # is treated as a bad entry rather than an empty one.
  gps_blank_both <- .is_blank_value(df[[lat_column]]) &
    .is_blank_value(df[[lon_column]])

  is_phone <- if (isTRUE(treat_blank_gps_as_phone)) {
    gps_blank_both
  } else {
    rep(FALSE, nrow(df))
  }

  if (any(is_phone)) {
    message(
      "validate_interview_location: ",
      sum(is_phone),
      " survey(s) have no geopoint in either coordinate column — treated as ",
      "phone interviews and excluded from all location checks."
    )
  }

  # ---- classify GPS validity ----
  has_valid_gps <- !is.na(lats) &
    !is.na(lons) &
    is.finite(lats) &
    is.finite(lons) &
    lats >= -90 &
    lats <= 90 &
    lons >= -180 &
    lons <= 180 &
    !(lats == 0 & lons == 0) & # (0,0) is in the Gulf of Guinea — almost certainly a default
    !is_phone

  log_parts <- list()

  # ====================================================================
  # CHECK 1: missing / invalid GPS
  # ====================================================================
  # Note: this deliberately does NOT flag phone interviews. It flags GPS that
  # is present but unusable — one coordinate filled and the other empty,
  # non-numeric text, out-of-range values, or the (0, 0) device default —
  # which is a genuine data quality problem in either interview modality.
  if (flag_missing_gps) {
    missing_gps_idx <- which(
      !has_valid_gps &
        !is_phone &
        !is.na(countries) &
        nzchar(countries)
    )
    if (length(missing_gps_idx) > 0) {
      raw_lat <- as.character(df[[lat_column]][missing_gps_idx])
      raw_lat[is.na(raw_lat) | !nzchar(raw_lat)] <- "NA"
      city_txt <- cities[missing_gps_idx]
      city_txt[is.na(city_txt) | !nzchar(city_txt)] <- "an unspecified city"

      log_parts[["missing_gps"]] <- data.frame(
        uuid = uuids[missing_gps_idx],
        old_value = raw_lat,
        question = lat_column,
        issue = paste0(
          "GPS coordinates are missing or invalid for an interview claimed to be ",
          "conducted in ",
          city_txt,
          ", ",
          countries[missing_gps_idx],
          " — interview may not have been conducted in person at the stated location"
        ),
        check_binding = paste0(
          "location_missing_gps ~/~ ",
          uuids[missing_gps_idx]
        ),
        stringsAsFactors = FALSE
      )
    }
  }

  # Only continue GPS checks for in-person surveys with valid coordinates
  valid_idx <- which(has_valid_gps)
  if (length(valid_idx) == 0) {
    message("validate_interview_location: no surveys with valid GPS to check.")
    dataset[[log_name]] <- .assemble_location_log(log_parts)
    return(dataset)
  }

  valid_lats <- lats[valid_idx]
  valid_lons <- lons[valid_idx]
  valid_uuids <- uuids[valid_idx]
  valid_countries <- countries[valid_idx]
  valid_cities <- cities[valid_idx]

  # Build sf point geometry for valid surveys (WGS84)
  pts <- sf::st_as_sf(
    data.frame(lon = valid_lons, lat = valid_lats),
    coords = c("lon", "lat"),
    crs = 4326
  )

  # ====================================================================
  # CHECK 2: country polygon containment
  # ====================================================================
  if (check_country) {
    message("validate_interview_location: running country check...")

    world <- .load_world_polygons()

    if (is.null(world)) {
      warning(paste0(
        "Could not read country polygons from 'rnaturalearthdata'. ",
        "Skipping country check."
      ))
    } else {
      # for each unique claimed country, find the matching polygon
      unique_countries <- unique(valid_countries[
        !is.na(valid_countries) & nzchar(valid_countries)
      ])

      # country_wrong[i] = TRUE if survey i's GPS is NOT in its claimed country
      country_wrong <- rep(FALSE, length(valid_idx))
      country_dist_km <- rep(NA_real_, length(valid_idx))

      for (ctry in unique_countries) {
        ctry_rows <- which(valid_countries == ctry)
        ctry_pts <- pts[ctry_rows, ]

        poly_match <- .match_country_polygon(world, ctry)

        if (length(poly_match) == 0) {
          warning(paste0(
            "Country '",
            ctry,
            "' could not be matched to a polygon in rnaturalearthdata",
            .suggest_country_names(world, ctry),
            ". Those surveys will be skipped for the country check."
          ))
          next
        }

        ctry_poly <- sf::st_geometry(world[poly_match, ])
        if (length(ctry_poly) > 1) {
          ctry_poly <- sf::st_union(ctry_poly)
        }

        # Points strictly inside the polygon are fine. For the rest, measure
        # the geodesic distance to the border and only flag those further out
        # than the tolerance. (Deliberately NOT st_buffer(): on lon/lat data
        # the meaning of `dist` depends on whether s2 is enabled, which makes
        # a metre-based buffer unreliable.)
        inside <- suppressMessages(
          lengths(sf::st_intersects(ctry_pts, ctry_poly)) > 0
        )

        outside_rows <- which(!inside)
        if (length(outside_rows) > 0) {
          d_m <- suppressMessages(as.numeric(
            sf::st_distance(ctry_pts[outside_rows, ], ctry_poly)
          ))
          too_far <- d_m > (border_tolerance_km * 1000)
          country_wrong[ctry_rows[outside_rows[too_far]]] <- TRUE
          country_dist_km[ctry_rows[outside_rows]] <- d_m / 1000
        }
      }

      wrong_country_pos <- which(country_wrong)
      wrong_country_idx <- valid_idx[wrong_country_pos]
      if (length(wrong_country_idx) > 0) {
        dist_txt <- ifelse(
          is.na(country_dist_km[wrong_country_pos]),
          "",
          paste0(
            " — approximately ",
            round(country_dist_km[wrong_country_pos], 1),
            "km outside its border"
          )
        )
        log_parts[["country"]] <- data.frame(
          uuid = uuids[wrong_country_idx],
          old_value = paste0(
            round(lats[wrong_country_idx], 5),
            ", ",
            round(lons[wrong_country_idx], 5)
          ),
          question = country_question,
          issue = paste0(
            "GPS coordinates (",
            round(lats[wrong_country_idx], 4),
            ", ",
            round(lons[wrong_country_idx], 4),
            ") ",
            "do not fall within the claimed country: '",
            countries[wrong_country_idx],
            "'",
            dist_txt
          ),
          check_binding = paste0(
            "location_country ~/~ ",
            uuids[wrong_country_idx]
          ),
          stringsAsFactors = FALSE
        )
      }
      message("  Country check: ", sum(country_wrong), " survey(s) flagged.")
    }
  }

  # ====================================================================
  # CHECK 3: city distance via Nominatim geocoding
  # ====================================================================
  if (check_city) {
    message(
      "validate_interview_location: geocoding unique city+country combinations..."
    )

    nominatim_delay_s <- max(nominatim_delay_s, 1) # enforce usage policy

    # geocode only unique city+country pairs — not every row.
    # Normalised keys mean case / spacing variants are geocoded once.
    survey_key <- .location_key(valid_cities, valid_countries)

    pairs <- data.frame(
      city = valid_cities,
      country = valid_countries,
      key = survey_key,
      stringsAsFactors = FALSE
    )
    pairs <- pairs[
      !is.na(pairs$city) &
        nzchar(pairs$city) &
        !is.na(pairs$country) &
        nzchar(pairs$country),
      ,
      drop = FALSE
    ]
    pairs <- pairs[!duplicated(pairs$key), , drop = FALSE]

    gc_results <- vector("list", nrow(pairs))
    for (k in seq_len(nrow(pairs))) {
      city_k <- pairs$city[k]
      country_k <- pairs$country[k]
      message(sprintf(
        "  Geocoding %d/%d: %s, %s",
        k,
        nrow(pairs),
        city_k,
        country_k
      ))
      hit <- .geocode_nominatim(city_k, country_k)
      if (!is.null(hit)) {
        hit$key <- pairs$key[k]
        gc_results[[k]] <- hit
      }
      if (k < nrow(pairs)) Sys.sleep(nominatim_delay_s)
    }

    gc_results <- gc_results[!vapply(gc_results, is.null, logical(1))]
    gc_table <- if (length(gc_results) > 0) {
      do.call(rbind, gc_results)
    } else {
      NULL
    }

    geocoded_keys <- if (is.null(gc_table)) character(0) else gc_table$key
    failed_pairs <- pairs[!(pairs$key %in% geocoded_keys), , drop = FALSE]
    if (nrow(failed_pairs) > 0) {
      warning(paste0(
        "Could not geocode the following city+country combination(s) — ",
        "those surveys are excluded from the city check: ",
        paste(
          paste0(failed_pairs$city, ", ", failed_pairs$country),
          collapse = "; "
        ),
        ". Check the spelling against OpenStreetMap, or confirm the machine ",
        "has internet access to nominatim.openstreetmap.org."
      ))
    }

    if (!is.null(gc_table) && nrow(gc_table) > 0) {
      # build city centroid sf points
      city_pts <- sf::st_as_sf(
        gc_table,
        coords = c("gc_lon", "gc_lat"),
        crs = 4326
      )

      city_far <- rep(FALSE, length(valid_idx))
      city_dist_m <- rep(NA_real_, length(valid_idx))

      for (k in seq_len(nrow(gc_table))) {
        survey_rows <- which(survey_key == gc_table$key[k])
        if (length(survey_rows) == 0) {
          next
        }

        survey_pts_k <- pts[survey_rows, ]
        city_pt_k <- city_pts[k, ]

        # geodesic distances in metres
        dists <- suppressMessages(as.numeric(
          sf::st_distance(survey_pts_k, city_pt_k)
        ))
        too_far <- dists > (city_radius_km * 1000)

        city_far[survey_rows[too_far]] <- TRUE
        city_dist_m[survey_rows] <- dists
      }

      far_city_idx <- valid_idx[city_far]
      if (length(far_city_idx) > 0) {
        dist_km_flagged <- round(city_dist_m[city_far] / 1000, 1)
        log_parts[["city"]] <- data.frame(
          uuid = uuids[far_city_idx],
          old_value = paste0(
            round(lats[far_city_idx], 5),
            ", ",
            round(lons[far_city_idx], 5)
          ),
          question = city_question,
          issue = paste0(
            "GPS coordinates are ",
            dist_km_flagged,
            "km from the centre of ",
            "'",
            cities[far_city_idx],
            "', ",
            countries[far_city_idx],
            " (threshold: ",
            city_radius_km,
            "km). ",
            "Interview may not have been conducted in the claimed city."
          ),
          check_binding = paste0("location_city ~/~ ", uuids[far_city_idx]),
          stringsAsFactors = FALSE
        )
      }
      message("  City check: ", sum(city_far), " survey(s) flagged.")
    }
  }

  # ====================================================================
  # Assemble and return
  # ====================================================================
  log <- .assemble_location_log(log_parts)
  dataset[[log_name]] <- log

  n_flags <- nrow(log)
  message(paste0(
    "validate_interview_location: ",
    n_flags,
    " total flag(s) across ",
    length(unique(log$uuid[!is.na(log$uuid)])),
    " survey(s)."
  ))
  return(dataset)
}

# ---- internal helpers -------------------------------------------------------

#' Is a raw column value empty? (NA, "", or whitespace only)
#' @keywords internal
#' @noRd
.is_blank_value <- function(x) {
  x <- as.character(x)
  is.na(x) | !nzchar(trimws(x))
}

#' @keywords internal
#' @noRd
.empty_location_log <- function() {
  data.frame(
    uuid = character(0),
    old_value = character(0),
    question = character(0),
    issue = character(0),
    check_binding = character(0),
    stringsAsFactors = FALSE
  )
}

#' @keywords internal
#' @noRd
.assemble_location_log <- function(log_parts) {
  if (length(log_parts) == 0) {
    return(.empty_location_log())
  }
  out <- do.call(rbind, log_parts)
  out$old_value <- as.character(out$old_value)
  rownames(out) <- NULL
  out <- out[order(out$uuid, out$check_binding), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Normalised city+country key
#' @keywords internal
#' @noRd
.location_key <- function(city, country) {
  norm <- function(x) {
    x <- tolower(trimws(as.character(x)))
    gsub("\\s+", " ", x)
  }
  paste0(norm(city), " ~ ", norm(country))
}

#' Load Natural Earth country polygons as an sf object, in EPSG:4326
#' @keywords internal
#' @noRd
.load_world_polygons <- function() {
  world <- tryCatch(
    {
      w <- rnaturalearthdata::countries50
      if (!inherits(w, "sf")) {
        w <- sf::st_as_sf(w)
      }
      w
    },
    error = function(e) NULL
  )
  if (is.null(world)) {
    return(NULL)
  }

  crs_now <- tryCatch(sf::st_crs(world), error = function(e) NA)
  if (is.na(crs_now)) {
    sf::st_crs(world) <- 4326
  } else if (!isTRUE(crs_now == sf::st_crs(4326))) {
    world <- sf::st_transform(world, crs = 4326)
  }
  world
}

#' Candidate country-name / ISO-code fields, resolved case-insensitively
#' @keywords internal
#' @noRd
.country_name_fields <- function(world) {
  wanted <- c(
    "admin",
    "name",
    "name_long",
    "sovereignt",
    "formal_en",
    "name_en",
    "name_sort",
    "geounit",
    "subunit",
    "brk_name",
    "iso_a2",
    "iso_a2_eh",
    "iso_a3",
    "iso_a3_eh",
    "adm0_a3"
  )
  nm <- names(world)
  idx <- match(wanted, tolower(nm))
  nm[idx[!is.na(idx)]]
}

#' Common alternative country spellings seen in humanitarian datasets
#' @keywords internal
#' @noRd
.country_aliases <- function(ctry) {
  key <- tolower(gsub("\\s+", " ", trimws(ctry)))
  map <- list(
    "drc" = "Democratic Republic of the Congo",
    "dr congo" = "Democratic Republic of the Congo",
    "dr.congo" = "Democratic Republic of the Congo",
    "congo (drc)" = "Democratic Republic of the Congo",
    "congo, dem. rep." = "Democratic Republic of the Congo",
    "congo-kinshasa" = "Democratic Republic of the Congo",
    "congo-brazzaville" = "Republic of the Congo",
    "congo" = "Republic of the Congo",
    "ivory coast" = "Ivory Coast",
    "cote d'ivoire" = "Ivory Coast",
    "cote d ivoire" = "Ivory Coast",
    "côte d'ivoire" = "Ivory Coast",
    "syria" = "Syria",
    "syrian arab republic" = "Syria",
    "iran" = "Iran",
    "islamic republic of iran" = "Iran",
    "tanzania" = "Tanzania",
    "united republic of tanzania" = "Tanzania",
    "uae" = "United Arab Emirates",
    "uk" = "United Kingdom",
    "usa" = "United States of America",
    "united states" = "United States of America",
    "us" = "United States of America",
    "south korea" = "South Korea",
    "north korea" = "North Korea",
    "cape verde" = "Cabo Verde",
    "swaziland" = "eSwatini",
    "eswatini" = "eSwatini",
    "burma" = "Myanmar",
    "myanmar/burma" = "Myanmar",
    "the gambia" = "Gambia",
    "gambia, the" = "Gambia",
    "turkiye" = "Turkey",
    "türkiye" = "Turkey",
    "czechia" = "Czechia",
    "czech republic" = "Czechia",
    "macedonia" = "North Macedonia",
    "palestine" = "Palestine",
    "occupied palestinian territory" = "Palestine",
    "state of palestine" = "Palestine",
    "west bank" = "Palestine",
    "gaza" = "Palestine",
    "laos" = "Laos",
    "moldova" = "Moldova",
    "russia" = "Russia",
    "russian federation" = "Russia",
    "bolivia" = "Bolivia",
    "venezuela" = "Venezuela",
    "vietnam" = "Vietnam",
    "viet nam" = "Vietnam",
    "egypt" = "Egypt",
    "libya" = "Libya",
    "sudan" = "Sudan",
    "south sudan" = "South Sudan",
    "somaliland" = "Somaliland",
    "somalia" = "Somalia"
  )
  if (!is.null(map[[key]])) map[[key]] else NULL
}

#' Row indices of the Natural Earth polygon(s) matching a country name/code
#' @keywords internal
#' @noRd
.match_country_polygon <- function(world, ctry) {
  fields <- .country_name_fields(world)
  if (length(fields) == 0) {
    return(integer(0))
  }

  targets <- tolower(gsub("\\s+", " ", trimws(ctry)))
  alias <- .country_aliases(ctry)
  if (!is.null(alias)) {
    targets <- unique(c(targets, tolower(alias)))
  }
  # "the "/"republic of " style prefixes
  targets <- unique(c(
    targets,
    sub("^the ", "", targets),
    sub("^republic of ", "", targets)
  ))

  hit <- rep(FALSE, nrow(world))
  for (f in fields) {
    vals <- tolower(gsub("\\s+", " ", trimws(as.character(world[[f]]))))
    hit <- hit | (!is.na(vals) & vals %in% targets)
  }
  which(hit)
}

#' Build a "did you mean" fragment for an unmatched country name
#' @keywords internal
#' @noRd
.suggest_country_names <- function(world, ctry) {
  fields <- .country_name_fields(world)
  if (length(fields) == 0) {
    return(paste0(
      " (no recognisable country-name columns found in the installed ",
      "rnaturalearthdata; expected one of: admin, name, name_long)"
    ))
  }
  admin_field <- intersect(c("admin", "ADMIN"), fields)
  pool_field <- if (length(admin_field) > 0) admin_field[1] else fields[1]
  pool <- unique(as.character(world[[pool_field]]))
  pool <- pool[!is.na(pool)]
  near <- tryCatch(
    agrep(ctry, pool, ignore.case = TRUE, max.distance = 0.3, value = TRUE),
    error = function(e) character(0)
  )
  if (length(near) == 0) {
    return("")
  }
  paste0(" (did you mean: ", paste(utils::head(near, 3), collapse = ", "), "?)")
}

#' Geocode one city+country pair via Nominatim
#'
#' Tries the structured query first, then a free-form query. Returns a
#' one-row dataframe (city, country, gc_lat, gc_lon, gc_name) or NULL.
#' @keywords internal
#' @noRd
.geocode_nominatim <- function(city, country) {
  ua <- "cleaningkit R package / MMC 4Mi data validation"

  fetch <- function(url) {
    tryCatch(
      {
        resp <- httr::GET(url, httr::user_agent(ua), httr::timeout(20))
        if (httr::status_code(resp) != 200) {
          return(NULL)
        }
        # Parse the body ourselves rather than relying on httr's automatic
        # simplification: with simplifyVector = TRUE a JSON array of objects
        # becomes a data.frame, and indexing it as a list returns COLUMNS,
        # not the first result.
        txt <- httr::content(resp, as = "text", encoding = "UTF-8")
        if (is.null(txt) || !nzchar(txt)) {
          return(NULL)
        }
        parsed <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
        if (length(parsed) == 0) {
          return(NULL)
        }
        first <- parsed[[1]]
        gc_lat <- suppressWarnings(as.numeric(first$lat))
        gc_lon <- suppressWarnings(as.numeric(first$lon))
        if (
          length(gc_lat) != 1 ||
            length(gc_lon) != 1 ||
            is.na(gc_lat) ||
            is.na(gc_lon)
        ) {
          return(NULL)
        }
        data.frame(
          city = city,
          country = country,
          gc_lat = gc_lat,
          gc_lon = gc_lon,
          gc_name = if (is.null(first$display_name)) {
            NA_character_
          } else {
            as.character(first$display_name)[1]
          },
          stringsAsFactors = FALSE
        )
      },
      error = function(e) NULL
    )
  }

  # 1. structured query (city= + country=)
  url_structured <- paste0(
    "https://nominatim.openstreetmap.org/search",
    "?city=",
    utils::URLencode(city, reserved = TRUE),
    "&country=",
    utils::URLencode(country, reserved = TRUE),
    "&format=json&limit=1&addressdetails=0"
  )
  out <- fetch(url_structured)
  if (!is.null(out)) {
    return(out)
  }

  # 2. free-form fallback — resolves towns, border crossings and settlements
  #    that OSM does not tag as a city
  url_free <- paste0(
    "https://nominatim.openstreetmap.org/search",
    "?q=",
    utils::URLencode(paste0(city, ", ", country), reserved = TRUE),
    "&format=json&limit=1&addressdetails=0"
  )
  fetch(url_free)
}
