# Tests for validate_interview_location()
#
# The country check runs entirely offline against rnaturalearthdata, so it is
# always tested. The city check needs Nominatim, so it is tested against a
# mocked HTTP layer (skipped on testthat < 3.2.0, which has no
# local_mocked_bindings()).

# ---- fixtures ---------------------------------------------------------------

loc_test_data <- function() {
  data.frame(
    `_uuid` = c("LABEL", "u1", "u2", "u3", "u4", "u5", "u6", "u7"),
    # u1 Quetta/Quetta GPS           -> clean
    # u2 Karachi/Karachi GPS         -> clean
    # u3 Quetta claimed, Karachi GPS -> city flag only
    # u4 Quetta claimed, Tehran GPS  -> country + city flag
    # u5 BOTH coordinates blank      -> phone interview, skipped entirely
    # u6 Chaman (border town), GPS at Chaman -> clean
    # u7 lat present, lon blank      -> unusable GPS: warning only, never logged
    `_location_latitude` = c(
      "latitude",
      "30.1900",
      "24.8600",
      "24.8600",
      "35.6892",
      NA,
      "30.9200",
      "34.0083"
    ),
    `_location_longitude` = c(
      "longitude",
      "67.0000",
      "67.0200",
      "67.0200",
      "51.3890",
      NA,
      "66.4500",
      NA
    ),
    Q13 = c("country of interview", rep("Pakistan", 7)),
    Q14 = c(
      "city of interview",
      "Quetta",
      "Karachi",
      "Quetta",
      "Quetta",
      "Peshawar",
      "Chaman",
      "Peshawar"
    ),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

loc_run <- function(...) {
  suppressWarnings(suppressMessages(validate_interview_location(...)))
}

loc_bindings <- function(x) {
  x$check_binding
}

# Run the function and keep the warnings as text. Unusable GPS is reported as a
# console warning rather than a log row, so most assertions about it have to be
# made against the warning.
loc_capture <- function(...) {
  w <- character(0)
  res <- withCallingHandlers(
    suppressMessages(validate_interview_location(...)),
    warning = function(cond) {
      w <<- c(w, conditionMessage(cond))
      invokeRestart("muffleWarning")
    }
  )
  list(result = res, warnings = w)
}

# A dataset carrying the raw ONA geopoint column alongside the split columns.
#
# g1 split columns valid (Quetta); location says Tehran -> location IGNORED
# g2 split columns emptied by Excel; location says Tehran -> rescued, flags
# g3 nothing anywhere -> phone interview, skipped entirely
# g4 split columns empty; location present but unparseable -> unusable
loc_geopoint_data <- function() {
  data.frame(
    `_uuid` = c("LABEL", "g1", "g2", "g3", "g4"),
    `_location_latitude` = c("latitude", "30.1900", NA, NA, NA),
    `_location_longitude` = c("longitude", "67.0000", NA, NA, NA),
    location = c(
      "location",
      "35.6892 51.3890 1200.0 10.0",
      "35.6892 51.3890 1200.0 10.0",
      NA,
      "not a geopoint"
    ),
    Q13 = c("country of interview", rep("Pakistan", 4)),
    Q14 = c("city of interview", rep("Quetta", 4)),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

# ---- country name / code matching ------------------------------------------

test_that("country names, ISO codes and aliases match a Natural Earth polygon", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearthdata")

  world <- .load_world_polygons()
  expect_false(is.null(world))

  # This is the regression guard for the original bug: the name columns in
  # rnaturalearthdata are lower-case (admin / name / name_long), so a
  # hard-coded upper-case lookup matched nothing and every country warned.
  expect_gt(length(.country_name_fields(world)), 0)

  expect_length(.match_country_polygon(world, "Pakistan"), 1)
  expect_length(.match_country_polygon(world, "pakistan"), 1)
  expect_length(.match_country_polygon(world, "  PAKISTAN  "), 1)
  expect_length(.match_country_polygon(world, "PAK"), 1)
  expect_length(.match_country_polygon(world, "PK"), 1)
  expect_gte(length(.match_country_polygon(world, "DRC")), 1)
  expect_gte(length(.match_country_polygon(world, "Ivory Coast")), 1)
  expect_gte(length(.match_country_polygon(world, "Syria")), 1)

  # a genuine typo still fails, but helpfully
  expect_length(.match_country_polygon(world, "Pakisstan"), 0)
  expect_match(.suggest_country_names(world, "Pakisstan"), "did you mean")
})

test_that("an unmatched country warns and is skipped, not silently passed", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearthdata")

  d <- loc_test_data()
  d$Q13[-1] <- "Pakisstan"
  expect_warning(
    suppressMessages(validate_interview_location(
      d,
      check_city = FALSE,
      flag_missing_gps = FALSE # keep the unusable-GPS warning out of the way
    )),
    "could not be matched to a polygon"
  )
})

# ---- country containment check ---------------------------------------------

test_that("country check flags GPS outside the claimed country only", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearthdata")

  res <- loc_run(loc_test_data(), check_city = FALSE)
  log <- res$interview_location_log

  expect_true(any(grepl("^location_country ~/~ u4", loc_bindings(log))))
  for (u in c("u1", "u2", "u3", "u6")) {
    expect_false(any(grepl(
      paste0("^location_country ~/~ ", u, "$"),
      loc_bindings(log)
    )))
  }
})

test_that("border_tolerance_km controls how far outside the border is allowed", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearthdata")

  # a point ~25.5km outside the Pakistan/Iran border
  d <- data.frame(
    `_uuid` = c("LABEL", "b1"),
    `_location_latitude` = c("lat", "29.8290"),
    `_location_longitude` = c("lon", "61.8000"),
    Q13 = c("c", "Pakistan"),
    Q14 = c("c", "Taftan"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )

  wide <- loc_run(d, check_city = FALSE, border_tolerance_km = 30)
  tight <- loc_run(d, check_city = FALSE, border_tolerance_km = 10)

  expect_equal(nrow(wide$interview_location_log), 0)
  expect_equal(nrow(tight$interview_location_log), 1)
  expect_match(tight$interview_location_log$issue[1], "outside its border")
})

# ---- missing / invalid GPS --------------------------------------------------
#
# Unusable GPS is NOT a cleaning-log entry. There is nothing an enumerator can
# correct, and one row per survey buried the country and city flags that matter.
# It is reported as a console warning instead, and these tests assert both
# halves of that: the warning fires, and the log stays empty.

test_that("unusable GPS is reported as a warning and never written to the log", {
  skip_if_not_installed("sf")

  out <- loc_capture(
    loc_test_data(),
    check_country = FALSE,
    check_city = FALSE
  )

  # u7 has a latitude but no longitude — a real data problem, but not a
  # cleaning-log one
  expect_equal(nrow(out$result$interview_location_log), 0)
  expect_true(any(grepl("NOT written to the cleaning log", out$warnings)))
  expect_true(any(grepl("u7", out$warnings)))
  expect_false(any(grepl("location_missing_gps", loc_bindings(
    out$result$interview_location_log
  ))))
})

test_that("(0, 0) and non-numeric coordinates count as unusable", {
  skip_if_not_installed("sf")

  # (0, 0) is the Gulf of Guinea — a device default, not a real fix
  d <- loc_test_data()
  d$`_location_latitude`[2] <- "0"
  d$`_location_longitude`[2] <- "0"
  out0 <- loc_capture(d, check_country = FALSE, check_city = FALSE)
  expect_true(any(grepl("u1", out0$warnings)))
  expect_equal(nrow(out0$result$interview_location_log), 0)

  # non-numeric text is a bad entry, not a phone interview
  dtxt <- loc_test_data()
  dtxt$`_location_latitude`[2] <- "n/a"
  dtxt$`_location_longitude`[2] <- "n/a"
  outtxt <- loc_capture(dtxt, check_country = FALSE, check_city = FALSE)
  expect_true(any(grepl("u1", outtxt$warnings)))
  expect_equal(nrow(outtxt$result$interview_location_log), 0)
})

test_that("flag_missing_gps = FALSE suppresses the warning too", {
  skip_if_not_installed("sf")

  out <- loc_capture(
    loc_test_data(),
    check_country = FALSE,
    check_city = FALSE,
    flag_missing_gps = FALSE
  )
  expect_length(out$warnings, 0)
  expect_equal(nrow(out$result$interview_location_log), 0)
})

# ---- raw geopoint fallback --------------------------------------------------

test_that(".parse_location_geopoint splits the four ONA components", {
  p <- .parse_location_geopoint(c(
    "33.9820598 71.5482743 317.4000244140625 18.033",
    "  30.19   67.00   1650   4.2  ",
    "24.86,67.02,8,18",
    "12.5 13.5",
    "not a geopoint",
    NA,
    ""
  ))

  expect_equal(p$lat[1], 33.9820598)
  expect_equal(p$lon[1], 71.5482743)
  expect_equal(p$altitude[1], 317.4000244140625)
  expect_equal(p$precision[1], 18.033)

  # tolerant of padded / repeated whitespace and of comma separators
  expect_equal(p$lat[2], 30.19)
  expect_equal(p$precision[2], 4.2)
  expect_equal(p$lon[3], 67.02)

  # missing components, junk and blanks all come back NA rather than erroring
  expect_equal(p$lat[4], 12.5)
  expect_true(is.na(p$altitude[4]))
  expect_true(is.na(p$lat[5]))
  expect_true(is.na(p$lat[6]))
  expect_true(is.na(p$lat[7]))

  # zero-length input returns a zero-row frame, not an error
  expect_equal(nrow(.parse_location_geopoint(character(0))), 0)
})

test_that(".is_valid_coord rejects out-of-range and (0, 0) coordinates", {
  expect_true(.is_valid_coord(30.19, 67.00))
  expect_false(.is_valid_coord(0, 0))
  expect_false(.is_valid_coord(91, 10))
  expect_false(.is_valid_coord(10, 181))
  expect_false(.is_valid_coord(NA, 10))
  expect_false(.is_valid_coord("n/a", 10))
  expect_equal(
    .is_valid_coord(c(30.19, 0, NA), c(67.00, 0, 10)),
    c(TRUE, FALSE, FALSE)
  )
})

test_that("the location column rescues coordinates Excel has destroyed", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearthdata")

  out <- loc_capture(loc_geopoint_data(), check_city = FALSE)
  log <- out$result$interview_location_log

  # g2's split columns are empty but its geopoint is intact and sits in Tehran,
  # so the country check runs on the recovered coordinates and flags it
  expect_true(any(grepl("^location_country ~/~ g2", loc_bindings(log))))

  # g1's split columns are valid: the (conflicting) location value is ignored
  expect_false(any(grepl("~/~ g1", loc_bindings(log))))

  # g3 has nothing anywhere -> phone interview, not even in the warning
  expect_false(any(grepl("~/~ g3", loc_bindings(log))))
  expect_false(any(grepl("g3", out$warnings)))

  # g4's geopoint is present but unparseable -> warning, never a log row
  expect_false(any(grepl("~/~ g4", loc_bindings(log))))
  expect_true(any(grepl("g4", out$warnings)))
})

