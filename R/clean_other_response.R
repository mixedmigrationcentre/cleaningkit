#' Read and Prepare Filled Other-Responses Files
#'
#' Reads one or more filled other-responses Excel files from a directory (or a
#' single file path), renames the verbose column headers to short working names,
#' filters to valid uuids and joins the question metadata from \code{other_db},
#' classifies each row into one of three action types, and returns a single
#' cleaning-log dataframe ready for \code{apply_other_responses()}.
#'
#' @details
#' \strong{The three action types and what they produce:}
#' \describe{
#'   \item{\code{true_other}}{A genuine new answer (e.g. a translation).
#'     Overwrites the \code{_other} text column with the value in
#'     \code{TRUE other ...}. The parent question is not touched.}
#'   \item{\code{recode}}{The response actually matches an existing choice.
#'     The \code{EXISTING other ...} column is filled (older logs with several
#'     numbered \code{EXISTING other} columns are still read and merged). For
#'     \code{select_one}: blanks the \code{_other} text column, sets the parent
#'     to the matched choice code. For \code{select_multiple}: blanks the
#'     \code{_other} text column, removes the \code{other} option from the
#'     parent concatenation, and adds the matched choice(s).}
#'   \item{\code{remove}}{The response is invalid (\code{INVALID other == "Yes"}).
#'     Blanks the \code{_other} text column and removes/blanks the parent
#'     question reference.}
#' }
#'
#' \strong{Column check:} before the files are stacked, their headers are
#' compared with \code{check_log_files()}. Because the files are combined with
#' \code{rbind()}, a single file with an extra, missing or renamed column would
#' otherwise fail with "numbers of columns of arguments do not match", which
#' names no file. Instead the function stops with the offending file name and
#' the exact columns that are missing or extra - most often an older log still
#' carrying three numbered \code{EXISTING other} columns instead of one. Files
#' that cannot be opened at all are not treated as mismatches; they are warned
#' about and skipped as before.
#'
#' \strong{UUID matching:} the dataset uuid column (\code{uuid_column}) and
#' the other-responses file uuid column (\code{log_uuid_col}) are resolved
#' independently so they can have different names (e.g. \code{"_uuid"} in the
#' dataset and \code{"uuid"} in the log file). The ONA label/description row
#' is excluded from the dataset uuid list when \code{skip_label_row = TRUE}.
#'
#' \strong{Mutual exclusivity:} each row must have exactly one of
#' \code{true_other}, \code{existing_other}, or \code{invalid_other} filled.
#' Rows with zero or more than one filled are flagged with a warning and
#' excluded.
#'
#' \strong{Output shape:} the returned dataframe has columns
#' \code{uuid}, \code{question}, \code{action_taken}, \code{old_value},
#' \code{new_value} ready for \code{apply_other_responses()}.
#'
#' @param path Either a path to a directory containing one or more
#'   other-responses Excel files, or a direct path to a single \code{.xlsx}
#'   file.
#' @param dataset The current working dataset (after any prior cleaning). Used
#'   to filter to valid uuids and to look up current values of parent columns
#'   for \code{select_multiple} recoding.
#' @param other_db The \code{other_db} dataframe produced by
#'   \code{get_other_db()}, containing at least \code{name},
#'   \code{ref_question}, \code{q_type}, and \code{option_other}.
#' @param tool_choices The XLSForm choices sheet dataframe (works with Kobo,
#'   ONA, or any other XLSForm-based tool), used to resolve choice labels to
#'   codes for recode actions. Passed to \code{get_name_from_label()}.
#' @param uuid_column Name of the uuid column in \code{dataset}. Default
#'   \code{"_uuid"}.
#' @param log_uuid_col Name of the uuid column in the other-responses log
#'   files. Default \code{"uuid"} (as produced by \code{prepare_other_responses()}).
#'   Set to \code{"_uuid"} if your files use the raw ONA column name.
#' @param sm_separator Separator between a select-multiple parent column name
#'   and its binary sub-columns in \code{dataset}. Default \code{"/"} (ONA
#'   export style).
#' @param file_pattern Regex pattern used when \code{path} is a directory.
#'   Default \code{"_other_responses_edited\\\\.xlsx$"}.
#' @param skip_questions Character vector of question names to exclude from
#'   processing (e.g. free-text comments columns). Default \code{NULL}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row
#'   of \code{dataset} is treated as the ONA label/description row and excluded
#'   from the valid-uuid list so it cannot match against log file uuids.
#' @param verbose Logical. If \code{TRUE} (the default), progress messages are
#'   printed.
#'
#' @return A dataframe with columns \code{uuid}, \code{question},
#'   \code{action_taken}, \code{old_value}, \code{new_value}.
#' @export
read_other_responses <- function(
  path,
  dataset,
  other_db,
  tool_choices,
  uuid_column = "_uuid",
  log_uuid_col = "uuid",
  sm_separator = "/",
  file_pattern = "_other_responses_edited\\.xlsx$",
  skip_questions = NULL,
  skip_label_row = TRUE,
  verbose = TRUE
) {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    stop(
      "The 'readxl' package is required. Install it with: install.packages('readxl')"
    )
  }

  # ---- resolve files ----
  if (file.exists(path) && !dir.exists(path)) {
    files <- path
  } else if (dir.exists(path)) {
    files <- list.files(
      path,
      pattern = file_pattern,
      recursive = TRUE,
      full.names = TRUE
    )
    if (length(files) == 0) {
      stop(paste0("No files matching '", file_pattern, "' found in: ", path))
    }
  } else {
    stop(paste0("'path' does not exist: ", path))
  }

  if (verbose) {
    message("read_other_responses: reading ", length(files), " file(s).")
  }

  # ---- guard: every file must have the same columns ----
  # The files are stacked with rbind() below, which needs identical columns.
  # Checking the headers first turns "numbers of columns of arguments do not
  # match" into a message that names the offending file and the columns to fix.
  # Older logs carrying three "EXISTING other" slots instead of one are the
  # usual cause.
  ck_assert_log_columns(
    files = files,
    sheet = 1,
    caller = "read_other_responses",
    verbose = verbose
  )

  # ---- read and stack ----
  raw_list <- lapply(files, function(f) {
    tryCatch(
      readxl::read_excel(f, col_types = "text"),
      error = function(e) {
        warning(paste0("Could not read '", f, "': ", conditionMessage(e)))
        NULL
      }
    )
  })
  raw_list <- raw_list[!vapply(raw_list, is.null, logical(1))]
  if (length(raw_list) == 0) {
    stop("No other-response files could be read.")
  }

  or <- do.call(rbind, raw_list)
  if (verbose) {
    message("read_other_responses: ", nrow(or), " total rows read.")
  }

  # ---- rename verbose column headers to short working names ----
  rename_starts <- function(df, pattern, replacement) {
    hits <- stringr::str_starts(names(df), pattern)
    names(df)[hits] <- replacement
    df
  }
  or <- or |>
    rename_starts("TRUE", "true_other") |>
    rename_starts("INVALID", "invalid_other") |>
    rename_starts("FOLLOW", "fu_message")

  # "EXISTING other" columns are numbered by the order they appear in the file,
  # so both layouts are handled: the current single "EXISTING other" column, and
  # older logs that still carry "EXISTING other 1/2/3".
  exist_hits <- which(stringr::str_starts(names(or), "EXISTING"))
  if (length(exist_hits) > 0) {
    names(or)[exist_hits] <- paste0("existing_other_", seq_along(exist_hits))
  }

  # ---- check the uuid column exists in the log ----
  if (!(log_uuid_col %in% names(or))) {
    stop(paste0(
      "UUID column '",
      log_uuid_col,
      "' not found in the other-responses file(s). ",
      "Available columns: ",
      paste(names(or), collapse = ", "),
      ". ",
      "Set `log_uuid_col` to the correct column name."
    ))
  }

  # only one "EXISTING other" column is required; any further ones (from older
  # three-slot logs) are optional and merged in below
  required_cols <- c(
    log_uuid_col,
    "question_name",
    "list_name",
    "response_en",
    "true_other",
    "existing_other_1",
    "invalid_other"
  )
  missing_cols <- setdiff(required_cols, names(or))
  if (length(missing_cols) > 0) {
    stop(paste0(
      "Required column(s) missing from other-response file(s): ",
      paste(missing_cols, collapse = ", ")
    ))
  }

  # ---- build valid uuid set from dataset ----
  # Skip the ONA label/description row (row 1) before extracting uuids so the
  # label text never accidentally matches a log uuid.  The dataset uuid column
  # and the log uuid column are allowed to have different names.
  if (!(uuid_column %in% names(dataset))) {
    stop(paste0("UUID column '", uuid_column, "' not found in dataset."))
  }
  ds_for_uuids <- if (skip_label_row && nrow(dataset) > 0) {
    dataset[-1, , drop = FALSE]
  } else {
    dataset
  }
  valid_uuids <- trimws(as.character(ds_for_uuids[[uuid_column]]))
  valid_uuids <- valid_uuids[!is.na(valid_uuids) & nzchar(valid_uuids)]

  # ---- filter to valid uuids ----
  log_uuids <- trimws(as.character(or[[log_uuid_col]]))
  n_before <- nrow(or)
  or <- or[log_uuids %in% valid_uuids, , drop = FALSE]
  n_dropped <- n_before - nrow(or)
  if (n_dropped > 0) {
    if (verbose) {
      message(
        "read_other_responses: dropped ",
        n_dropped,
        " row(s) whose '",
        log_uuid_col,
        "' was not found in dataset '",
        uuid_column,
        "' column."
      )
    }
    if (nrow(or) == 0) {
      stop(paste0(
        "All ",
        n_before,
        " rows were dropped during uuid filtering. ",
        "Check that `uuid_column` ('",
        uuid_column,
        "') matches the dataset column ",
        "and `log_uuid_col` ('",
        log_uuid_col,
        "') matches the log file column. ",
        "First few dataset uuids: ",
        paste(head(valid_uuids, 5), collapse = ", "),
        ". ",
        "First few log uuids: ",
        paste(
          head(
            trimws(as.character(
              do.call(rbind, raw_list)[[log_uuid_col]]
            )),
            5
          ),
          collapse = ", "
        ),
        "."
      ))
    }
  }

  # make the uuid column in 'or' consistently named "uuid" internally
  # so downstream code always uses or$uuid regardless of log_uuid_col
  if (log_uuid_col != "uuid") {
    or[["uuid"]] <- or[[log_uuid_col]]
  }

  # ---- skip excluded questions ----
  if (!is.null(skip_questions) && length(skip_questions) > 0) {
    n_before2 <- nrow(or)
    or <- or[
      !(trimws(as.character(or$question_name)) %in% skip_questions),
      ,
      drop = FALSE
    ]
    if (verbose && (n_before2 - nrow(or)) > 0) {
      message(
        "read_other_responses: skipped ",
        n_before2 - nrow(or),
        " row(s) for excluded questions."
      )
    }
  }

  if (nrow(or) == 0) {
    warning("No rows remain after filtering.")
    return(.empty_other_log())
  }

  # ---- combine three existing_other slots into one semicolon-separated field ----
  or <- or |>
    tidyr::unite(
      "existing_other",
      dplyr::any_of(c(
        "existing_other_1",
        "existing_other_2",
        "existing_other_3"
      )),
      sep = ";",
      remove = TRUE,
      na.rm = TRUE
    ) |>
    dplyr::mutate(
      existing_other = dplyr::na_if(trimws(existing_other), "")
    )

  # ---- join question metadata from other_db ----
  or <- or |>
    dplyr::left_join(
      dplyr::select(
        other_db,
        name,
        ref_question,
        ref_type = q_type,
        option_other
      ),
      by = c("question_name" = "name")
    )

  # ---- classify rows and check mutual exclusivity ----
  or <- or |>
    dplyr::mutate(
      .n_filled = (!is.na(true_other) & nzchar(trimws(true_other))) +
        (!is.na(existing_other) & nzchar(trimws(existing_other))) +
        (!is.na(invalid_other) & nzchar(trimws(invalid_other)))
    )

  bad_rows <- or[or$.n_filled != 1, , drop = FALSE]
  if (nrow(bad_rows) > 0) {
    warning(paste0(
      nrow(bad_rows),
      " row(s) have zero or more than one action column filled ",
      "and will be excluded. uuids: ",
      paste(unique(bad_rows$uuid), collapse = ", ")
    ))
  }
  or <- or[or$.n_filled == 1, , drop = FALSE]
  or$.n_filled <- NULL

  if (nrow(or) == 0) {
    warning("No rows remain after action-type classification.")
    return(.empty_other_log())
  }

  # ---- split into the three groups ----
  or_true <- or[!is.na(or$true_other) & nzchar(trimws(or$true_other)), ]
  or_recode <- or[
    !is.na(or$existing_other) & nzchar(trimws(or$existing_other)),
  ]
  or_remove <- or[!is.na(or$invalid_other) & nzchar(trimws(or$invalid_other)), ]

  if (
    nrow(or_remove) > 0 && any(or_remove$invalid_other != "Yes", na.rm = TRUE)
  ) {
    stop(
      "INVALID other column contains values other than 'Yes'. Fix before proceeding."
    )
  }

  if (verbose) {
    message(
      "read_other_responses: ",
      nrow(or_true),
      " true_other | ",
      nrow(or_recode),
      " recode | ",
      nrow(or_remove),
      " remove."
    )
  }

  # ---- build cleaning log parts ----
  log_parts <- list()

  # 1) TRUE OTHER
  if (nrow(or_true) > 0) {
    log_parts[["true_other"]] <- data.frame(
      uuid = or_true$uuid,
      question = or_true$question_name,
      action_taken = "true_other",
      old_value = as.character(or_true$response_en),
      new_value = as.character(or_true$true_other),
      stringsAsFactors = FALSE
    )
  }

  # Convention detection is per parent question and identical for every log
  # row that touches it — memoise it so a large dataset is scanned once.
  conv_cache <- new.env(parent = emptyenv())

  # 2) REMOVE
  if (nrow(or_remove) > 0) {
    remove_rows <- lapply(seq_len(nrow(or_remove)), function(i) {
      .build_remove_rows(
        or_remove[i, ],
        dataset,
        uuid_column,
        sm_separator,
        skip_label_row,
        tool_choices,
        conv_cache
      )
    })
    log_parts[["remove"]] <- do.call(rbind, remove_rows)
  }

  # 3) RECODE
  if (nrow(or_recode) > 0) {
    recode_rows <- lapply(seq_len(nrow(or_recode)), function(i) {
      .build_recode_rows(
        or_recode[i, ],
        dataset,
        tool_choices,
        uuid_column,
        sm_separator,
        skip_label_row,
        conv_cache
      )
    })
    log_parts[["recode"]] <- do.call(rbind, recode_rows)
  }

  # Report the select-multiple conventions detected from the data, so a
  # mis-detection is visible in the console rather than only in the output.
  if (verbose) {
    for (k in ls(conv_cache)) {
      cv <- get(k, envir = conv_cache)
      message(
        "  ",
        sub("^q:", "", k),
        ": sub-columns named with ",
        if (cv$use_label) "choice labels" else "choice codes",
        "; selected = ",
        switch(
          cv$value_kind,
          binary = "\"1\"",
          suffix = "the choice text",
          label = "the choice label"
        ),
        ", not selected = ",
        if (is.na(cv$unsel_val)) "blank" else paste0("\"", cv$unsel_val, "\"")
      )
    }
  }

  result <- do.call(rbind, log_parts)
  rownames(result) <- NULL

  # ---- dedup: keep first occurrence of each uuid + question pair ----
  n_before_dedup <- nrow(result)
  result <- result[
    !duplicated(paste(result$uuid, result$question, sep = "__|__")),
  ]
  if (verbose && (n_before_dedup - nrow(result)) > 0) {
    message(
      "read_other_responses: removed ",
      n_before_dedup - nrow(result),
      " duplicate uuid+question row(s)."
    )
  }

  dup_key <- paste(result$uuid, result$question, sep = "__|__")
  if (any(duplicated(dup_key))) {
    dups <- unique(dup_key[duplicated(dup_key)])
    stop(paste0(
      "Duplicate uuid+question pairs remain: ",
      paste(gsub("__|__", " | ", dups), collapse = "; ")
    ))
  }

  if (verbose) {
    message("read_other_responses: returning ", nrow(result), " cleaning rows.")
  }
  result
}

