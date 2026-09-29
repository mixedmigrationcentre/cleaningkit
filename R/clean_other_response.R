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
#'     \code{Input translation or improved text ...}. The parent question is not
#'     touched.}
#'   \item{\code{recode}}{The response actually matches an existing choice.
#'     The \code{Correct to existing answer option ...} column is filled (older
#'     logs with several numbered \code{EXISTING other} columns are still read
#'     and merged). For
#'     \code{select_one}: blanks the \code{_other} text column, sets the parent
#'     to the matched choice code. For \code{select_multiple}: blanks the
#'     \code{_other} text column, removes the \code{other} option from the
#'     parent concatenation, and adds the matched choice(s).}
#'   \item{\code{remove}}{The response is invalid
#'     (\code{Invalid other ... == "Yes"}).
#'     Blanks the \code{_other} text column and removes/blanks the parent
#'     question reference.}
#' }
#'
#' \strong{Header names:} the reviewer columns are matched by prefix, case
#' insensitively, against both the headers written by the current
#' \code{prepare_other_responses()} and the earlier \code{TRUE other} /
#' \code{EXISTING other} / \code{INVALID other} / \code{FOLLOW-UP message}
#' headers, so a file reviewed before the rename is read exactly as before. The
#' patterns are defined once in \code{.ck_other_review_patterns()}.
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
#' \strong{Mutual exclusivity:} a row may have at most one of
#' \code{true_other}, \code{existing_other}, or \code{invalid_other} filled.
#' Rows with more than one filled are contradictory - the reviewer has asked for
#' two different things on one response - so they are excluded and their uuids
#' named in a warning.
#'
#' \strong{Rows left blank:} a row with all three action columns blank is not an
#' error. It is the normal way a reviewer records that the "other" text is a
#' valid answer as it stands and the record should not change. Such rows produce
#' no cleaning-log entry (there is no data point to change, so logging one would
#' only pad the log) and no warning; they are counted in the \code{verbose}
#' summary as \emph{no change (kept as-is)}. A file in which every row is blank
#' therefore returns an empty log quietly rather than warning.
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
    message(
      "read_other_responses: ",
      nrow(or),
      " other-response row(s) read."
    )
  }

  # ---- rename verbose column headers to short working names ----
  # The patterns come from .ck_other_review_patterns(), which matches both the
  # current headers written by prepare_other_responses() ("Input translation
  # ...", "Correct to existing answer option ...", "Invalid other ...",
  # "Comment from IM") and the earlier TRUE / EXISTING / INVALID / FOLLOW-UP
  # ones, so a file reviewed before the rename is still read correctly.
  rename_matching <- function(df, pattern, replacement) {
    hits <- grepl(pattern, names(df), ignore.case = TRUE)
    names(df)[hits] <- replacement
    df
  }
  review_pat <- .ck_other_review_patterns()
  or <- or |>
    rename_matching(review_pat[["true_other"]], "true_other") |>
    rename_matching(review_pat[["invalid_other"]], "invalid_other") |>
    rename_matching(review_pat[["fu_message"]], "fu_message")

  # The recode columns are numbered by the order they appear in the file, so
  # both layouts are handled: the current single "Correct to existing answer
  # option" column, and older logs that still carry "EXISTING other 1/2/3".
  exist_hits <- which(grepl(
    review_pat[["existing_other"]],
    names(or),
    ignore.case = TRUE
  ))
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

  # Zero filled and more than one filled are different situations and are not
  # reported the same way.
  #
  # Zero filled is the normal outcome for a response the reviewer read and
  # accepted as it stands: the "other" text is a valid answer and nothing about
  # the record should change. There is nothing to fix and nothing to apply, so
  # the row is dropped quietly and only counted in the verbose summary. It used
  # to be lumped in with the conflict case below and raise a warning, which read
  # as an error on a sheet where most rows are legitimately blank.
  #
  # More than one filled is a genuine conflict - the reviewer asked for two
  # contradictory things on one response - so it still warns and names the
  # uuids.
  n_no_change <- sum(or$.n_filled == 0)

  conflict_rows <- or[or$.n_filled > 1, , drop = FALSE]
  if (nrow(conflict_rows) > 0) {
    warning(paste0(
      nrow(conflict_rows),
      " row(s) have more than one action column filled ",
      "and will be excluded. uuids: ",
      paste(unique(conflict_rows$uuid), collapse = ", ")
    ))
  }

  or <- or[or$.n_filled == 1, , drop = FALSE]
  or$.n_filled <- NULL

  if (nrow(or) == 0) {
    # Every row being "no change" is a valid review outcome, not a problem, so
    # it is reported as a message. A warning is kept for the cases where rows
    # were actually lost (conflicts, or nothing recognisable at all).
    if (nrow(conflict_rows) == 0 && n_no_change > 0) {
      if (verbose) {
        message(
          "read_other_responses: all ",
          n_no_change,
          " other-response row(s) were left blank by the reviewer ",
          "(valid as they stand); no cleaning-log rows to apply."
        )
      }
    } else {
      warning("No rows remain after action-type classification.")
    }
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
      "The invalid-other column ('Invalid other ...') contains values other than 'Yes'. Fix before proceeding."
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
      " remove | ",
      n_no_change,
      " no change (kept as-is) (",
      nrow(or_true) + nrow(or_recode) + nrow(or_remove),
      " other-response row(s) to apply)."
    )
  }

  n_input_rows <- nrow(or_true) + nrow(or_recode) + nrow(or_remove)

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

  # uuid -> row position, built once: every value lookup below uses it instead
  # of re-scanning the dataset.
  uuid_index <- .make_uuid_index(dataset, uuid_column, skip_label_row)

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
        conv_cache,
        uuid_index
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
        conv_cache,
        uuid_index
      )
    })
    log_parts[["recode"]] <- do.call(rbind, recode_rows)
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
    # One other-response row becomes several cleaning-log rows: the _other text
    # column is blanked, the "other" child column is unset, each recoded child
    # column is set, and the parent column is rewritten. So this count is
    # expected to exceed the number of rows read.
    message(
      "read_other_responses: returning ",
      nrow(result),
      " cleaning-log row(s) from ",
      n_input_rows,
      " other-response row(s)."
    )
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