test_that("use_location_fallback = FALSE ignores the location column", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearthdata")

  res <- loc_run(
    loc_geopoint_data(),
    check_city = FALSE,
    use_location_fallback = FALSE
  )
  # g2 is no longer rescued, so nothing is flagged at all
  expect_false(any(grepl(
    "~/~ g2",
    loc_bindings(res$interview_location_log)
  )))
})

test_that("a dataset without a location column behaves exactly as before", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearthdata")

  # loc_test_data() has no `location` column at all
  res <- loc_run(loc_test_data(), check_city = FALSE)
  expect_true(any(grepl(
    "^location_country ~/~ u4",
    loc_bindings(res$interview_location_log)
  )))
})

test_that("a custom location_column name is honoured", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearthdata")

  d <- loc_geopoint_data()
  names(d)[names(d) == "location"] <- "_geopoint"

  res <- loc_run(d, check_city = FALSE, location_column = "_geopoint")
  expect_true(any(grepl(
    "^location_country ~/~ g2",
    loc_bindings(res$interview_location_log)
  )))
})

# ---- phone interviews -------------------------------------------------------

test_that("both coordinates blank is treated as a phone interview and skipped", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearthdata")

  res <- loc_run(loc_test_data(), check_city = FALSE)
  log <- res$interview_location_log

  # u5 has no geopoint at all -> no flag of any kind
  expect_false("u5" %in% log$uuid)
  expect_false(any(grepl("~/~ u5$", loc_bindings(log))))
})

