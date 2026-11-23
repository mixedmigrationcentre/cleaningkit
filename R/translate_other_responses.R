#' Options for Translating Other Responses
#'
#' Settings used by \code{translate_other_responses()} and by
#' \code{prepare_other_responses(translate = TRUE)}. The defaults are chosen to
#' stay well inside what Google's free translation service tolerates and to send
#' as little as possible; most users only set \code{cache_file}.
#'
#' @param mask_numbers Logical. If \code{TRUE} (the default), any run of five or
#'   more digits - a phone number, an ID, a bank or case number, even with
#'   spaces, dashes, brackets or a leading \code{+} - is replaced by
#'   \code{#####} before the text is sent. Shorter numbers such as ages or years
#'   written as two digits are kept, because they are rarely identifying and
#'   often matter for the meaning.
#' @param cache_file Optional path to an \code{.rds} file. Every text that has
#'   been translated is saved there (after each batch), and a later run only
#'   sends texts that are not in it yet. Use one cache per project; it contains
#'   the response texts, so keep it with the data and never commit or share it.
#'   \code{NULL} (the default) keeps no cache.
#' @param target_language Language code to translate into. Default \code{"en"}.
#' @param pause Seconds to wait between two requests. Default \code{0.5}.
#' @param max_retries How many times a request is retried after a "too many
#'   requests" reply, a server error or a lost connection. Default \code{4}.
#' @param retry_wait Seconds to wait before the first retry. The wait doubles
#'   with each further retry (2, 4, 8, 16 seconds with the defaults).
#' @param batch_size Maximum number of texts sent in one request. Default
#'   \code{50}.
#' @param batch_chars Maximum number of characters sent in one request. Google
#'   rejects requests much above 5000 characters. Default \code{4000}.
#' @param timeout Seconds to wait for one reply before giving up on it. Default
#'   \code{30}.
#'
#' @return A named list of the settings.
#' @seealso \code{translate_other_responses()}
#' @examples
#' ck_translate_options(cache_file = "output/translation_cache.rds")
#' @export
ck_translate_options <- function(
  mask_numbers = TRUE,
  cache_file = NULL,
  target_language = "en",
  pause = 0.5,
  max_retries = 4,
  retry_wait = 2,
  batch_size = 50,
  batch_chars = 4000,
  timeout = 30
) {
  num_ok <- function(x) is.numeric(x) && length(x) == 1 && !is.na(x) && x >= 0
  if (!num_ok(pause) || !num_ok(retry_wait) || !num_ok(timeout)) {
    stop("`pause`, `retry_wait` and `timeout` must be single numbers >= 0.")
  }
  if (!num_ok(max_retries)) {
    stop("`max_retries` must be a single number >= 0.")
  }
  if (!num_ok(batch_size) || batch_size < 1) {
    stop("`batch_size` must be a single number >= 1.")
  }
  if (!num_ok(batch_chars) || batch_chars < 1) {
    stop("`batch_chars` must be a single number >= 1.")
  }
  if (
    !is.character(target_language) ||
      length(target_language) != 1 ||
      !nzchar(target_language)
  ) {
    stop("`target_language` must be a language code such as \"en\".")
  }
  if (
    !is.null(cache_file) &&
      (!is.character(cache_file) || length(cache_file) != 1)
  ) {
    stop("`cache_file` must be NULL or a single file path.")
  }
  list(
    mask_numbers = isTRUE(mask_numbers),
    cache_file = cache_file,
    target_language = target_language,
    pause = pause,
    max_retries = as.integer(max_retries),
    retry_wait = retry_wait,
    batch_size = as.integer(batch_size),
    batch_chars = batch_chars,
    timeout = timeout
  )
}