# ---- internal helpers -------------------------------------------------------

#' @keywords internal
.empty_other_log <- function() {
  data.frame(
    uuid = character(0),
    question = character(0),
    action_taken = character(0),
    old_value = character(0),
    new_value = character(0),
    stringsAsFactors = FALSE
  )
}

#' Look up current value from dataset by uuid and column
#' @keywords internal
.get_val <- function(
  dataset,
  uuid_column,
  uuid,
  column,
  skip_label_row = TRUE
) {
  ds <- if (skip_label_row && nrow(dataset) > 0) {
    dataset[-1, , drop = FALSE]
  } else {
    dataset
  }
  if (!column %in% names(ds)) {
    return(NA_character_)
  }
  idx <- which(trimws(as.character(ds[[uuid_column]])) == uuid)
  if (length(idx) == 0) {
    return(NA_character_)
  }
  as.character(ds[[column]][idx[1]])
}

#' Get names of select-multiple sub-columns for a parent column
#' @keywords internal
.sm_sub_cols <- function(dataset, parent_col, sm_separator) {
  prefix <- paste0(parent_col, sm_separator)
  names(dataset)[stringr::str_starts(names(dataset), stringr::fixed(prefix))]
}

#' Build log rows for a REMOVE action
#' @keywords internal
.build_remove_rows <- function(
  x,
  dataset,
  uuid_column,
  sm_separator,
  skip_label_row = TRUE,
  tool_choices = NULL,
  conv_cache = NULL
) {
  rows <- list()
  uuid <- x$uuid
  ref_type <- x$ref_type
  gv <- function(col) .get_val(dataset, uuid_column, uuid, col, skip_label_row)

  # always blank the _other text column
  rows[[1]] <- data.frame(
    uuid = uuid,
    question = x$question_name,
    action_taken = "remove",
    old_value = as.character(x$response_en),
    new_value = NA_character_,
    stringsAsFactors = FALSE
  )

  if (identical(ref_type, "select_one")) {
    rows[[2]] <- data.frame(
      uuid = uuid,
      question = x$ref_question,
      action_taken = "remove",
      old_value = as.character(x$option_other),
      new_value = NA_character_,
      stringsAsFactors = FALSE
    )
  } else if (identical(ref_type, "select_multiple")) {
    vocab <- .get_vocab(x$list_name, tool_choices)
    conv <- .detect_sm_convention(
      dataset,
      x$ref_question,
      sm_separator,
      list_name = x$list_name,
      tool_choices = tool_choices,
      skip_label_row = skip_label_row,
      cache = conv_cache
    )
    all_sub <- conv$sub_cols
    suffixes <- conv$suffixes
    use_lbl <- conv$use_label
    other_lbl <- .resolve_token_to_token(
      x$option_other,
      x$list_name,
      tool_choices,
      "label"
    )
    other_nm <- .resolve_token_to_token(
      x$option_other,
      x$list_name,
      tool_choices,
      "name"
    )
    token_rem <- if (use_lbl) other_lbl else other_nm
    old_concat <- gv(x$ref_question)
    new_concat <- .remove_token(
      if (is.na(old_concat)) "" else old_concat,
      token_rem,
      vocab
    )
    new_concat <- if (trimws(new_concat) == "") {
      NA_character_
    } else {
      trimws(new_concat)
    }

    if (is.na(new_concat)) {
      # removing this choice empties the parent — blank all sub-columns too
      for (col in all_sub) {
        rows[[length(rows) + 1]] <- data.frame(
          uuid = uuid,
          question = col,
          action_taken = "remove",
          old_value = as.character(gv(col)),
          new_value = conv$unsel_val,
          stringsAsFactors = FALSE
        )
      }
      rows[[length(rows) + 1]] <- data.frame(
        uuid = uuid,
        question = x$ref_question,
        action_taken = "remove",
        old_value = as.character(old_concat),
        new_value = NA_character_,
        stringsAsFactors = FALSE
      )
    } else {
      # blank (NA) the sub-column for the other option
      sub_col <- .find_sub_col(
        all_sub,
        suffixes,
        c(token_rem, other_lbl, other_nm, x$option_other)
      )
      if (!is.na(sub_col)) {
        rows[[length(rows) + 1]] <- data.frame(
          uuid = uuid,
          question = sub_col,
          action_taken = "remove",
          old_value = as.character(gv(sub_col)),
          new_value = conv$unsel_val,
          stringsAsFactors = FALSE
        )
      }
      rows[[length(rows) + 1]] <- data.frame(
        uuid = uuid,
        question = x$ref_question,
        action_taken = "remove",
        old_value = as.character(old_concat),
        new_value = new_concat,
        stringsAsFactors = FALSE
      )
    }
  } else if (identical(ref_type, "text")) {
    rows[[2]] <- data.frame(
      uuid = uuid,
      question = x$ref_question,
      action_taken = "remove",
      old_value = as.character(x$response_en),
      new_value = NA_character_,
      stringsAsFactors = FALSE
    )
  }

  do.call(rbind, rows)
}

