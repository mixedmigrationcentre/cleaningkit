# Machine translation of the "other" responses. The HTTP call is always mocked:
# nothing here ever reaches Google.

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

ck_tr_df <- function() {
  data.frame(
    uuid = paste0("u", 1:7),
    question_name = c(
      "Q34_1",
      "Q34_1",
      "Q35_1",
      "Q35_1",
      "Q34_1",
      "Q34_1",
      "Q35_1"
    ),
    response = c(
      "أريد العمل", # Arabic
      "أريد العمل", # same again
      "je cherche du travail",
      "looking for work", # English
      "123", # no letters
      "", # blank
      "call me on +251 91 234 5678"
    ),
    stringsAsFactors = FALSE
  )
}

ck_tr_opts <- function(...) {
  ck_translate_options(pause = 0, retry_wait = 0, ...)
}

# A stand-in for Google: English stays as it is, the rest gets a fixed
# translation and a language code.
ck_tr_fake_google <- function(texts) {
  one <- function(t) {
    if (grepl("[؀-ۿ]", t)) {
      list("I want to work", "ar")
    } else if (grepl("cherche", t)) {
      list("I am looking for work", "fr")
    } else {
      list(t, "en")
    }
  }
  as.character(jsonlite::toJSON(lapply(texts, one), auto_unbox = TRUE))
}

# Mock the request and record every batch it is called with.
ck_tr_mock <- function(env = parent.frame(), respond = NULL) {
  calls <- new.env()
  calls$batches <- list()
  if (is.null(respond)) {
    respond <- function(texts, n_call) {
      list(status = 200L, body = ck_tr_fake_google(texts))
    }
  }
  testthat::local_mocked_bindings(
    .ck_translate_request = function(texts, target, timeout) {
      calls$batches[[length(calls$batches) + 1]] <- texts
      respond(texts, length(calls$batches))
    },
    .env = env
  )
  calls
}

# --------------------------------------------------------------------------
# off by default
# --------------------------------------------------------------------------

test_that("translate = FALSE sends nothing and leaves an empty column", {
  calls <- ck_tr_mock()
  out <- translate_other_responses(ck_tr_df(), translate = FALSE)
  expect_length(calls$batches, 0)
  expect_true("translation" %in% names(out))
  expect_true(all(is.na(out$translation)))
  # placed right after the response
  expect_identical(
    which(names(out) == "translation"),
    which(names(out) == "response") + 1L
  )
})

test_that("translate_other_responses() previews unless told to send", {
  calls <- ck_tr_mock()
  expect_message(
    preview <- translate_other_responses(ck_tr_df(), options = ck_tr_opts()),
    "PREVIEW - nothing was sent"
  )
  expect_length(calls$batches, 0)
  # distinct texts only; blanks and number-only answers skipped; masked
  expect_identical(
    preview$text_to_send,
    c(
      "أريد العمل",
      "je cherche du travail",
      "looking for work",
      "call me on #####"
    )
  )
  expect_identical(preview$n_responses, c(2L, 1L, 1L, 1L))
  expect_identical(preview$questions[1], "Q34_1")
})

test_that("an invalid translate value is refused", {
  expect_error(
    translate_other_responses(ck_tr_df(), translate = "yes"),
    "FALSE, TRUE"
  )
  expect_error(.ck_translate_mode(NA), "FALSE, TRUE")
})

# --------------------------------------------------------------------------
# sending
# --------------------------------------------------------------------------

test_that("translate = TRUE fills the column, tagged with the language", {
  calls <- ck_tr_mock()
  expect_message(
    out <- translate_other_responses(
      ck_tr_df(),
      translate = TRUE,
      options = ck_tr_opts()
    ),
    "sending 4 distinct text"
  )
  # one batch, distinct and masked texts only - never the uuid or question
  expect_length(calls$batches, 1)
  expect_identical(length(calls$batches[[1]]), 4L)
  expect_false(any(grepl("u1|Q34", calls$batches[[1]])))
  expect_false(any(grepl("5678", calls$batches[[1]])))

  expect_identical(out$translation[1:2], rep("[Arabic] I want to work", 2))
  expect_identical(out$translation[3], "[French] I am looking for work")
  # English, number-only and blank answers stay empty
  expect_true(all(is.na(out$translation[4:7])))
})