#' Machine-Translate Other Responses
#'
#' Fills the \code{translation} column of an other-responses data frame with
#' an English machine translation of each \code{response}, using Google
#' Translate's free web service. The detected language is shown in front of
#' each translation, e.g. \code{"[Arabic] I want to work"}.
#'
#' \strong{Nothing is sent unless you ask for it.} The default,
#' \code{translate = "preview"}, sends nothing: it returns the exact list of
#' texts that would be sent, so a team can check it first. Only
#' \code{translate = TRUE} contacts Google.
#'
#' @section What is sent:
#' Only the text of the "other" responses, and each distinct text once. No
#' uuid, enumerator, date, location, question or any other column is sent, and
#' nothing links a text to the respondent. Before sending:
#' \itemize{
#'   \item blank responses and responses with no letters (only numbers or
#'     punctuation) are skipped;
#'   \item long numbers are masked as \code{#####} (see \code{mask_numbers} in
#'     \code{ck_translate_options()});
#'   \item texts already in the cache, and rows whose \code{translation} is
#'     already filled, are skipped.
#' }
#' The texts travel in the body of an HTTPS request, not in the web address, so
#' they do not end up in proxy or browser logs. Google still receives them, and
#' it sees the computer's IP address. The free service comes with no data
#' processing agreement: check your data-protection rules before using it.
#'
#' @section Limits and failures:
#' Google does not publish limits for the free service and blocks a computer
#' that sends too much too fast. Texts are therefore combined into batches,
#' requests are paced, and a "too many requests" reply is retried after a
#' growing wait (see \code{ck_translate_options()}). If Google keeps refusing,
#' sending stops. A text that could not be translated is left blank with a
#' warning, and the rest of the work carries on; with a \code{cache_file}, run
#' it again later and only the missing texts are sent.
#'
#' @section Accuracy:
#' Machine translation of short, informal, misspelt answers is often wrong, and
#' the language of a one-word answer can be misdetected. The translation is a
#' help for the reviewer, never applied to the data: confirm it against the
#' original response. A response detected as English is left blank, as is one
#' whose translation is identical to the original.
#'
#' @param df Data frame from \code{prepare_other_responses()}. One made by an
#'   earlier version (with \code{response_en} and no \code{translation} column)
#'   also works.
#' @param translate \code{"preview"} (the default) returns the texts that would
#'   be sent and sends nothing. \code{TRUE} sends them and fills the
#'   \code{translation} column. \code{FALSE} does nothing and returns \code{df}
#'   with an empty \code{translation} column.
#' @param options Settings from \code{ck_translate_options()}.
#' @param verbose Logical. Print what is being sent and how it went. Default
#'   \code{TRUE}.
#'
#' @return With \code{translate = TRUE} or \code{FALSE}, \code{df} with its
#'   \code{translation} column. With \code{translate = "preview"}, a data frame
#'   with one row per text that would be sent: \code{text_to_send} (exactly as
#'   it would be sent, after masking), \code{n_responses} (how many responses
#'   share it) and \code{questions}.
#' @seealso \code{ck_translate_options()}, \code{prepare_other_responses()}
#' @examples
#' \dontrun{
#' # see what would be sent - nothing leaves the computer
#' preview <- translate_other_responses(other_responses_df)
#' View(preview)
#'
#' # send it
#' other_responses_df <- translate_other_responses(
#'   other_responses_df,
#'   translate = TRUE,
#'   options = ck_translate_options(cache_file = "output/translation_cache.rds")
#' )
#' }
#' @export
translate_other_responses <- function(
  df,
  translate = "preview",
  options = ck_translate_options(),
  verbose = TRUE
) {
  mode <- .ck_translate_mode(translate)
  df <- .ck_normalise_other_cols(df)
  if (mode == "off") {
    return(df)
  }
  if (!("response" %in% names(df))) {
    stop(
      "`df` has no `response` (or `response_en`) column. ",
      "Pass the data frame returned by prepare_other_responses()."
    )
  }

  tr_col <- .ck_translation_col()
  target <- options$target_language
  src <- as.character(df[["response"]])
  existing <- as.character(df[[tr_col]])

  has_text <- !is.na(src) & nzchar(trimws(src))
  todo <- is.na(existing) | !nzchar(trimws(existing))
  eligible <- todo & has_text & grepl("\\p{L}", src, perl = TRUE)
  n_no_letters <- sum(todo & has_text & !eligible)

  sent <- rep(NA_character_, nrow(df))
  sent[eligible] <- .ck_prepare_send_text(src[eligible], options$mask_numbers)
  uniq <- unique(sent[eligible])

  cache <- .ck_read_translation_cache(options$cache_file)
  cache_hit <- cache$text[cache$target == target]
  to_send <- uniq[!(uniq %in% cache_hit)]
  n_cached <- length(uniq) - length(to_send)

  # ---- preview: report and return the list, send nothing -------------------
  if (mode == "preview") {
    preview <- .ck_translation_preview(df, sent, to_send)
    if (verbose) {
      message(
        "translate_other_responses: PREVIEW - nothing was sent. ",
        length(to_send),
        " distinct text(s) would be sent to Google Translate",
        .ck_translate_summary(n_cached, n_no_letters, options$mask_numbers),
        ". Use translate = TRUE to send them."
      )
    }
    return(preview)
  }

  # ---- send ----------------------------------------------------------------
  if (verbose) {
    message(
      "translate_other_responses: sending ",
      length(to_send),
      " distinct text(s) to Google Translate (translate.googleapis.com)",
      .ck_translate_summary(n_cached, n_no_letters, options$mask_numbers),
      "."
    )
  }

  if (length(to_send) > 0) {
    on_batch <- function(rows) {
      rows <- rows[!is.na(rows$translation), , drop = FALSE]
      if (nrow(rows) == 0) {
        return(invisible())
      }
      cache <<- rbind(
        cache,
        data.frame(
          text = rows$text,
          target = target,
          translation = rows$translation,
          language = rows$language,
          stringsAsFactors = FALSE
        )
      )
      .ck_write_translation_cache(cache, options$cache_file)
    }
    .ck_translate_send(to_send, options, verbose, on_batch)
  }

  # ---- fill the column -----------------------------------------------------
  cache_t <- cache[cache$target == target, , drop = FALSE]
  hit <- match(sent, cache_t$text)
  done <- eligible & !is.na(hit)
  df[[tr_col]][done] <- .ck_format_translation(
    sent[done],
    cache_t$translation[hit[done]],
    cache_t$language[hit[done]],
    target
  )

  n_failed_texts <- length(unique(sent[eligible & is.na(hit)]))
  if (n_failed_texts > 0) {
    warning(
      "translate_other_responses: ",
      n_failed_texts,
      " distinct text(s) could not be translated and were left blank. ",
      "Nothing else is affected. Run it again later",
      if (is.null(options$cache_file)) {
        " (set `cache_file` in ck_translate_options() so translated texts are not sent again)"
      } else {
        "; texts already translated are taken from the cache and not sent again"
      },
      ".",
      call. = FALSE
    )
  } else if (verbose) {
    message(
      "translate_other_responses: done - ",
      sum(done),
      " response(s) have a translation result."
    )
  }
  df
}