#' Split a space-joined multi-word token string using a known vocabulary
#'
#' The concat column in ONA exports joins selected values with spaces. When
#' values are multi-word labels (e.g. "Travel in a group Plan my journey
#' carefully Other") a naive whitespace split breaks them. This function
#' greedily matches the longest known token from \code{vocab} (sorted by
#' descending word count), case-insensitively, so multi-word labels are
#' correctly identified as atomic tokens.
#'
#' @param concat Space-joined string of selected values.
#' @param vocab  Character vector of all valid tokens for this question.
#' @return Character vector of matched tokens (in original order).
#' @keywords internal
.split_concat <- function(concat, vocab) {
  if (is.na(concat) || !nzchar(trimws(concat))) {
    return(character(0))
  }
  toks <- strsplit(trimws(concat), "\\s+")[[1]]
  toks <- toks[nzchar(toks)]
  if (length(toks) == 0) {
    return(character(0))
  }

  # fast path: every whitespace-token is itself in the vocab (pure-code datasets)
  if (all(toks %in% vocab)) {
    return(toks)
  }

  # greedy longest-match (descending word count, case-insensitive)
  vocab_words <- strsplit(vocab, "\\s+")
  ord <- order(-lengths(vocab_words))
  vocab_ord <- vocab[ord]
  vocab_lc <- lapply(vocab_words[ord], tolower)
  toks_lc <- tolower(toks)

  out <- character(0)
  i <- 1L
  n <- length(toks)
  while (i <= n) {
    matched <- NA_character_
    for (j in seq_along(vocab_ord)) {
      L <- length(vocab_lc[[j]])
      if (
        i + L - 1L <= n &&
          identical(toks_lc[i:(i + L - 1L)], vocab_lc[[j]])
      ) {
        matched <- vocab_ord[j]
        i <- i + L
        break
      }
    }
    if (is.na(matched)) {
      out <- c(out, toks[i]) # unknown token: keep as-is
      i <- i + 1L
    } else {
      out <- c(out, matched)
    }
  }
  out
}