test_that("mask_numbers = FALSE sends numbers as written", {
  calls <- ck_tr_mock()
  translate_other_responses(
    ck_tr_df()[7, ],
    translate = TRUE,
    options = ck_tr_opts(mask_numbers = FALSE),
    verbose = FALSE
  )
  expect_identical(calls$batches[[1]], "call me on +251 91 234 5678")
})

test_that("texts are combined into batches by count and length", {
  expect_identical(
    .ck_translate_batches(
      c(10, 10, 10, 10, 10),
      batch_size = 2,
      batch_chars = 100
    ),
    list(1:2, 3:4, 5L)
  )
  expect_identical(
    .ck_translate_batches(c(60, 60, 10), batch_size = 50, batch_chars = 100),
    list(1L, 2:3)
  )
  # a text longer than the limit still goes, on its own
  expect_identical(
    .ck_translate_batches(c(500, 10), batch_size = 50, batch_chars = 100),
    list(1L, 2L)
  )

  calls <- ck_tr_mock()
  translate_other_responses(
    ck_tr_df(),
    translate = TRUE,
    options = ck_tr_opts(batch_size = 2),
    verbose = FALSE
  )
  expect_length(calls$batches, 2)
})

test_that("a 'too many requests' reply is retried", {
  calls <- ck_tr_mock(respond = function(texts, n_call) {
    if (n_call < 3) {
      list(status = 429L, body = "")
    } else {
      list(status = 200L, body = ck_tr_fake_google(texts))
    }
  })
  expect_message(
    out <- translate_other_responses(
      ck_tr_df(),
      translate = TRUE,
      options = ck_tr_opts()
    ),
    "HTTP 429 - waiting"
  )
  expect_length(calls$batches, 3)
  expect_identical(out$translation[1], "[Arabic] I want to work")
})

test_that("persistent refusal stops sending, warns, and keeps what worked", {
  calls <- ck_tr_mock(respond = function(texts, n_call) {
    if (n_call == 1) {
      list(status = 200L, body = ck_tr_fake_google(texts))
    } else {
      list(status = 429L, body = "")
    }
  })
  expect_warning(
    out <- translate_other_responses(
      ck_tr_df(),
      translate = TRUE,
      options = ck_tr_opts(batch_size = 1, max_retries = 2),
      verbose = FALSE
    ),
    "3 distinct text\\(s\\) could not be translated"
  )
  # first batch, then 1 try + 2 retries on the second, then it stops
  expect_length(calls$batches, 4)
  expect_identical(out$translation[1:2], rep("[Arabic] I want to work", 2))
  expect_true(all(is.na(out$translation[3:7])))
})

test_that("no connection never stops the run", {
  testthat::local_mocked_bindings(
    .ck_translate_request = function(texts, target, timeout) stop("offline")
  )
  expect_warning(
    out <- translate_other_responses(
      ck_tr_df(),
      translate = TRUE,
      options = ck_tr_opts(max_retries = 1),
      verbose = FALSE
    ),
    "could not be translated"
  )
  expect_identical(nrow(out), 7L)
  expect_true(all(is.na(out$translation)))
})

test_that("a malformed reply loses only its own batch", {
  calls <- ck_tr_mock(respond = function(texts, n_call) {
    if (n_call == 1) {
      list(status = 200L, body = "not json")
    } else {
      list(status = 200L, body = ck_tr_fake_google(texts))
    }
  })
  expect_warning(
    out <- translate_other_responses(
      ck_tr_df(),
      translate = TRUE,
      options = ck_tr_opts(batch_size = 1),
      verbose = FALSE
    ),
    "1 distinct text"
  )
  expect_length(calls$batches, 4)
  expect_true(is.na(out$translation[1]))
  expect_identical(out$translation[3], "[French] I am looking for work")
})