# ---------------------------------------------------------------------------
# internals
# ---------------------------------------------------------------------------

#' Turn the `translate` argument into "off", "preview" or "send"
#' @noRd
.ck_translate_mode <- function(translate) {
  if (isTRUE(translate)) {
    return("send")
  }
  if (isFALSE(translate)) {
    return("off")
  }
  if (identical(translate, "preview")) {
    return("preview")
  }
  stop("`translate` must be FALSE, TRUE or \"preview\".")
}

#' Accuracy note shown on the translation column
#' @noRd
.ck_translation_note <- function() {
  paste0(
    "Machine translation (Google Translate). It may be inaccurate: please ",
    "confirm it against the original response before using it. ",
    "Not applied to the data."
  )
}

#' One clause for the console summary
#' @noRd
.ck_translate_summary <- function(n_cached, n_no_letters, mask_numbers) {
  parts <- character(0)
  if (n_cached > 0) {
    parts <- c(parts, paste0(n_cached, " already translated in the cache, not sent"))
  }
  if (n_no_letters > 0) {
    parts <- c(
      parts,
      paste0(n_no_letters, " response(s) without letters skipped")
    )
  }
  parts <- c(
    parts,
    if (isTRUE(mask_numbers)) {
      "long numbers masked as #####"
    } else {
      "numbers NOT masked"
    }
  )
  paste0(" (", paste(parts, collapse = "; "), ")")
}