#' Remove a token from a space-joined concat using vocabulary-aware splitting
#' @keywords internal
.remove_token <- function(concat, token, vocab) {
  tokens <- .split_concat(concat, vocab)
  tokens <- tokens[!tolower(tokens) %in% tolower(token)]
  if (length(tokens) == 0) {
    return("")
  }
  paste(tokens, collapse = " ")
}

#' Add a token to a space-joined concat (appended at end if not already present)
#' @keywords internal
.add_token <- function(concat, token, vocab) {
  tokens <- .split_concat(concat, vocab)
  if (any(tolower(tokens) == tolower(token))) {
    return(paste(tokens, collapse = " "))
  }
  paste(c(tokens, token), collapse = " ")
}

#' Get the vocabulary (all valid tokens) for a list from tool_choices
#' @keywords internal
.get_vocab <- function(list_name, tool_choices) {
  if (is.null(tool_choices)) {
    return(character(0))
  }
  tc <- tool_choices[
    !is.na(tool_choices$list_name) &
      tool_choices$list_name == list_name,
  ]
  # both names and labels are valid tokens depending on dataset convention
  unique(c(as.character(tc$name), as.character(tc$label)))
}

#' Strip the parent prefix from select-multiple sub-column names
#' @keywords internal
.sm_suffixes <- function(sub_cols, parent_col, sm_separator) {
  substring(sub_cols, nchar(parent_col) + nchar(sm_separator) + 1L)
}