test_that("NA, empty string and whitespace all count as a blank coordinate", {
  skip_if_not_installed("sf")

  for (blank in list(NA, "", "   ", "\t")) {
    d <- loc_test_data()
    d$`_location_latitude`[6] <- blank
    d$`_location_longitude`[6] <- blank
    res <- loc_run(d, check_country = FALSE, check_city = FALSE)
    expect_false(
      "u5" %in% res$interview_location_log$uuid,
      info = paste0("blank form: '", blank, "'")
    )
  }
})

test_that("an all-phone dataset returns an empty log without erroring", {
  skip_if_not_installed("sf")

  d <- loc_test_data()
  d$`_location_latitude`[-1] <- NA
  d$`_location_longitude`[-1] <- NA
  res <- loc_run(d, check_country = FALSE, check_city = FALSE)
  expect_equal(nrow(res$interview_location_log), 0)
  expect_named(
    res$interview_location_log,
    c("uuid", "old_value", "question", "issue", "check_binding")
  )
})

test_that("treat_blank_gps_as_phone = FALSE counts a fully absent geopoint", {
  skip_if_not_installed("sf")

  on_out <- loc_capture(
    loc_test_data(),
    check_country = FALSE,
    check_city = FALSE,
    treat_blank_gps_as_phone = TRUE
  )
  off_out <- loc_capture(
    loc_test_data(),
    check_country = FALSE,
    check_city = FALSE,
    treat_blank_gps_as_phone = FALSE
  )

  # u5 has no geopoint at all: a phone interview when TRUE, unusable when FALSE
  expect_false(any(grepl("u5", on_out$warnings)))
  expect_true(any(grepl("u5", off_out$warnings)))

  # u7 is reported either way — its GPS is present but unusable
  expect_true(any(grepl("u7", on_out$warnings)))
  expect_true(any(grepl("u7", off_out$warnings)))

  # and neither ever reaches the log
  expect_equal(nrow(on_out$result$interview_location_log), 0)
  expect_equal(nrow(off_out$result$interview_location_log), 0)
})