#' Replace long numbers (5+ digits) with #####
#'
#' A run starts and ends with a digit and may hold spaces, dashes, dots and
#' brackets between digits, with an optional leading "+", so phone numbers
#' written as "+251 91 234 5678" or "0912-345-678" are caught as one. Runs with
#' fewer than five digits in total are kept.
#' @noRd
.ck_mask_numbers <- function(x, token = "#####") {
  m <- gregexpr("\\+?\\d[\\d ().-]*\\d", x, perl = TRUE)
  regmatches(x, m) <- lapply(regmatches(x, m), function(s) {
    long <- nchar(gsub("\\D", "", s)) >= 5
    s[long] <- token
    s
  })
  x
}

#' The text exactly as it would be sent
#' @noRd
.ck_prepare_send_text <- function(x, mask_numbers = TRUE) {
  x <- enc2utf8(as.character(x))
  x <- stringr::str_squish(gsub("[\r\n\t]+", " ", x))
  if (isTRUE(mask_numbers)) {
    x <- .ck_mask_numbers(x)
  }
  x
}

#' The preview table: one row per text that would be sent
#' @noRd
.ck_translation_preview <- function(df, sent, to_send) {
  if (length(to_send) == 0) {
    return(data.frame(
      text_to_send = character(0),
      n_responses = integer(0),
      questions = character(0),
      stringsAsFactors = FALSE
    ))
  }
  q <- if ("question_name" %in% names(df)) {
    as.character(df[["question_name"]])
  } else {
    rep(NA_character_, nrow(df))
  }
  rows <- lapply(to_send, function(t) which(sent == t))
  data.frame(
    text_to_send = to_send,
    n_responses = vapply(rows, length, integer(1)),
    questions = vapply(
      rows,
      function(r) paste(unique(stats::na.omit(q[r])), collapse = ", "),
      character(1)
    ),
    stringsAsFactors = FALSE
  )
}

#' Group texts into batches by count and total length
#' @return A list of integer index vectors.
#' @noRd
.ck_translate_batches <- function(n_chars, batch_size, batch_chars) {
  ids <- integer(length(n_chars))
  b <- 1L
  cur_n <- 0L
  cur_c <- 0
  for (i in seq_along(n_chars)) {
    if (
      cur_n > 0 && (cur_n >= batch_size || cur_c + n_chars[i] > batch_chars)
    ) {
      b <- b + 1L
      cur_n <- 0L
      cur_c <- 0
    }
    ids[i] <- b
    cur_n <- cur_n + 1L
    cur_c <- cur_c + n_chars[i]
  }
  unname(split(seq_along(n_chars), ids))
}

#' One request to Google's free translation endpoint
#'
#' The texts go in the POST body (form-encoded, one `q` per text), never in the
#' URL. Kept as its own function so tests can replace it.
#'
#' @return \code{list(status = <HTTP status>, body = <text>)}. Errors (no
#'   connection, timeout) are left to the caller.
#' @noRd
.ck_translate_request <- function(texts, target, timeout) {
  body <- paste0(
    "q=",
    vapply(texts, utils::URLencode, character(1), reserved = TRUE),
    collapse = "&"
  )
  resp <- httr::POST(
    "https://translate.googleapis.com/translate_a/t",
    query = list(client = "gtx", sl = "auto", tl = target, dt = "t"),
    body = body,
    encode = "raw",
    httr::content_type("application/x-www-form-urlencoded; charset=UTF-8"),
    httr::user_agent("cleaningkit (R package)"),
    httr::timeout(timeout)
  )
  list(
    status = httr::status_code(resp),
    body = httr::content(resp, as = "text", encoding = "UTF-8")
  )
}