#' Normalise a token for comparison (trim + lowercase)
#' @keywords internal
.norm_tok <- function(x) {
  tolower(trimws(as.character(x)))
}

#' Locate the sub-column that actually exists for a choice
#'
#' The dataset may name sub-columns with the choice label
#' (\code{Q83/Insufficient access to basic goods}) or the choice code
#' (\code{Q83/2}), and the casing/spacing may differ from \code{tool_choices}.
#' This tries each candidate token in turn, case- and whitespace-insensitively,
#' and returns the real column name.
#'
#' @param sub_cols Character vector of the parent's sub-column names.
#' @param suffixes The matching suffixes (see \code{.sm_suffixes()}).
#' @param tokens Candidate tokens, in priority order.
#' @return The matching column name, or \code{NA_character_}.
#' @keywords internal
.find_sub_col <- function(sub_cols, suffixes, tokens) {
  if (length(sub_cols) == 0) {
    return(NA_character_)
  }
  suff_n <- .norm_tok(suffixes)
  for (tk in tokens) {
    if (length(tk) == 0) next
    tk <- tk[1]
    if (is.na(tk) || !nzchar(trimws(tk))) next
    hit <- which(suff_n == .norm_tok(tk))
    if (length(hit) > 0) {
      return(sub_cols[hit[1]])
    }
  }
  NA_character_
}

#' Detect the "selected" marker used across the dataset as a whole
#'
#' Used only as a last resort, when the question being cleaned has no filled
#' sub-column to learn from. Scans other select-multiple sub-columns anywhere in
#' the dataset: if their filled values are all \code{0}/\code{1}, the export is
#' binary; if any filled value equals its own column suffix, the export writes
#' the choice text.
#'
#' @return \code{"binary"}, \code{"suffix"}, or \code{NA_character_}.
#' @keywords internal
.detect_dataset_sm_style <- function(ds, sm_separator, max_cols = 300L) {
  cand <- names(ds)[grepl(sm_separator, names(ds), fixed = TRUE)]
  if (length(cand) == 0) {
    return(NA_character_)
  }
  if (length(cand) > max_cols) {
    cand <- cand[seq_len(max_cols)]
  }
  saw_binary <- FALSE
  for (col in cand) {
    pos <- regexpr(sm_separator, col, fixed = TRUE)
    if (pos < 1L) next
    suffix <- substring(col, pos + nchar(sm_separator))
    if (!nzchar(suffix)) next
    vals <- as.character(ds[[col]])
    vals <- vals[!is.na(vals) & nzchar(trimws(vals))]
    if (length(vals) == 0) next
    v <- .norm_tok(vals)
    if (any(v == .norm_tok(suffix))) {
      return("suffix")
    }
    if (all(v %in% c("0", "1", "true", "false"))) {
      saw_binary <- TRUE
    }
  }
  if (saw_binary) "binary" else NA_character_
}