test_that("phone interviews are not geocoded", {
  skip_if_not_installed("sf")
  skip_if_not_installed("httr")
  skip_if_not_installed("jsonlite")
  skip_if(
    !exists("local_mocked_bindings", asNamespace("testthat")),
    "needs testthat >= 3.2.0"
  )

  requested <- character(0)
  testthat::local_mocked_bindings(
    GET = function(url, ...) {
      requested <<- c(requested, url)
      structure(
        list(
          status = 200L,
          body = '[{"place_id":1,"lat":"30.1832063","lon":"66.9994226","display_name":"Quetta, Pakistan"}]'
        ),
        class = "mock_response"
      )
    },
    status_code = function(x, ...) x$status,
    content = function(x, ...) x$body,
    user_agent = function(...) NULL,
    timeout = function(...) NULL,
    .package = "httr"
  )

  loc_run(loc_test_data(), check_country = FALSE, nominatim_delay_s = 0)
  # u5 and u7 both claim Peshawar and neither has usable GPS, so Peshawar
  # must never be sent to Nominatim
  expect_false(any(grepl("Peshawar", requested, ignore.case = TRUE)))
})

# ---- contract / plumbing ----------------------------------------------------

test_that("the returned log follows the package log contract", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearthdata")

  # run the country check so the contract is tested against real rows
  res <- loc_run(loc_test_data(), check_city = FALSE)
  log <- res$interview_location_log
  expect_gt(nrow(log), 0)
  expect_named(
    log,
    c("uuid", "old_value", "question", "issue", "check_binding")
  )
  expect_true(all(vapply(log, is.character, logical(1))))
  expect_true(all(grepl(" ~/~ ", log$check_binding, fixed = TRUE)))
  expect_true(all(!is.na(log$old_value)))

  # only two prefixes survive: location_missing_gps was retired
  expect_true(all(grepl(
    "^(location_country|location_city) ~/~ ",
    log$check_binding
  )))
})