#' Parse a reply: one \code{[translation, language]} pair per text
#' @return A data frame with \code{translation} and \code{language}, or
#'   \code{NULL} when the reply does not have one entry per text.
#' @noRd
.ck_parse_translate_response <- function(body, n) {
  parsed <- tryCatch(
    jsonlite::fromJSON(body, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(parsed)) {
    return(NULL)
  }
  # a one-text request may come back unwrapped: "text" or ["text", "lang"]
  if (
    n == 1 &&
      (is.character(parsed) || all(vapply(parsed, is.character, logical(1))))
  ) {
    parsed <- list(parsed)
  }
  if (!is.list(parsed) || length(parsed) != n) {
    return(NULL)
  }
  pick <- function(el, i) {
    if (length(el) >= i && is.character(el[[i]]) && length(el[[i]]) == 1) {
      el[[i]]
    } else {
      NA_character_
    }
  }
  data.frame(
    translation = vapply(parsed, pick, character(1), i = 1),
    language = vapply(parsed, pick, character(1), i = 2),
    stringsAsFactors = FALSE
  )
}

#' Send texts in paced batches, retrying and backing off
#'
#' Retries a batch after a 429 ("too many requests"), a 5xx or a lost
#' connection, waiting \code{retry_wait}, then twice as long, and so on. If a
#' batch still fails that way, Google is refusing or unreachable, so sending
#' stops rather than prolonging a block. Any other failure (a malformed reply,
#' a rejected batch) loses only that batch.
#'
#' @param on_batch Called with each translated batch, so results are cached
#'   as they arrive and survive an interruption.
#' @return A data frame of \code{text}, \code{translation}, \code{language};
#'   untranslated texts have \code{NA}.
#' @noRd
.ck_translate_send <- function(texts, options, verbose, on_batch) {
  res <- data.frame(
    text = texts,
    translation = NA_character_,
    language = NA_character_,
    stringsAsFactors = FALSE
  )
  batches <- .ck_translate_batches(
    nchar(texts),
    options$batch_size,
    options$batch_chars
  )
  n_b <- length(batches)

  for (k in seq_len(n_b)) {
    idx <- batches[[k]]
    if (k > 1 && options$pause > 0) {
      Sys.sleep(options$pause)
    }

    out <- NULL
    status <- NA
    attempt <- 0L
    repeat {
      r <- tryCatch(
        .ck_translate_request(
          texts[idx],
          options$target_language,
          options$timeout
        ),
        error = function(e) list(status = NA, body = conditionMessage(e))
      )
      status <- r$status
      if (!is.na(status) && status == 200) {
        out <- .ck_parse_translate_response(r$body, length(idx))
        break
      }
      retryable <- is.na(status) || status == 429 || status >= 500
      if (!retryable || attempt >= options$max_retries) {
        break
      }
      attempt <- attempt + 1L
      wait <- options$retry_wait * 2^(attempt - 1L)
      if (verbose) {
        message(
          "  batch ",
          k,
          "/",
          n_b,
          ": ",
          if (is.na(status)) "no connection" else paste0("HTTP ", status),
          " - waiting ",
          wait,
          "s before retry ",
          attempt,
          "/",
          options$max_retries
        )
      }
      if (wait > 0) Sys.sleep(wait)
    }

    if (!is.null(out)) {
      res$translation[idx] <- out$translation
      res$language[idx] <- out$language
      on_batch(res[idx, , drop = FALSE])
      if (verbose && n_b > 1) {
        message("  batch ", k, "/", n_b, " done")
      }
      next
    }

    gave_up <- is.na(status) || status == 429 || status >= 500
    if (gave_up) {
      if (verbose) {
        message(
          "  batch ",
          k,
          "/",
          n_b,
          ": Google is ",
          if (is.na(status)) "unreachable" else "refusing requests",
          " - stopping. ",
          n_b - k + 1,
          " batch(es) not sent."
        )
      }
      break
    }
    if (verbose) {
      message(
        "  batch ",
        k,
        "/",
        n_b,
        ": skipped (",
        if (status == 200) "unexpected reply" else paste0("HTTP ", status),
        ")"
      )
    }
  }
  res
}

#' Read the translation cache, or an empty one
#' @noRd
.ck_read_translation_cache <- function(path) {
  empty <- data.frame(
    text = character(0),
    target = character(0),
    translation = character(0),
    language = character(0),
    stringsAsFactors = FALSE
  )
  if (is.null(path) || !file.exists(path)) {
    return(empty)
  }
  cache <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.data.frame(cache) || !all(names(empty) %in% names(cache))) {
    warning(
      "translate_other_responses: could not read the cache '",
      path,
      "'; starting without it.",
      call. = FALSE
    )
    return(empty)
  }
  cache <- cache[, names(empty), drop = FALSE]
  cache[] <- lapply(cache, as.character)
  cache
}