#' Row positions of the actual data (everything but the ONA label row)
#' @keywords internal
.data_rows <- function(dataset, skip_label_row = TRUE) {
  n <- nrow(dataset)
  if (n == 0) {
    return(integer(0))
  }
  if (skip_label_row) seq_len(n)[-1] else seq_len(n)
}

#' Build a uuid -> row position lookup for the dataset
#'
#' Built once per call and reused for every lookup. Resolving a uuid used to
#' mean copying the whole dataframe and re-scanning the uuid column, which on a
#' wide export costs more than all the cleaning logic put together.
#'
#' @return A named integer vector: uuid -> row position in \code{dataset}
#'   (positions refer to the original dataframe, label row included).
#' @keywords internal
.make_uuid_index <- function(dataset, uuid_column, skip_label_row = TRUE) {
  rows <- .data_rows(dataset, skip_label_row)
  if (length(rows) == 0 || !(uuid_column %in% names(dataset))) {
    return(integer(0))
  }
  u <- trimws(as.character(dataset[[uuid_column]][rows]))
  keep <- !is.na(u) & nzchar(u) & !duplicated(u)
  stats::setNames(rows[keep], u[keep])
}

#' Look up current value from dataset by uuid and column
#' @keywords internal
.get_val <- function(
  dataset,
  uuid_column,
  uuid,
  column,
  skip_label_row = TRUE,
  uuid_index = NULL
) {
  if (!column %in% names(dataset)) {
    return(NA_character_)
  }
  if (is.null(uuid_index)) {
    uuid_index <- .make_uuid_index(dataset, uuid_column, skip_label_row)
  }
  i <- uuid_index[[uuid]]
  if (is.null(i) || is.na(i)) {
    return(NA_character_)
  }
  as.character(dataset[[column]][i])
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
  conv_cache = NULL,
  uuid_index = NULL
) {
  rows <- list()
  uuid <- x$uuid
  ref_type <- x$ref_type
  gv <- function(col) {
    .get_val(dataset, uuid_column, uuid, col, skip_label_row, uuid_index)
  }
  tc_norm <- .norm_tool_choices(tool_choices, conv_cache)

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
    vocab <- unique(c(suffixes, vocab))

    # Match the "other" option against the dataset's own sub-columns first, so a
    # list_name that no longer matches tool_choices cannot pick the wrong token.
    other_cands <- .choice_tokens(
      x$option_other,
      x$list_name,
      tool_choices,
      tc_norm
    )
    sub_col <- .find_sub_col(all_sub, suffixes, other_cands)
    token_rem <- if (!is.na(sub_col)) {
      .sm_suffixes(sub_col, x$ref_question, sm_separator)
    } else {
      hit <- other_cands[.norm_tok(other_cands) %in% .norm_tok(vocab)]
      if (length(hit) > 0) hit[1] else other_cands[1]
    }
    old_concat <- gv(x$ref_question)
    new_concat <- if (is.na(old_concat)) "" else old_concat
    for (tk in unique(c(token_rem, other_cands))) {
      new_concat <- .remove_token(new_concat, tk, vocab)
    }
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
      # blank the sub-column for the other option
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

#' Normalise a token loosely: lowercase, punctuation to spaces, spaces collapsed
#'
#' Two versions of the same XLSForm often differ only in punctuation or spacing
#' (\code{"Other (specify)"} vs \code{"Other(specify)"}), so exact matching
#' alone loses choices that are plainly the same.
#' @keywords internal
.norm_loose <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", " ", x)
  trimws(gsub("\\s+", " ", x))
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
  tokens <- unlist(tokens, use.names = FALSE)
  tokens <- tokens[!is.na(tokens) & nzchar(trimws(tokens))]
  if (length(tokens) == 0) {
    return(NA_character_)
  }
  # exact (trim + case-insensitive) first, then punctuation-insensitive
  suff_n <- .norm_tok(suffixes)
  for (tk in tokens) {
    hit <- which(suff_n == .norm_tok(tk))
    if (length(hit) > 0) {
      return(sub_cols[hit[1]])
    }
  }
  suff_l <- .norm_loose(suffixes)
  for (tk in tokens) {
    hit <- which(suff_l == .norm_loose(tk))
    if (length(hit) > 0) {
      return(sub_cols[hit[1]])
    }
  }
  NA_character_
}