#' Detect the select-multiple conventions used by a parent question
#'
#' Two independent things have to be detected, and getting either wrong writes
#' values the export never uses:
#' \enumerate{
#'   \item \strong{Header tokens} — are sub-columns named with the choice
#'     \emph{label} (\code{Q83/Insufficient access to basic goods}) or the
#'     choice \emph{code} (\code{Q83/2})?
#'   \item \strong{Selected marker} — what does a selected cell contain? Either
#'     \code{"1"} (binary export) or the choice text itself (label export, where
#'     an unselected cell is simply blank).
#' }
#' Detection looks at every sub-column of the question (not a 5-column sample),
#' then at the parent concat column, then at the rest of the dataset. If nothing
#' in the data indicates a binary export, the choice-text convention wins: a
#' label export must never have \code{0}/\code{1} introduced into it.
#'
#' @param dataset The dataset.
#' @param parent_col The parent select-multiple column name.
#' @param sm_separator Sub-column separator.
#' @param list_name The \code{list_name} of the question's choices.
#' @param tool_choices The XLSForm choices sheet.
#' @param skip_label_row Whether the first row is the ONA label row.
#' @param cache Optional environment used to memoise detection per question.
#' @return A list with \code{use_label} (logical, headers carry labels),
#'   \code{value_kind} (\code{"binary"}, \code{"suffix"} or \code{"label"}),
#'   \code{sel_fn} (\code{f(suffix, label)} giving the value to write when
#'   marking a choice selected), \code{sub_cols} and \code{suffixes}.
#' @keywords internal
.detect_sm_convention <- function(
  dataset,
  parent_col,
  sm_separator,
  list_name = NULL,
  tool_choices = NULL,
  skip_label_row = TRUE,
  cache = NULL
) {
  key <- paste0("q:", parent_col)
  if (!is.null(cache) && exists(key, envir = cache, inherits = FALSE)) {
    return(get(key, envir = cache, inherits = FALSE))
  }

  sub_cols <- .sm_sub_cols(dataset, parent_col, sm_separator)
  suffixes <- .sm_suffixes(sub_cols, parent_col, sm_separator)

  ds <- if (skip_label_row && nrow(dataset) > 0) {
    dataset[-1, , drop = FALSE]
  } else {
    dataset
  }

  # ---- choice vocabulary for this question ----
  ch_lbl <- character(0)
  ch_nm <- character(0)
  if (
    is.data.frame(tool_choices) &&
      !is.null(list_name) &&
      !is.na(list_name) &&
      all(c("list_name", "label", "name") %in% names(tool_choices))
  ) {
    tc <- tool_choices[
      !is.na(tool_choices$list_name) & tool_choices$list_name == list_name,
      ,
      drop = FALSE
    ]
    ch_lbl <- as.character(tc$label)
    ch_nm <- as.character(tc$name)
  }

  # ---- 1. do the HEADERS carry labels or codes? ----
  n_lbl <- sum(.norm_tok(suffixes) %in% .norm_tok(ch_lbl))
  n_nm <- sum(.norm_tok(suffixes) %in% .norm_tok(ch_nm))
  use_label <- if (n_lbl > 0 || n_nm > 0) {
    n_lbl >= n_nm
  } else {
    # nothing to match against: a multi-word suffix can only be a label
    any(grepl(" ", suffixes, fixed = TRUE))
  }

  # ---- 2. what value marks a choice as SELECTED? ----
  value_kind <- NA_character_
  saw_zero <- FALSE
  for (i in seq_along(sub_cols)) {
    vals <- as.character(ds[[sub_cols[i]]])
    vals <- vals[!is.na(vals) & nzchar(trimws(vals))]
    if (length(vals) == 0) next
    v <- .norm_tok(vals)
    if (any(v %in% c("0", "false"))) {
      saw_zero <- TRUE
    }
    if (any(v == .norm_tok(suffixes[i]))) {
      value_kind <- "suffix" # cell holds its own column's choice text
      break
    }
    if (length(ch_lbl) > 0 && any(v %in% .norm_tok(ch_lbl))) {
      value_kind <- "label" # coded headers, but the cell holds the label
      break
    }
    if (all(v %in% c("0", "1", "true", "false"))) {
      value_kind <- "binary"
      # keep scanning: a later sub-column may prove it is a label export
    }
  }

  if (is.na(value_kind)) {
    # No filled sub-column for this question. Try the parent concat column: in a
    # label export it holds the choice text, in a binary export only 0/1.
    parent_vals <- if (parent_col %in% names(ds)) {
      as.character(ds[[parent_col]])
    } else {
      character(0)
    }
    parent_vals <- parent_vals[
      !is.na(parent_vals) & nzchar(trimws(parent_vals))
    ]
    if (
      length(parent_vals) > 0 &&
        all(.norm_tok(parent_vals) %in% c("0", "1", "true", "false"))
    ) {
      value_kind <- "binary"
    } else {
      value_kind <- .detect_dataset_sm_style(ds, sm_separator)
    }
  }

  if (is.na(value_kind)) {
    # Still no evidence anywhere. Default to the choice-text convention so a
    # label export is never given 0/1 it did not have.
    value_kind <- if (use_label) "suffix" else "label"
  }

  sel_fn <- switch(
    value_kind,
    binary = function(suffix, label = NULL) "1",
    suffix = function(suffix, label = NULL) suffix,
    label = function(suffix, label = NULL) {
      if (
        !is.null(label) && length(label) > 0 && !is.na(label[1]) &&
          nzchar(label[1])
      ) {
        label[1]
      } else {
        suffix
      }
    }
  )

  # What an UNSELECTED cell looks like: "0" only where the export actually
  # writes zeros, blank (NA) everywhere else — a label export stays blank.
  unsel_val <- if (identical(value_kind, "binary") && saw_zero) {
    "0"
  } else {
    NA_character_
  }

  out <- list(
    use_label = use_label,
    value_kind = value_kind,
    unsel_val = unsel_val,
    sel_fn = sel_fn,
    sub_cols = sub_cols,
    suffixes = suffixes
  )
  if (!is.null(cache)) {
    assign(key, out, envir = cache)
  }
  out
}
#' @keywords internal
.resolve_token_to_token <- function(
  token,
  list_name,
  tool_choices,
  to = "label"
) {
  if (is.null(tool_choices)) {
    return(token)
  }
  tc <- tool_choices[
    !is.na(tool_choices$list_name) &
      tool_choices$list_name == list_name,
  ]
  # try matching token as name first, then as label
  idx <- which(tc$name == token)
  if (length(idx) == 0) {
    idx <- which(tc$label == token)
  }
  if (length(idx) == 0) {
    return(token)
  }
  as.character(tc[[to]][idx[1]])
}