#' Save the translation cache; a failure only warns
#' @noRd
.ck_write_translation_cache <- function(cache, path) {
  if (is.null(path)) {
    return(invisible(FALSE))
  }
  ok <- tryCatch(
    {
      dir <- dirname(path)
      if (!dir.exists(dir)) {
        dir.create(dir, recursive = TRUE)
      }
      cache <- cache[
        !duplicated(cache[, c("text", "target")], fromLast = TRUE),
        ,
        drop = FALSE
      ]
      saveRDS(cache, path)
      TRUE
    },
    error = function(e) {
      warning(
        "translate_other_responses: could not write the cache '",
        path,
        "': ",
        conditionMessage(e),
        call. = FALSE
      )
      FALSE
    }
  )
  invisible(ok)
}

#' Cell text: the language name in square brackets, then the translation;
#' NA when there is nothing to add
#' @noRd
.ck_format_translation <- function(sent, translation, language, target) {
  same <- tolower(stringr::str_squish(translation)) ==
    tolower(stringr::str_squish(sent))
  blank <- is.na(translation) |
    !nzchar(trimws(translation)) |
    (!is.na(language) & tolower(language) == tolower(target)) |
    (!is.na(same) & same)
  out <- paste0("[", .ck_language_name(language), "] ", translation)
  out[blank] <- NA_character_
  out
}

#' Language name for a detected code, falling back to the code
#' @noRd
.ck_language_name <- function(code) {
  names_map <- c(
    am = "Amharic",
    ar = "Arabic",
    bm = "Bambara",
    bn = "Bengali",
    ckb = "Kurdish (Sorani)",
    de = "German",
    en = "English",
    es = "Spanish",
    fa = "Persian",
    `fa-AF` = "Dari",
    ff = "Fula",
    fr = "French",
    ha = "Hausa",
    hi = "Hindi",
    it = "Italian",
    ku = "Kurdish",
    ln = "Lingala",
    my = "Burmese",
    om = "Oromo",
    ps = "Pashto",
    pt = "Portuguese",
    ru = "Russian",
    rw = "Kinyarwanda",
    so = "Somali",
    sw = "Swahili",
    ti = "Tigrinya",
    tr = "Turkish",
    uk = "Ukrainian",
    ur = "Urdu",
    wo = "Wolof"
  )
  out <- unname(names_map[code])
  out[is.na(out)] <- code[is.na(out)]
  out[is.na(out)] <- "?"
  out
}
