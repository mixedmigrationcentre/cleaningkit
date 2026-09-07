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
    # u7 lat present, lon blank      -> unusable GPS, missing_gps flag
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
      check_city = FALSE
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

test_that("GPS that is present but unusable is flagged", {
  skip_if_not_installed("sf")

  res <- loc_run(loc_test_data(), check_country = FALSE, check_city = FALSE)
  log <- res$interview_location_log

  # u7 has a latitude but no longitude — a real data problem
  expect_true(any(grepl("^location_missing_gps ~/~ u7", loc_bindings(log))))
  expect_equal(nrow(log), 1)

  # (0, 0) is the Gulf of Guinea — treat as a device default, not a real fix
  d <- loc_test_data()
  d$`_location_latitude`[2] <- "0"
  d$`_location_longitude`[2] <- "0"
  res0 <- loc_run(d, check_country = FALSE, check_city = FALSE)
  expect_true(any(grepl(
    "^location_missing_gps ~/~ u1",
    loc_bindings(res0$interview_location_log)
  )))

  # non-numeric text in a coordinate column is a bad entry, not a phone
  # interview, and must still be flagged
  dtxt <- loc_test_data()
  dtxt$`_location_latitude`[2] <- "n/a"
  dtxt$`_location_longitude`[2] <- "n/a"
  restxt <- loc_run(dtxt, check_country = FALSE, check_city = FALSE)
  expect_true(any(grepl(
    "^location_missing_gps ~/~ u1",
    loc_bindings(restxt$interview_location_log)
  )))

  # old_value is the string "NA", never a real NA
  expect_true(all(!is.na(log$old_value)))
  expect_equal(
    res0$interview_location_log$old_value[
      res0$interview_location_log$uuid == "u7"
    ],
    "34.0083"
  )
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

test_that("treat_blank_gps_as_phone = FALSE flags a fully absent geopoint", {
  skip_if_not_installed("sf")

  on_res <- loc_run(
    loc_test_data(),
    check_country = FALSE,
    check_city = FALSE,
    treat_blank_gps_as_phone = TRUE
  )
  off_res <- loc_run(
    loc_test_data(),
    check_country = FALSE,
    check_city = FALSE,
    treat_blank_gps_as_phone = FALSE
  )

  expect_false("u5" %in% on_res$interview_location_log$uuid)
  expect_true(any(grepl(
    "^location_missing_gps ~/~ u5",
    loc_bindings(off_res$interview_location_log)
  )))
  # u7 is flagged either way — its GPS is present but unusable
  expect_true("u7" %in% on_res$interview_location_log$uuid)
  expect_true("u7" %in% off_res$interview_location_log$uuid)
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

  res <- loc_run(loc_test_data(), check_country = FALSE, check_city = FALSE)
  log <- res$interview_location_log
  expect_named(
    log,
    c("uuid", "old_value", "question", "issue", "check_binding")
  )
  expect_true(all(vapply(log, is.character, logical(1))))
  expect_true(all(grepl(" ~/~ ", log$check_binding, fixed = TRUE)))
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

  kept <- loc_run(
    loc_test_data(),
    check_country = FALSE,
    check_city = FALSE,
    skip_label_row = FALSE
  )
  dropped <- loc_run(
    loc_test_data(),
    check_country = FALSE,
    check_city = FALSE,
    skip_label_row = TRUE
  )
  expect_true("LABEL" %in% kept$interview_location_log$uuid)
  expect_false("LABEL" %in% dropped$interview_location_log$uuid)
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
      nominatim_delay_s = 0
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

  res <- loc_run(
    loc_test_data(),
    check_country = FALSE,
    nominatim_delay_s = 0
  )
  # the missing-GPS flag still comes through; nothing errors
  expect_true(any(grepl(
    "^location_missing_gps ~/~ u7",
    loc_bindings(res$interview_location_log)
  )))
})