#' Build log rows for a RECODE action
#' @keywords internal
.build_recode_rows <- function(
  x,
  dataset,
  tool_choices,
  uuid_column,
  sm_separator,
  skip_label_row = TRUE,
  conv_cache = NULL
) {
  rows <- list()
  uuid <- x$uuid
  ref_type <- x$ref_type
  gv <- function(col) .get_val(dataset, uuid_column, uuid, col, skip_label_row)

  # always blank the _other text column
  rows[[1]] <- data.frame(
    uuid = uuid,
    question = x$question_name,
    action_taken = "recode",
    old_value = as.character(x$response_en),
    new_value = NA_character_,
    stringsAsFactors = FALSE
  )

  if (identical(ref_type, "select_one")) {
    new_code <- get_name_from_label(
      x$list_name,
      trimws(x$existing_other),
      tool_choices
    )
    if (length(new_code) == 0 || is.na(new_code[1])) {
      warning(paste0(
        "Choice label not found in tool_choices — skipping recode ",
        "for uuid '",
        uuid,
        "', label '",
        x$existing_other,
        "'"
      ))
      return(rows[[1]])
    }
    rows[[2]] <- data.frame(
      uuid = uuid,
      question = x$ref_question,
      action_taken = "recode",
      old_value = as.character(gv(x$ref_question)),
      new_value = as.character(new_code[1]),
      stringsAsFactors = FALSE
    )
  } else if (identical(ref_type, "select_multiple")) {
    # Split the existing_other field on ";;" or ";" to get individual labels
    raw_existing <- trimws(x$existing_other)
    chosen_labels <- if (grepl(";;", raw_existing, fixed = TRUE)) {
      trimws(stringr::str_split(raw_existing, ";;")[[1]])
    } else {
      trimws(stringr::str_split(raw_existing, ";")[[1]])
    }
    chosen_labels <- chosen_labels[nzchar(chosen_labels)]

    # Validate every chosen label exists in tool_choices — skip unknowns
    valid_labels <- c()
    for (l in chosen_labels) {
      cd <- get_name_from_label(x$list_name, l, tool_choices)
      if (length(cd) == 0 || is.na(cd[1]) || !nzchar(cd[1])) {
        warning(paste0(
          "Label '",
          l,
          "' not found in tool_choices list '",
          x$list_name,
          "' for uuid '",
          uuid,
          "' — skipped. Check the label matches exactly."
        ))
      } else {
        valid_labels <- c(valid_labels, l)
      }
    }

    vocab <- .get_vocab(x$list_name, tool_choices)
    old_concat <- gv(x$ref_question)
    new_concat <- if (is.na(old_concat)) "" else old_concat

    # Detect, from the data itself, (a) whether sub-columns are named with the
    # choice label or the choice code, and (b) what a selected cell contains —
    # "1" in a binary export, or the choice text in a label export where an
    # unselected cell is blank. See .detect_sm_convention().
    conv <- .detect_sm_convention(
      dataset,
      x$ref_question,
      sm_separator,
      list_name = x$list_name,
      tool_choices = tool_choices,
      skip_label_row = skip_label_row,
      cache = conv_cache
    )
    use_label_convention <- conv$use_label
    sel_fn <- conv$sel_fn
    all_sub_cols <- conv$sub_cols
    suffixes <- conv$suffixes

    option_other <- x$option_other # from other_db (could be code OR label)

    # Resolve the "other" option to both forms, then pick the one the dataset uses
    other_lbl <- .resolve_token_to_token(
      option_other,
      x$list_name,
      tool_choices,
      to = "label"
    )
    other_nm <- .resolve_token_to_token(
      option_other,
      x$list_name,
      tool_choices,
      to = "name"
    )
    token_to_remove <- if (use_label_convention) other_lbl else other_nm
    sub_col_other <- .find_sub_col(
      all_sub_cols,
      suffixes,
      c(token_to_remove, other_lbl, other_nm, option_other)
    )

    # Remove the "other" token from the concat; blank its sub-column
    new_concat <- .remove_token(new_concat, token_to_remove, vocab)
    if (!is.na(sub_col_other)) {
      rows[[length(rows) + 1]] <- data.frame(
        uuid = uuid,
        question = sub_col_other,
        action_taken = "recode",
        old_value = as.character(gv(sub_col_other)),
        new_value = conv$unsel_val,
        stringsAsFactors = FALSE
      )
    }

    # Add each validated label (or its code) to the concat;
    # set its sub-column to the dataset's "selected" value
    for (lbl in valid_labels) {
      lbl_code <- get_name_from_label(x$list_name, lbl, tool_choices)
      token_to_add <- if (use_label_convention) lbl else lbl_code
      sub_col <- .find_sub_col(
        all_sub_cols,
        suffixes,
        c(token_to_add, lbl, lbl_code)
      )
      if (!is.na(sub_col)) {
        # Write exactly what this export uses for "selected": the column's own
        # suffix / the choice label in a label export, "1" in a binary one.
        suffix_for_sel <- .sm_suffixes(sub_col, x$ref_question, sm_separator)
        want <- sel_fn(suffix_for_sel, lbl)
        cur_val <- gv(sub_col)
        if (!identical(cur_val, want)) {
          rows[[length(rows) + 1]] <- data.frame(
            uuid = uuid,
            question = sub_col,
            action_taken = "recode",
            old_value = as.character(cur_val),
            new_value = want,
            stringsAsFactors = FALSE
          )
        }
      } else {
        warning(paste0(
          "No sub-column found for choice '",
          lbl,
          "' under '",
          x$ref_question,
          "' — the parent column was updated but no child column was set."
        ))
      }
      new_concat <- .add_token(new_concat, token_to_add, vocab)
    }

    new_concat <- trimws(new_concat)
    new_concat <- if (!nzchar(new_concat)) NA_character_ else new_concat
    final_old <- as.character(old_concat)
    if (!identical(new_concat, final_old)) {
      rows[[length(rows) + 1]] <- data.frame(
        uuid = uuid,
        question = x$ref_question,
        action_taken = "recode",
        old_value = final_old,
        new_value = new_concat,
        stringsAsFactors = FALSE
      )
    }
  }

  do.call(rbind, rows)
}