# --------------------------------------------------------------------------
# cache
# --------------------------------------------------------------------------

test_that("the cache means a re-run sends only new texts", {
  cache <- withr::local_tempfile(fileext = ".rds")
  calls <- ck_tr_mock()

  translate_other_responses(
    ck_tr_df()[1:3, ],
    translate = TRUE,
    options = ck_tr_opts(cache_file = cache),
    verbose = FALSE
  )
  expect_true(file.exists(cache))
  expect_length(calls$batches, 1)

  out <- translate_other_responses(
    ck_tr_df(),
    translate = TRUE,
    options = ck_tr_opts(cache_file = cache),
    verbose = FALSE
  )
  expect_length(calls$batches, 2)
  expect_identical(
    calls$batches[[2]],
    c("looking for work", "call me on #####")
  )
  expect_identical(out$translation[1], "[Arabic] I want to work")

  # the preview also leaves cached texts out
  preview <- translate_other_responses(
    ck_tr_df(),
    options = ck_tr_opts(cache_file = cache),
    verbose = FALSE
  )
  expect_identical(nrow(preview), 0L)
})

test_that("an unreadable cache warns and is ignored", {
  cache <- withr::local_tempfile(fileext = ".rds")
  writeLines("not an rds", cache)
  ck_tr_mock()
  expect_warning(
    translate_other_responses(
      ck_tr_df()[1, ],
      translate = TRUE,
      options = ck_tr_opts(cache_file = cache),
      verbose = FALSE
    ),
    "could not read the cache"
  )
})

# --------------------------------------------------------------------------
# helpers and legacy input
# --------------------------------------------------------------------------

test_that("only long numbers are masked", {
  expect_identical(
    .ck_mask_numbers(c(
      "call +251 91 234 5678 today",
      "id 0912-345-678",
      "aged 25 in 2023",
      "case 12345"
    )),
    c("call ##### today", "id #####", "aged 25 in 2023", "case #####")
  )
})

test_that("replies of every shape are parsed", {
  expect_identical(
    .ck_parse_translate_response('[["hello","fr"],["work","en"]]', 2)$language,
    c("fr", "en")
  )
  expect_identical(
    .ck_parse_translate_response('[["hello","es"]]', 1)$translation,
    "hello"
  )
  expect_identical(
    .ck_parse_translate_response('["hello","es"]', 1)$language,
    "es"
  )
  expect_identical(
    .ck_parse_translate_response('"hello"', 1)$translation,
    "hello"
  )
  expect_null(.ck_parse_translate_response('[["a","en"]]', 2))
  expect_null(.ck_parse_translate_response("<html>", 1))
})

test_that("rows already translated are kept and not sent", {
  calls <- ck_tr_mock()
  df <- .ck_normalise_other_cols(ck_tr_df())
  df$translation[1:2] <- "kept"
  out <- translate_other_responses(
    df,
    translate = TRUE,
    options = ck_tr_opts(),
    verbose = FALSE
  )
  expect_identical(out$translation[1:2], c("kept", "kept"))
  expect_false(any(grepl("أ", calls$batches[[1]])))
})

test_that("a data frame from an older version (response_en) works", {
  ck_tr_mock()
  df <- ck_tr_df()[1:3, ]
  names(df)[names(df) == "response"] <- "response_en"
  out <- translate_other_responses(
    df,
    translate = TRUE,
    options = ck_tr_opts(),
    verbose = FALSE
  )
  expect_true(all(c("response", "translation") %in% names(out)))
  expect_identical(out$translation[3], "[French] I am looking for work")
})

test_that("ck_translate_options() rejects nonsense", {
  expect_error(ck_translate_options(pause = -1), "pause")
  expect_error(ck_translate_options(batch_size = 0), "batch_size")
  expect_error(ck_translate_options(target_language = ""), "target_language")
  expect_identical(ck_translate_options()$mask_numbers, TRUE)
})
