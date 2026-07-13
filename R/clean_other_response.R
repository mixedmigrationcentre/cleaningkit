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
#'     One or more of the \code{EXISTING other ...} columns is filled. For
#'     \code{select_one}: blanks the \code{_other} text column, sets the parent
#'     to the matched choice code. For \code{select_multiple}: blanks the
#'     \code{_other} text column, removes the \code{other} option from the
#'     parent concatenation, and adds the matched choice(s).}
#'   \item{\code{remove}}{The response is invalid (\code{INVALID other == "Yes"}).
#'     Blanks the \code{_other} text column and removes/blanks the parent
#'     question reference.}
#' }
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
    rename_starts("EXISTING other 1", "existing_other_1") |>
    rename_starts("EXISTING other 2", "existing_other_2") |>
    rename_starts("EXISTING other 3", "existing_other_3") |>
    rename_starts("INVALID", "invalid_other") |>
    rename_starts("FOLLOW", "fu_message")

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

  required_cols <- c(
    log_uuid_col,
    "question_name",
    "list_name",
    "response_en",
    "true_other",
    "existing_other_1",
    "existing_other_2",
    "existing_other_3",
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

  # 2) REMOVE
  if (nrow(or_remove) > 0) {
    remove_rows <- lapply(seq_len(nrow(or_remove)), function(i) {
      .build_remove_rows(
        or_remove[i, ],
        dataset,
        uuid_column,
        sm_separator,
        skip_label_row
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
        skip_label_row
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
  skip_label_row = TRUE
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
    old_concat <- gv(x$ref_question)
    new_concat <- remove_choice(old_concat, x$option_other)
    new_concat <- if (is.na(new_concat) || trimws(new_concat) == "") {
      NA_character_
    } else {
      trimws(new_concat)
    }

    if (is.na(new_concat)) {
      sub_cols <- .sm_sub_cols(dataset, x$ref_question, sm_separator)
      for (col in sub_cols) {
        rows[[length(rows) + 1]] <- data.frame(
          uuid = uuid,
          question = col,
          action_taken = "remove",
          old_value = as.character(gv(col)),
          new_value = NA_character_,
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
      sub_col <- paste0(x$ref_question, sm_separator, x$option_other)
      if (sub_col %in% names(dataset)) {
        rows[[length(rows) + 1]] <- data.frame(
          uuid = uuid,
          question = sub_col,
          action_taken = "remove",
          old_value = "1",
          new_value = "0",
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

#' Build log rows for a RECODE action
#' @keywords internal
.build_recode_rows <- function(
  x,
  dataset,
  tool_choices,
  uuid_column,
  sm_separator,
  skip_label_row = TRUE
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
    labels <- trimws(stringr::str_split(x$existing_other, ";")[[1]])
    labels <- labels[nzchar(labels)]
    codes <- vapply(
      labels,
      function(l) {
        cd <- get_name_from_label(x$list_name, l, tool_choices)
        if (length(cd) == 0 || is.na(cd[1])) {
          warning(paste0(
            "Label '",
            l,
            "' not found for list '",
            x$list_name,
            "' uuid '",
            uuid,
            "' — using label as-is."
          ))
          return(l)
        }
        as.character(cd[1])
      },
      character(1)
    )

    old_concat <- gv(x$ref_question)
    new_concat <- old_concat
    option_other <- x$option_other

    # remove the "other" binary sub-column and from the concatenation
    new_concat <- remove_choice(new_concat, option_other)
    sub_col_other <- paste0(x$ref_question, sm_separator, option_other)
    if (sub_col_other %in% names(dataset)) {
      rows[[length(rows) + 1]] <- data.frame(
        uuid = uuid,
        question = sub_col_other,
        action_taken = "recode",
        old_value = "1",
        new_value = "0",
        stringsAsFactors = FALSE
      )
    }

    # add each matched code
    for (code in codes) {
      cur_val <- gv(paste0(x$ref_question, sm_separator, code))
      if (!identical(cur_val, "1")) {
        sub_col <- paste0(x$ref_question, sm_separator, code)
        if (sub_col %in% names(dataset)) {
          rows[[length(rows) + 1]] <- data.frame(
            uuid = uuid,
            question = sub_col,
            action_taken = "recode",
            old_value = as.character(cur_val),
            new_value = "1",
            stringsAsFactors = FALSE
          )
        }
        new_concat <- add_choice(new_concat, code)
      }
    }

    new_concat <- trimws(new_concat)
    if (nzchar(new_concat) && new_concat != as.character(old_concat)) {
      rows[[length(rows) + 1]] <- data.frame(
        uuid = uuid,
        question = x$ref_question,
        action_taken = "recode",
        old_value = as.character(old_concat),
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