#' Apply Other Responses Cleaning Log to a Dataset
#'
#' Applies every row of the cleaning log produced by \code{read_other_responses()}
#' to the dataset. A direct replacement for the manual apply loop.
#'
#' @param dataset The current working dataset to modify.
#' @param other_log The cleaning log produced by \code{read_other_responses()}.
#' @param uuid_column Name of the uuid column in \code{dataset}. Default
#'   \code{"_uuid"}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), changes are
#'   never applied to the first (ONA label) row even if its uuid somehow
#'   matched.
#'
#' @details
#' Values are written back in whatever convention the export already uses.
#' For select-multiple sub-columns this is detected from the data by
#' \code{read_other_responses()} (see \code{.detect_sm_convention()}): in a
#' label export a selected choice holds the choice text and an unselected one
#' stays blank, and in a binary export they hold \code{"1"} and \code{"0"}.
#' \code{0}/\code{1} are only ever introduced where the export already
#' contains them.
#' @param verbose Logical. If \code{TRUE} (the default), a message is printed
#'   for each change applied, matching the original loop output.
#'
#' @return A list with:
#'   \item{dataset}{The modified dataset.}
#'   \item{audit_log}{A dataframe recording every change with columns
#'     \code{uuid}, \code{question}, \code{action_taken}, \code{value_before},
#'     \code{value_after}.}
#' @export
apply_other_responses <- function(
  dataset,
  other_log,
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  verbose = TRUE
) {
  if (!is.data.frame(dataset)) {
    stop("`dataset` must be a dataframe.")
  }
  if (!is.data.frame(other_log) || nrow(other_log) == 0) {
    message("apply_other_responses: nothing to apply.")
    return(list(dataset = dataset, audit_log = .empty_audit()))
  }
  if (!(uuid_column %in% names(dataset))) {
    stop(paste0("Cannot find '", uuid_column, "' in dataset."))
  }

  # never touch the label row
  label_row <- NULL
  data_start <- 1L
  if (skip_label_row && nrow(dataset) > 0) {
    label_row <- dataset[1, , drop = FALSE]
    dataset <- dataset[-1, , drop = FALSE]
    data_start <- 2L
  }

  dataset_uuids <- trimws(as.character(dataset[[uuid_column]]))
  audit <- vector("list", nrow(other_log))

  for (r in seq_len(nrow(other_log))) {
    uuid <- trimws(as.character(other_log$uuid[r]))
    question <- trimws(as.character(other_log$question[r]))
    new_value <- other_log$new_value[r]
    action <- as.character(other_log$action_taken[r])

    row_match <- which(dataset_uuids == uuid)
    if (length(row_match) == 0) {
      warning(paste0("Row ", r, ": uuid '", uuid, "' not found — skipped."))
      next
    }
    if (!(question %in% names(dataset))) {
      warning(paste0(
        "Row ",
        r,
        ": question '",
        question,
        "' not found in dataset — skipped."
      ))
      next
    }

    old_value <- as.character(dataset[[question]][row_match[1]])
    dataset[[question]][row_match[1]] <- new_value

    if (verbose) {
      message(sprintf(
        "%d - %s - %s: %s --> %s",
        r,
        uuid,
        question,
        ifelse(is.na(old_value), "<NA>", old_value),
        ifelse(is.na(new_value), "<NA>", new_value)
      ))
    }

    audit[[r]] <- data.frame(
      uuid = uuid,
      question = question,
      action_taken = action,
      value_before = old_value,
      value_after = as.character(new_value),
      stringsAsFactors = FALSE
    )
  }

  audit_log <- do.call(rbind, audit[!vapply(audit, is.null, logical(1))])
  if (is.null(audit_log)) {
    audit_log <- .empty_audit()
  }
  rownames(audit_log) <- NULL

  # reattach label row
  if (!is.null(label_row)) {
    dataset <- rbind(label_row, dataset)
  }

  message("apply_other_responses: ", nrow(audit_log), " change(s) applied.")
  list(dataset = dataset, audit_log = audit_log)
}

#' @keywords internal
.empty_audit <- function() {
  data.frame(
    uuid = character(0),
    question = character(0),
    action_taken = character(0),
    value_before = character(0),
    value_after = character(0),
    stringsAsFactors = FALSE
  )
}