#' Pre-normalised view of tool_choices, computed once per call
#'
#' Choice lookups compare normalised text, and normalising the whole choices
#' sheet on every lookup dominated the runtime. This builds the normalised
#' vectors once and memoises them in the shared cache.
#' @keywords internal
.norm_tool_choices <- function(tool_choices, cache = NULL) {
  key <- "tc:normalised"
  if (!is.null(cache) && exists(key, envir = cache, inherits = FALSE)) {
    return(get(key, envir = cache, inherits = FALSE))
  }
  out <- NULL
  if (
    is.data.frame(tool_choices) &&
      all(c("list_name", "label", "name") %in% names(tool_choices))
  ) {
    lbl <- as.character(tool_choices$label)
    nm <- as.character(tool_choices$name)
    out <- list(
      list_name = as.character(tool_choices$list_name),
      label = lbl,
      name = nm,
      label_n = .norm_tok(lbl),
      name_n = .norm_tok(nm),
      label_l = .norm_loose(lbl),
      name_l = .norm_loose(nm)
    )
  }
  if (!is.null(cache)) {
    assign(key, out, envir = cache)
  }
  out
}

#' Every token a choice could be written as in the dataset
#'
#' The \code{list_name} recorded in \code{other_db} comes from whichever
#' version of the tool produced the original output, and that need not be the
#' list the current \code{tool_choices} calls by that name — a colleague's tool
#' can name the same list differently, or name a different list the same. So the
#' stated list is tried first, then the rest of \code{tool_choices} is searched
#' for the same text, so a mismatched \code{list_name} degrades to a slower
#' lookup rather than a wrong answer.
#'
#' @param text The choice as written in the other-responses file (usually the
#'   label, occasionally the code).
#' @param list_name The \code{list_name} recorded in \code{other_db}.
#' @param tool_choices The XLSForm choices sheet.
#' @return Character vector of candidate tokens, most trustworthy first: the
#'   text itself, then its counterpart within the stated list, then counterparts
#'   found in any other list.
#' @keywords internal
.choice_tokens <- function(text, list_name, tool_choices, tc_norm = NULL) {
  txt <- trimws(as.character(text))[1]
  if (is.na(txt) || !nzchar(txt)) {
    return(character(0))
  }
  tcn <- if (is.null(tc_norm)) .norm_tool_choices(tool_choices) else tc_norm
  if (is.null(tcn)) {
    return(txt)
  }

  txt_n <- .norm_tok(txt)
  txt_l <- .norm_loose(txt)
  gather <- function(mask) {
    if (!any(mask)) {
      return(character(0))
    }
    c(
      tcn$name[mask & tcn$label_n == txt_n],
      tcn$label[mask & tcn$name_n == txt_n],
      tcn$name[mask & tcn$label_l == txt_l],
      tcn$label[mask & tcn$name_l == txt_l]
    )
  }

  in_list <- if (is.null(list_name) || is.na(list_name)) {
    rep(FALSE, length(tcn$list_name))
  } else {
    !is.na(tcn$list_name) & tcn$list_name == list_name
  }
  # stated list first, then every other list (a list_name recorded by another
  # version of the tool may not exist here at all)
  out <- c(txt, gather(in_list), gather(!in_list))
  out <- out[!is.na(out) & nzchar(trimws(out))]
  unique(out)
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
.detect_dataset_sm_style <- function(
  ds,
  sm_separator,
  max_cols = 300L,
  rows = NULL,
  max_rows = 2000L
) {
  if (is.null(rows)) {
    rows <- seq_len(nrow(ds))
  }
  if (length(rows) > max_rows) {
    rows <- rows[seq_len(max_rows)]
  }
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
    vals <- as.character(ds[[col]][rows])
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

#' Detect whether a select_one column holds choice labels or choice codes
#'
#' A label export writes the choice text into the column, a coded export writes
#' the XLSForm \code{name}. Recoding an "other" response must write back
#' whichever the column already contains, so this compares the column's existing
#' values against \code{tool_choices} — first within the recorded
#' \code{list_name}, then across every list, since that name may come from a
#' different version of the tool.
#'
#' @return \code{"label"} or \code{"code"}.
#' @keywords internal
.detect_so_convention <- function(
  dataset,
  col,
  list_name = NULL,
  tool_choices = NULL,
  skip_label_row = TRUE,
  cache = NULL
) {
  key <- paste0("so:", col)
  if (!is.null(cache) && exists(key, envir = cache, inherits = FALSE)) {
    return(get(key, envir = cache, inherits = FALSE))
  }

  out <- "label" # a label export is the safe default: never invent codes
  if (
    col %in% names(dataset) &&
      is.data.frame(tool_choices) &&
      all(c("list_name", "label", "name") %in% names(tool_choices))
  ) {
    vals <- as.character(dataset[[col]][.data_rows(dataset, skip_label_row)])
    vals <- .norm_tok(vals[!is.na(vals) & nzchar(trimws(vals))])
    if (length(vals) > 0) {
      score <- function(tc) {
        c(
          lbl = sum(vals %in% .norm_tok(tc$label)),
          nm = sum(vals %in% .norm_tok(tc$name))
        )
      }
      sc <- score(tool_choices[
        !is.null(list_name) &
          !is.na(list_name) &
          !is.na(tool_choices$list_name) &
          tool_choices$list_name == list_name,
        ,
        drop = FALSE
      ])
      if (sum(sc) == 0) {
        sc <- score(tool_choices) # recorded list_name did not match: try all
      }
      if (sc[["nm"]] > sc[["lbl"]]) {
        out <- "code"
      }
    }
  }

  if (!is.null(cache)) {
    assign(key, out, envir = cache)
  }
  out
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

  rows <- .data_rows(dataset, skip_label_row)

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

  if (
    length(ch_lbl) == 0 &&
      is.data.frame(tool_choices) &&
      !is.null(list_name) &&
      !is.na(list_name)
  ) {
    warning(paste0(
      "list_name '",
      list_name,
      "' (recorded in other_db) is not in tool_choices — matching the choices ",
      "for '",
      parent_col,
      "' against the dataset's own sub-column headers instead. This usually ",
      "means other_db was built with a different version of the tool."
    ))
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
  # Gather the evidence over every sub-column before deciding, because a single
  # column can be misleading: a coded header like Q83/1 holding "1" looks like
  # the choice-text convention but is an ordinary binary export.
  binary_set <- c("0", "1", "true", "false")
  value_kind <- NA_character_
  saw_zero <- FALSE
  saw_one <- FALSE
  saw_nonbinary <- FALSE
  hit_suffix <- FALSE
  hit_label <- FALSE
  for (i in seq_along(sub_cols)) {
    vals <- as.character(dataset[[sub_cols[i]]][rows])
    vals <- vals[!is.na(vals) & nzchar(trimws(vals))]
    if (length(vals) == 0) next
    v <- .norm_tok(vals)
    if (any(v %in% c("0", "false"))) saw_zero <- TRUE
    if (any(v %in% c("1", "true"))) saw_one <- TRUE
    if (!all(v %in% binary_set)) saw_nonbinary <- TRUE
    # A suffix that is itself 0/1 proves nothing — its "1" is the binary marker.
    if (
      !(.norm_tok(suffixes[i]) %in% binary_set) &&
        any(v == .norm_tok(suffixes[i]))
    ) {
      hit_suffix <- TRUE
    }
    if (length(ch_lbl) > 0 && any(v %in% .norm_tok(ch_lbl))) hit_label <- TRUE
  }

  if (!saw_nonbinary && (saw_one || saw_zero)) {
    value_kind <- "binary" # nothing but 0/1 anywhere in the question
  } else if (hit_suffix) {
    value_kind <- "suffix" # cell holds its own column's choice text
  } else if (hit_label) {
    value_kind <- "label" # coded headers, but the cell holds the label
  } else if (saw_one) {
    value_kind <- "binary"
  }

  if (is.na(value_kind)) {
    # No filled sub-column for this question. Try the parent concat column: in a
    # label export it holds the choice text, in a binary export only 0/1.
    parent_vals <- if (parent_col %in% names(dataset)) {
      as.character(dataset[[parent_col]][rows])
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
      value_kind <- .detect_dataset_sm_style(dataset, sm_separator, rows = rows)
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
  conv_cache = NULL,
  uuid_index = NULL
) {
  rows <- list()
  uuid <- x$uuid
  ref_type <- x$ref_type
  gv <- function(col) {
    .get_val(dataset, uuid_column, uuid, col, skip_label_row, uuid_index)
  }
  tc_norm <- .norm_tool_choices(tool_choices, conv_cache)

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
    chosen <- trimws(x$existing_other)
    cands <- .choice_tokens(chosen, x$list_name, tool_choices, tc_norm)
    so_conv <- .detect_so_convention(
      dataset,
      x$ref_question,
      list_name = x$list_name,
      tool_choices = tool_choices,
      skip_label_row = skip_label_row,
      cache = conv_cache
    )

    # Write back in the convention the column already uses: the choice text in a
    # label export, the XLSForm name in a coded one. Previously the code was
    # written unconditionally, which put digits into label columns.
    new_value <- if (identical(so_conv, "code")) {
      cd <- .resolve_token_to_token(chosen, x$list_name, tool_choices, "name")
      if (identical(cd, chosen) && length(cands) > 1) cands[2] else cd
    } else {
      chosen
    }

    if (length(new_value) == 0 || is.na(new_value[1]) || !nzchar(new_value[1])) {
      warning(paste0(
        "Choice '",
        chosen,
        "' could not be resolved for '",
        x$ref_question,
        "' (recorded list_name '",
        x$list_name,
        "') for uuid '",
        uuid,
        "' — skipped."
      ))
      return(rows[[1]])
    }
    if (identical(so_conv, "code") && identical(new_value[1], chosen)) {
      warning(paste0(
        "'",
        x$ref_question,
        "' looks like a coded column but no code was found for '",
        chosen,
        "' (recorded list_name '",
        x$list_name,
        "') — wrote the text as given for uuid '",
        uuid,
        "'."
      ))
    }
    rows[[2]] <- data.frame(
      uuid = uuid,
      question = x$ref_question,
      action_taken = "recode",
      old_value = as.character(gv(x$ref_question)),
      new_value = as.character(new_value[1]),
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

    # The dataset's own sub-column suffixes are the authoritative vocabulary for
    # this question: they are what the parent concat is actually built from,
    # whatever tool_choices (or a mismatched list_name) may say.
    vocab <- unique(c(suffixes, .get_vocab(x$list_name, tool_choices)))

    # Which token to write for a choice: the matched sub-column's own suffix
    # wins, so the value always matches the export. Only when no sub-column
    # matches do we guess from tool_choices.
    token_for <- function(sub_col, cands) {
      if (!is.na(sub_col)) {
        return(.sm_suffixes(sub_col, x$ref_question, sm_separator))
      }
      hit <- cands[.norm_tok(cands) %in% .norm_tok(suffixes)]
      if (length(hit) > 0) {
        return(hit[1])
      }
      hit <- cands[.norm_loose(cands) %in% .norm_loose(vocab)]
      if (length(hit) > 0) {
        return(hit[1])
      }
      cands[1]
    }

    # ---- validate the chosen labels ----
    # A choice is usable if the dataset has a sub-column for it, even when
    # tool_choices does not recognise it under the recorded list_name.
    valid_labels <- c()
    label_cands <- list()
    label_subcol <- list()
    for (l in chosen_labels) {
      cands <- .choice_tokens(l, x$list_name, tool_choices, tc_norm)
      sc <- .find_sub_col(all_sub_cols, suffixes, cands)
      if (is.na(sc) && length(cands) <= 1L) {
        warning(paste0(
          "Choice '",
          l,
          "' matches no sub-column of '",
          x$ref_question,
          "' and is not in tool_choices (recorded list_name '",
          x$list_name,
          "') for uuid '",
          uuid,
          "' — skipped. Check the label matches the tool."
        ))
        next
      }
      valid_labels <- c(valid_labels, l)
      label_cands[[l]] <- cands
      label_subcol[[l]] <- sc
    }

    # ---- the "other" option ----
    other_cands <- .choice_tokens(
      x$option_other,
      x$list_name,
      tool_choices,
      tc_norm
    )
    sub_col_other <- .find_sub_col(all_sub_cols, suffixes, other_cands)
    token_to_remove <- token_for(sub_col_other, other_cands)

    # Remove the "other" token from the concat. Every candidate form is tried
    # because the concat may hold the label while other_db recorded the code (or
    # the reverse); removing a token that is not there is a no-op.
    for (tk in unique(c(token_to_remove, other_cands))) {
      new_concat <- .remove_token(new_concat, tk, vocab)
    }
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
      cands <- label_cands[[lbl]]
      sub_col <- label_subcol[[lbl]]
      token_to_add <- token_for(sub_col, cands)
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
#'
#' Choices are matched to the dataset's own column headers first, and only then
#' translated through \code{tool_choices}. The \code{list_name} recorded in
#' \code{other_db} comes from whichever version of the tool produced the
#' original output, so when it is missing from the current \code{tool_choices}
#' the choice text is looked up across the remaining lists (and matched
#' ignoring case, spacing and punctuation). A recoded choice is written in the
#' form the column itself uses, so a label export is never given choice codes.
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