test_that("dataframe and list inputs both work and the dataset is untouched", {
  skip_if_not_installed("sf")

  d <- loc_test_data()
  res <- loc_run(
    list(checked_dataset = d),
    log_name = "loc_log",
    check_country = FALSE,
    check_city = FALSE
  )
  expect_true("loc_log" %in% names(res))
  expect_identical(res$checked_dataset, d)
})

test_that("skip_label_row controls whether row 1 is checked", {
  skip_if_not_installed("sf")

  # the label row carries the words "latitude"/"longitude", so when it is kept
  # it shows up as unusable GPS — which is now a warning, not a log row
  kept <- loc_capture(
    loc_test_data(),
    check_country = FALSE,
    check_city = FALSE,
    skip_label_row = FALSE
  )
  dropped <- loc_capture(
    loc_test_data(),
    check_country = FALSE,
    check_city = FALSE,
    skip_label_row = TRUE
  )
  expect_true(any(grepl("LABEL", kept$warnings)))
  expect_false(any(grepl("LABEL", dropped$warnings)))
  expect_false("LABEL" %in% dropped$result$interview_location_log$uuid)
})

test_that("a missing column errors with the column named", {
  expect_error(
    validate_interview_location(loc_test_data(), city_question = "Q99"),
    "Cannot find the following column"
  )
})

# ---- city check (mocked Nominatim) -----------------------------------------

test_that("city check geocodes correctly and flags distant GPS", {
  skip_if_not_installed("sf")
  skip_if_not_installed("httr")
  skip_if_not_installed("jsonlite")
  skip_if(
    !exists("local_mocked_bindings", asNamespace("testthat")),
    "needs testthat >= 3.2.0"
  )

  structured <- list(
    quetta = '[{"place_id":1,"lat":"30.1832063","lon":"66.9994226","display_name":"Quetta, Balochistan, Pakistan"}]',
    karachi = '[{"place_id":2,"lat":"24.8546842","lon":"67.0207055","display_name":"Karachi, Sindh, Pakistan"}]'
  )
  # Chaman is a border town OSM does not tag as a city: only free-form finds it
  free <- c(
    structured,
    list(
      `chaman, pakistan` = '[{"place_id":3,"lat":"30.9209","lon":"66.4508","display_name":"Chaman, Balochistan, Pakistan"}]'
    )
  )
  n_structured <- 0L
  n_free <- 0L

  fake_get <- function(url, ...) {
    lookup <- function(db, key) {
      i <- match(tolower(trimws(key)), tolower(names(db)))
      if (is.na(i)) NULL else db[[i]]
    }
    if (grepl("[?&]q=", url)) {
      n_free <<- n_free + 1L
      body <- lookup(free, utils::URLdecode(sub(".*[?&]q=([^&]*).*", "\\1", url)))
    } else {
      n_structured <<- n_structured + 1L
      body <- lookup(
        structured,
        utils::URLdecode(sub(".*[?&]city=([^&]*).*", "\\1", url))
      )
    }
    if (is.null(body)) body <- "[]"
    structure(list(status = 200L, body = body), class = "mock_response")
  }

  testthat::local_mocked_bindings(
    GET = fake_get,
    status_code = function(x, ...) x$status,
    content = function(x, ...) x$body,
    user_agent = function(...) NULL,
    timeout = function(...) NULL,
    .package = "httr"
  )

  res <- loc_run(
    loc_test_data(),
    check_country = FALSE,
    nominatim_delay_s = 0
  )
  log <- res$interview_location_log

  # 3 unique city+country pairs among surveys with valid GPS
  expect_equal(n_structured, 3L)
  # free-form fallback used only for the pair the structured query missed
  expect_equal(n_free, 1L)

  expect_true(any(grepl("^location_city ~/~ u3", loc_bindings(log))))
  expect_true(any(grepl("^location_city ~/~ u4", loc_bindings(log))))
  for (u in c("u1", "u2", "u6")) {
    expect_false(any(grepl(paste0("^location_city ~/~ ", u), loc_bindings(log))))
  }
  # Quetta -> Karachi is ~590km
  expect_match(log$issue[log$uuid == "u3"], "59[0-9](\\.[0-9])?km from the centre")
})

