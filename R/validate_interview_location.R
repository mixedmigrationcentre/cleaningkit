#' Validate Interview Location Against Claimed Country and City
#'
#' Checks whether the GPS coordinates recorded during an in-person interview
#' are plausibly consistent with the country and city the respondent claims
#' the interview was conducted in. Two independent checks are performed:
#'
#' \enumerate{
#'   \item \strong{Country check} (requires \code{rnaturalearthdata}): tests
#'     whether the GPS point falls inside the polygon of the claimed country.
#'   \item \strong{City check}: geocodes each unique city+country combination
#'     in the dataset once via the Nominatim/OpenStreetMap API, then checks
#'     whether the GPS point is within \code{city_radius_km} kilometres of the
#'     city centre. Requires an internet connection.
#' }
#'
#' Surveys with no GPS coordinates are flagged separately — in an in-person
#' survey a missing GPS point may indicate the interview was not actually
#' conducted at the claimed location, or that the device GPS was disabled.
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
#' (e.g. "Kampala", "Nairobi", "Addis Ababa"). Minor variations are usually
#' handled by OSM's search engine. If a city cannot be geocoded, those surveys
#' are excluded from the city check and a warning is issued.
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
#' @param check_country Logical. If \code{TRUE} (the default), perform the
#'   country-level polygon containment check. Requires the
#'   \code{rnaturalearthdata} and \code{sf} packages.
#' @param check_city Logical. If \code{TRUE} (the default), perform the
#'   city-level distance check via Nominatim geocoding. Requires an internet
#'   connection.
#' @param flag_missing_gps Logical. If \code{TRUE} (the default), surveys
#'   with missing or invalid GPS coordinates are flagged in the log.
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
  check_country = TRUE,
  check_city = TRUE,
  flag_missing_gps = TRUE,
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

  # ---- classify GPS validity ----
  has_valid_gps <- !is.na(lats) &
    !is.na(lons) &
    is.finite(lats) &
    is.finite(lons) &
    lats >= -90 &
    lats <= 90 &
    lons >= -180 &
    lons <= 180 &
    !(lats == 0 & lons == 0) # (0,0) is in the Gulf of Guinea — almost certainly a default

  log_parts <- list()

  # ====================================================================
  # CHECK 1: missing / invalid GPS
  # ====================================================================
  if (flag_missing_gps) {
    missing_gps_idx <- which(
      !has_valid_gps &
        !is.na(countries) &
        nzchar(countries)
    )
    if (length(missing_gps_idx) > 0) {
      log_parts[["missing_gps"]] <- data.frame(
        uuid = uuids[missing_gps_idx],
        old_value = as.character(df[[lat_column]][missing_gps_idx]),
        question = lat_column,
        issue = paste0(
          "GPS coordinates are missing or invalid for an interview claimed to be ",
          "conducted in ",
          cities[missing_gps_idx],
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

  # Only continue GPS checks for surveys with valid coordinates
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

    world <- sf::st_as_sf(
      rnaturalearthdata::countries50,
      quiet = TRUE
    )
    # ensure same CRS
    world <- sf::st_transform(world, crs = 4326)
    sf::st_crs(pts) <- 4326

    # for each unique claimed country, find the matching polygon
    unique_countries <- unique(valid_countries[
      !is.na(valid_countries) & nzchar(valid_countries)
    ])

    # country_wrong[i] = TRUE if survey i's GPS is NOT in its claimed country
    country_wrong <- rep(FALSE, length(valid_idx))

    for (ctry in unique_countries) {
      ctry_rows <- which(valid_countries == ctry)
      ctry_pts <- pts[ctry_rows, ]

      # flexible name matching against multiple name fields
      poly_match <- which(
        tolower(world$NAME_LONG) == tolower(ctry) |
          tolower(world$NAME) == tolower(ctry) |
          tolower(world$ADMIN) == tolower(ctry)
      )

      if (length(poly_match) == 0) {
        warning(paste0(
          "Country '",
          ctry,
          "' could not be matched to a polygon in ",
          "rnaturalearthdata. Those surveys will be skipped for the country check."
        ))
        next
      }

      ctry_poly <- world[poly_match[1], ]

      # slightly buffer the polygon to handle GPS points just outside borders
      ctry_poly_buf <- sf::st_buffer(ctry_poly, dist = 10000) # 10km buffer

      contained <- suppressMessages(
        lengths(sf::st_within(ctry_pts, ctry_poly_buf)) > 0
      )
      country_wrong[ctry_rows[!contained]] <- TRUE
    }

    wrong_country_idx <- valid_idx[country_wrong]
    if (length(wrong_country_idx) > 0) {
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
          "'"
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

  # ====================================================================
  # CHECK 3: city distance via Nominatim geocoding
  # ====================================================================
  if (check_city) {
    message(
      "validate_interview_location: geocoding unique city+country combinations..."
    )

    nominatim_delay_s <- max(nominatim_delay_s, 1) # enforce usage policy

    # geocode only unique city+country pairs — not every row
    pairs <- unique(data.frame(
      city = valid_cities,
      country = valid_countries,
      stringsAsFactors = FALSE
    ))
    pairs <- pairs[
      !is.na(pairs$city) &
        nzchar(pairs$city) &
        !is.na(pairs$country) &
        nzchar(pairs$country),
    ]

    geocode_nominatim <- function(city, country) {
      url <- paste0(
        "https://nominatim.openstreetmap.org/search",
        "?city=",
        utils::URLencode(city, reserved = TRUE),
        "&country=",
        utils::URLencode(country, reserved = TRUE),
        "&format=json&limit=1&addressdetails=0"
      )
      tryCatch(
        {
          resp <- httr::GET(
            url,
            httr::user_agent("cleaningkit R package / MMC data validation"),
            httr::timeout(10)
          )
          if (httr::status_code(resp) != 200) {
            return(NULL)
          }
          parsed <- httr::content(resp, as = "parsed", simplifyVector = TRUE)
          if (length(parsed) == 0) {
            return(NULL)
          }
          data.frame(
            city = city,
            country = country,
            gc_lat = as.numeric(parsed[[1]]$lat),
            gc_lon = as.numeric(parsed[[1]]$lon),
            gc_name = parsed[[1]]$display_name,
            stringsAsFactors = FALSE
          )
        },
        error = function(e) NULL
      )
    }

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
      gc_results[[k]] <- geocode_nominatim(city_k, country_k)
      if (k < nrow(pairs)) Sys.sleep(nominatim_delay_s)
    }

    gc_table <- do.call(
      rbind,
      gc_results[!vapply(gc_results, is.null, logical(1))]
    )

    failed_pairs <- pairs[
      !(paste(pairs$city, pairs$country) %in%
        paste(gc_table$city, gc_table$country)),
    ]
    if (nrow(failed_pairs) > 0) {
      warning(paste0(
        "Could not geocode the following city+country combination(s) — ",
        "those surveys are excluded from the city check: ",
        paste(
          paste0(failed_pairs$city, ", ", failed_pairs$country),
          collapse = "; "
        )
      ))
    }

    if (!is.null(gc_table) && nrow(gc_table) > 0) {
      # build city centroid sf points
      city_pts <- sf::st_as_sf(
        gc_table,
        coords = c("gc_lon", "gc_lat"),
        crs = 4326
      )

      # match each survey to its geocoded city centroid
      pair_key_survey <- paste(valid_cities, valid_countries)
      pair_key_gc <- paste(gc_table$city, gc_table$country)

      city_far <- rep(FALSE, length(valid_idx))
      city_dist_m <- rep(NA_real_, length(valid_idx))

      for (k in seq_len(nrow(gc_table))) {
        survey_rows <- which(pair_key_survey == pair_key_gc[k])
        if (length(survey_rows) == 0) {
          next
        }

        survey_pts_k <- pts[survey_rows, ]
        city_pt_k <- city_pts[k, ]

        # geodesic distances in metres
        dists <- as.numeric(sf::st_distance(survey_pts_k, city_pt_k))
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

#' @keywords internal
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
.assemble_location_log <- function(log_parts) {
  if (length(log_parts) == 0) {
    return(.empty_location_log())
  }
  out <- do.call(rbind, log_parts)
  out$old_value <- as.character(out$old_value)
  rownames(out) <- NULL
  out[order(out$uuid, out$check_binding), ]
}