test_that("case and whitespace variants of a city are geocoded once", {
  skip_if_not_installed("sf")
  skip_if_not_installed("httr")
  skip_if_not_installed("jsonlite")
  skip_if(
    !exists("local_mocked_bindings", asNamespace("testthat")),
    "needs testthat >= 3.2.0"
  )

  n_calls <- 0L
  testthat::local_mocked_bindings(
    GET = function(url, ...) {
      n_calls <<- n_calls + 1L
      structure(
        list(
          status = 200L,
          body = '[{"place_id":1,"lat":"30.1832063","lon":"66.9994226","display_name":"Quetta, Pakistan"}]'
        ),
        class = "mock_response"
      )
    },
    status_code = function(x, ...) x$status,
    content = function(x, ...) x$body,
    user_agent = function(...) NULL,
    timeout = function(...) NULL,
    .package = "httr"
  )

  d <- loc_test_data()
  d$Q14[-1] <- c(
    " quetta ",
    "QUETTA",
    "Quetta",
    "quetta",
    "Quetta",
    "QuEtTa",
    "quetta "
  )
  loc_run(d, check_country = FALSE, nominatim_delay_s = 0)
  expect_equal(n_calls, 1L)
})

test_that("an empty Nominatim result warns instead of erroring", {
  skip_if_not_installed("sf")
  skip_if_not_installed("httr")
  skip_if_not_installed("jsonlite")
  skip_if(
    !exists("local_mocked_bindings", asNamespace("testthat")),
    "needs testthat >= 3.2.0"
  )

  testthat::local_mocked_bindings(
    GET = function(url, ...) {
      structure(list(status = 200L, body = "[]"), class = "mock_response")
    },
    status_code = function(x, ...) x$status,
    content = function(x, ...) x$body,
    user_agent = function(...) NULL,
    timeout = function(...) NULL,
    .package = "httr"
  )

  expect_warning(
    suppressMessages(validate_interview_location(
      loc_test_data(),
      check_country = FALSE,
      nominatim_delay_s = 0,
      flag_missing_gps = FALSE # keep the unusable-GPS warning out of the way
    )),
    "Could not geocode"
  )
})

test_that("geocoding survives an HTTP error without aborting the run", {
  skip_if_not_installed("sf")
  skip_if_not_installed("httr")
  skip_if_not_installed("jsonlite")
  skip_if(
    !exists("local_mocked_bindings", asNamespace("testthat")),
    "needs testthat >= 3.2.0"
  )

  testthat::local_mocked_bindings(
    GET = function(url, ...) stop("connection refused"),
    status_code = function(x, ...) 500L,
    content = function(x, ...) "",
    user_agent = function(...) NULL,
    timeout = function(...) NULL,
    .package = "httr"
  )

  out <- loc_capture(
    loc_test_data(),
    check_country = FALSE,
    nominatim_delay_s = 0
  )
  # nothing errors, the log contract still holds, and no city flags are invented
  expect_named(
    out$result$interview_location_log,
    c("uuid", "old_value", "question", "issue", "check_binding")
  )
  expect_false(any(grepl(
    "^location_city",
    loc_bindings(out$result$interview_location_log)
  )))
  # the unusable-GPS surveys are still reported, just not logged
  expect_true(any(grepl("u7", out$warnings)))
})
