#' Read and Prepare Filled Cleaning Log(s)
#'
#' Reads one or more filled cleaning log Excel files from a directory (or a
#' single file path), filters to valid uuids and known questions, deduplicates
#' rows where the same \code{uuid + question} was reviewed more than once, and
#' returns a single clean dataframe ready for \code{evaluate_cleaning_log()}.
#'
#' @details
#' \strong{File discovery:} when \code{path} is a directory, all files matching
#' \code{file_pattern} are read and stacked. When \code{path} is a single
#' \code{.xlsx} file it is read directly. An error is raised if no matching
#' files are found.
#'
#' \strong{Sheet selection:} \code{sheet} accepts either a sheet name or an
#' integer index. The default \code{2} matches the output of
#' \code{create_cleaning_log()} where sheet 1 is the dataset and sheet 2 is
#' the cleaning log.
#'
#' \strong{Filtering:} rows whose \code{uuid} is not in the raw dataset and rows
#' whose \code{question} is not a column in the raw dataset are silently dropped
#' (with a summary message). Rows with \code{action == "no_action"} have their
#' \code{New value} set to the \code{Old value} (no change should be applied).
#'
#' \strong{Deduplication:} when the same \code{uuid + question} pair appears in
#' more than one row (e.g. the same cell was reviewed in two separate log files
#' or two reviewers completed the same row), the most decisive action is kept
#' using the following priority:
#' \enumerate{
#'   \item \code{recoded} — a specific new value was chosen
#'   \item \code{addition} — a blank was filled in
#'   \item \code{other} — a change was made that doesn't fit a standard category
#'   \item \code{delete_data_point} — the cell was blanked
#'   \item \code{no_action} — reviewer confirmed no change needed
#'   \item \code{NA} or anything else — lowest priority
#' }
#' \code{discard} rows are handled separately: only one \code{discard} row is
#' kept per uuid.
#'
#' \strong{Duplicate check:} after deduplication, if any \code{uuid + question}
#' pair still appears more than once the function stops with a clear error
#' listing the offending pairs, because applying an ambiguous log would corrupt
#' the dataset.
#'
#' @param path Either a path to a directory containing one or more cleaning log
#'   Excel files, or a direct path to a single \code{.xlsx} file.
#' @param raw_dataset The original raw dataset. Used to filter rows to valid
#'   uuids and known question columns.
#' @param raw_uuid_column Name of the uuid column in \code{raw_dataset}. Default
#'   \code{"_uuid"}.
#' @param uuid_col Name of the uuid column in the cleaning log. Default
#'   \code{"Survey UUID"}.
#' @param action_col Name of the action column in the cleaning log. Default
#'   \code{"Action taken"}.
#' @param question_col Name of the question column in the cleaning log. Default
#'   \code{"Question number"}.
#' @param old_value_col Name of the old-value column. Default \code{"Old value"}.
#' @param new_value_col Name of the new-value column. Default \code{"New value"}.
#' @param sheet Sheet to read from each Excel file. Accepts a name or integer.
#'   Default \code{2}.
#' @param file_pattern Regex pattern used to identify cleaning log files when
#'   \code{path} is a directory. Default \code{"_follow-ups_edited\\\\.xlsx$"}.
#' @param extra_questions Optional character vector of additional question values
#'   to allow through the question filter (e.g. computed columns that are not
#'   in the raw dataset but are valid targets). Default \code{NULL}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of
#'   \code{raw_dataset} is removed before extracting valid uuids.
#' @param verbose Logical. If \code{TRUE} (the default), messages are printed
#'   summarising files read, rows filtered, and deduplication results.
#'
#' @return A single deduplicated dataframe containing all cleaning log rows,
#'   ready to pass to \code{evaluate_cleaning_log()}.
#' @export
read_cleaning_log <- function(
  path,
  raw_dataset,
  raw_uuid_column = "_uuid",
  uuid_col = "Survey UUID",
  action_col = "Action taken",
  question_col = "Question number",
  old_value_col = "Old value",
  new_value_col = "New value",
  sheet = 2,
  file_pattern = "_follow-ups_edited\\.xlsx$",
  extra_questions = NULL,
  skip_label_row = TRUE,
  verbose = TRUE
) {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    stop(
      "The 'readxl' package is required. Install it with: install.packages('readxl')"
    )
  }
  if (!is.data.frame(raw_dataset)) {
    stop("`raw_dataset` must be a dataframe.")
  }
  if (!(raw_uuid_column %in% names(raw_dataset))) {
    stop(paste0("Cannot find '", raw_uuid_column, "' in `raw_dataset`."))
  }

  # ---- resolve file paths ----
  if (file.exists(path) && !dir.exists(path)) {
    # single file passed directly
    files <- path
  } else if (dir.exists(path)) {
    files <- list.files(
      path = path,
      pattern = file_pattern,
      recursive = TRUE,
      full.names = TRUE
    )
    if (length(files) == 0) {
      stop(paste0(
        "No files matching pattern '",
        file_pattern,
        "' found in directory: ",
        path
      ))
    }
  } else {
    stop(paste0("'path' does not exist: ", path))
  }

  if (verbose) {
    message("read_cleaning_log: reading ", length(files), " file(s):")
    for (f in files) {
      message("  ", f)
    }
  }

  # ---- read all files ----
  log_list <- lapply(files, function(f) {
    tryCatch(
      readxl::read_excel(f, col_types = "text", sheet = sheet),
      error = function(e) {
        warning(paste0("Could not read '", f, "': ", conditionMessage(e)))
        NULL
      }
    )
  })
  failed <- vapply(log_list, is.null, logical(1))
  if (any(failed)) {
    warning(sum(failed), " file(s) could not be read and were skipped.")
  }
  log_list <- log_list[!failed]
  if (length(log_list) == 0) {
    stop("No cleaning log files could be read.")
  }

  combined <- do.call(rbind, log_list)

  # guard: required columns must be present
  required <- c(
    uuid_col,
    action_col,
    question_col,
    old_value_col,
    new_value_col
  )
  missing_cols <- setdiff(required, names(combined))
  if (length(missing_cols) > 0) {
    stop(paste0(
      "The following required column(s) are missing from the cleaning log(s): ",
      paste(missing_cols, collapse = ", ")
    ))
  }

  n_raw <- nrow(combined)
  if (verbose) {
    message("read_cleaning_log: ", n_raw, " total rows read across all files.")
  }

  # ---- normalise action column ----
  combined[[action_col]] <- trimws(tolower(as.character(combined[[
    action_col
  ]])))

  # ---- build reference sets from raw_dataset ----
  raw_df <- raw_dataset
  if (skip_label_row && nrow(raw_df) > 0) {
    raw_df <- raw_df[-1, , drop = FALSE]
  }
  valid_uuids <- trimws(as.character(raw_df[[raw_uuid_column]]))
  valid_uuids <- valid_uuids[!is.na(valid_uuids) & nzchar(valid_uuids)]
  valid_questions <- c(names(raw_df), extra_questions)

  # ---- no_action: copy old_value -> new_value (no change should be applied) ----
  is_no_action <- !is.na(combined[[action_col]]) &
    combined[[action_col]] == "no_action"
  combined[[new_value_col]][is_no_action] <- combined[[old_value_col]][
    is_no_action
  ]

  # ---- filter to valid uuids ----
  log_uuids <- trimws(as.character(combined[[uuid_col]]))
  uuid_valid <- log_uuids %in% valid_uuids
  n_uuid_dropped <- sum(!uuid_valid)
  combined <- combined[uuid_valid, , drop = FALSE]
  if (verbose && n_uuid_dropped > 0) {
    message(
      "read_cleaning_log: dropped ",
      n_uuid_dropped,
      " row(s) whose uuid was not found in the raw dataset."
    )
  }

  # ---- filter to valid questions ----
  # always keep: discard rows (question is not a column), and sentinel values
  log_questions <- trimws(as.character(combined[[question_col]]))
  is_discard <- !is.na(combined[[action_col]]) &
    combined[[action_col]] == "discard"
  is_sentinel <- log_questions %in% c("all_columns", "all")
  q_valid <- log_questions %in% valid_questions | is_discard | is_sentinel
  n_q_dropped <- sum(!q_valid)
  combined <- combined[q_valid, , drop = FALSE]
  if (verbose && n_q_dropped > 0) {
    message(
      "read_cleaning_log: dropped ",
      n_q_dropped,
      " row(s) whose question was not found in the raw dataset."
    )
  }

  if (nrow(combined) == 0) {
    warning("No rows remain after filtering. Returning an empty dataframe.")
    return(combined)
  }

  # ---- deduplication ----
  #
  # The same uuid + question + issue triplet can appear across multiple log
  # files when two files cover overlapping checks. We keep exactly one row per
  # triplet:
  #
  #   Rule A — all duplicates share the same action: keep the first occurrence.
  #   Rule B — mixed actions: keep the most decisive action (lowest priority
  #             number); no_action / NA are dropped when a better action exists.
  #
  # Priority: recoded=1, addition=2, other=3, delete_data_point=4, no_action=5,
  #           unknown/NA=6.
  #
  # Key = uuid + question + issue  (NOT just uuid + question), because the same
  # question can legitimately appear under two different issues (flagged by two
  # different checks), and BOTH flags must survive into the cleaning step.
  #
  # discard rows use a separate rule: keep one per uuid only.

  action_priority <- c(
    "recoded" = 1L,
    "addition" = 2L,
    "other" = 3L,
    "delete_data_point" = 4L,
    "no_action" = 5L
  )
  get_priority <- function(a) {
    a <- trimws(tolower(as.character(a)))
    if (is.na(a) || !a %in% names(action_priority)) {
      6L
    } else {
      action_priority[[a]]
    }
  }

  # -- discard rows: keep one per uuid --
  discard_mask <- !is.na(combined[[action_col]]) &
    combined[[action_col]] == "discard"
  discard_rows <- combined[discard_mask, , drop = FALSE]
  other_rows <- combined[!discard_mask, , drop = FALSE]

  discard_deduped <- if (nrow(discard_rows) > 0) {
    discard_rows[
      !duplicated(trimws(as.character(discard_rows[[uuid_col]]))),
      ,
      drop = FALSE
    ]
  } else {
    discard_rows
  }
  n_discard_dropped <- nrow(discard_rows) - nrow(discard_deduped)

  # -- non-discard rows: dedup by uuid + question + issue --
  if (nrow(other_rows) > 0) {
    issue_vals <- if ("issue" %in% names(other_rows)) {
      trimws(as.character(other_rows[["issue"]]))
    } else {
      rep("", nrow(other_rows))
    }

    other_rows[[".priority"]] <- vapply(
      other_rows[[action_col]],
      get_priority,
      integer(1)
    )
    other_rows[[".key"]] <- paste(
      trimws(as.character(other_rows[[uuid_col]])),
      trimws(as.character(other_rows[[question_col]])),
      issue_vals,
      sep = "__|__"
    )

    # Sort by key then priority: within each group the best action floats to
    # the top (Rule B); if all actions are the same the first occurrence stays
    # (Rule A). Either way, slice the first row per group.
    other_rows <- other_rows[
      order(other_rows[[".key"]], other_rows[[".priority"]]),
    ]
    n_other_before <- nrow(other_rows)
    other_rows <- other_rows[
      !duplicated(other_rows[[".key"]]),
      ,
      drop = FALSE
    ]
    n_other_dropped <- n_other_before - nrow(other_rows)

    other_rows[[".priority"]] <- NULL
    other_rows[[".key"]] <- NULL
  } else {
    n_other_dropped <- 0L
  }

  n_deduped <- n_discard_dropped + n_other_dropped
  if (verbose && n_deduped > 0) {
    message(
      "read_cleaning_log: deduplicated ",
      n_deduped,
      " row(s) (",
      n_discard_dropped,
      " discard, ",
      n_other_dropped,
      " cell-level)."
    )
  }

  result <- rbind(discard_deduped, other_rows)
  rownames(result) <- NULL

  # ---- final duplicate check ----
  # After deduplication, uuid + question + issue must be unique. If not, the
  # log is ambiguous and applying it would corrupt the dataset.
  issue_res <- if ("issue" %in% names(result)) {
    trimws(as.character(result[["issue"]]))
  } else {
    rep("", nrow(result))
  }
  dup_key_final <- paste(
    trimws(as.character(result[[uuid_col]])),
    trimws(as.character(result[[question_col]])),
    issue_res,
    sep = "__|__"
  )
  is_res_discard <- !is.na(result[[action_col]]) &
    result[[action_col]] == "discard"
  dup_check_mask <- !is_res_discard &
    (duplicated(dup_key_final) | duplicated(dup_key_final, fromLast = TRUE))

  if (any(dup_check_mask)) {
    dups <- unique(dup_key_final[dup_check_mask])
    stop(paste0(
      "Duplicate uuid + question + issue combinations remain after deduplication ",
      "(",
      length(dups),
      " triplet(s)). Review and resolve before proceeding:\n",
      paste0("  ", gsub("__|__", " | ", dups), collapse = "\n")
    ))
  }

  if (verbose) {
    message(
      "read_cleaning_log: returning ",
      nrow(result),
      " rows (",
      sum(is_res_discard),
      " discard, ",
      sum(!is_res_discard),
      " cell-level changes)."
    )
  }

  result
}


#' Evaluate a Filled Cleaning Log
#'
#' Validates a completed cleaning log before it is applied to the raw dataset.
#' Catches missing values, invalid action types, logical inconsistencies, and
#' references to uuids or questions that do not exist in the raw data, so that
#' errors are surfaced at review time rather than silently corrupting the clean
#' dataset.
#'
#' @details
#' The five valid action types and how they are interpreted:
#' \describe{
#'   \item{\code{recoded}}{A data point was changed (maps to \code{change_response}).
#'     \strong{New value} must be filled and must differ from \strong{Old value}.}
#'   \item{\code{delete_data_point}}{A data point was set to blank / NA (maps to
#'     \code{blank_response}). \strong{New value} must be empty.}
#'   \item{\code{addition}}{A previously empty cell was filled in (maps to
#'     \code{change_response}). \strong{New value} must be filled.}
#'   \item{\code{discard}}{The entire survey is removed (maps to
#'     \code{remove_survey}). \strong{New value} is ignored. The uuid must exist
#'     in the raw dataset.}
#'   \item{\code{other}}{Any other change (maps to \code{change_response}).
#'     \strong{New value} must be filled.}
#'   \item{\code{no_action}}{No change is applied. Rows are skipped entirely
#'     during cleaning.}
#' }
#'
#' The function returns a list with two elements: \code{cleaning_log} (the
#' original log, possibly with an added \code{evaluation_issue} column when
#' \code{flag_issues_inline = TRUE}) and \code{evaluation_log} (a dataframe
#' summarising every issue found, one row per problem, with the row number and
#' a description).
#'
#' @param cleaning_log A dataframe containing the filled cleaning log as produced
#'   by \code{create_cleaning_log()} and completed by the reviewer.
#' @param raw_dataset The original raw dataset. Used to verify that uuids and
#'   question names referenced in the log actually exist.
#' @param uuid_col Name of the uuid column in \code{cleaning_log}. Default
#'   \code{"Survey UUID"} (the column name produced by \code{create_cleaning_log()}).
#' @param action_col Name of the action-type column in \code{cleaning_log}.
#'   Default \code{"Action taken"}.
#' @param question_col Name of the question column in \code{cleaning_log}.
#'   Default \code{"Question number"}.
#' @param old_value_col Name of the old-value column in \code{cleaning_log}.
#'   Default \code{"Old value"}.
#' @param new_value_col Name of the new-value column in \code{cleaning_log}.
#'   Default \code{"New value"}.
#' @param raw_uuid_column Name of the uuid column in \code{raw_dataset}.
#'   Default \code{"_uuid"}.
#' @param valid_actions Character vector of accepted action-type values.
#'   Default matches the five types defined in the \code{create_cleaning_log()}
#'   readme sheet.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row
#'   of \code{raw_dataset} is removed before checking uuid existence. ONA exports
#'   include a label/description row immediately after the header.
#' @param flag_issues_inline Logical. If \code{TRUE} (the default), an
#'   \code{evaluation_issue} column is added to the returned cleaning log so
#'   issues are visible alongside the rows that caused them.
#'
#' @return A list with:
#'   \item{cleaning_log}{The original cleaning log, with an optional
#'     \code{evaluation_issue} column when \code{flag_issues_inline = TRUE}.}
#'   \item{evaluation_log}{A dataframe with columns \code{row}, \code{uuid},
#'     \code{question}, \code{action}, \code{issue_type}, and \code{issue}
#'     describing every problem found. Zero rows means the log is clean.}
#' @export
evaluate_cleaning_log <- function(
  cleaning_log,
  raw_dataset,
  uuid_col = "Survey UUID",
  action_col = "Action taken",
  question_col = "Question number",
  old_value_col = "Old value",
  new_value_col = "New value",
  raw_uuid_column = "_uuid",
  valid_actions = c(
    "recoded",
    "delete_data_point",
    "addition",
    "discard",
    "other",
    "no_action"
  ),
  skip_label_row = TRUE,
  flag_issues_inline = TRUE
) {
  # ---- basic structure checks ----
  if (!is.data.frame(cleaning_log) || nrow(cleaning_log) == 0) {
    stop("`cleaning_log` must be a non-empty dataframe.")
  }
  if (!is.data.frame(raw_dataset)) {
    stop("`raw_dataset` must be a dataframe.")
  }

  required_cl_cols <- c(
    uuid_col,
    action_col,
    question_col,
    old_value_col,
    new_value_col
  )
  missing_cl_cols <- setdiff(required_cl_cols, names(cleaning_log))
  if (length(missing_cl_cols) > 0) {
    stop(paste0(
      "The following required column(s) are missing from `cleaning_log`: ",
      paste(missing_cl_cols, collapse = ", ")
    ))
  }
  if (!(raw_uuid_column %in% names(raw_dataset))) {
    stop(paste0("Cannot find '", raw_uuid_column, "' in `raw_dataset`."))
  }

  # ---- prepare raw dataset ----
  raw_df <- raw_dataset
  if (skip_label_row && nrow(raw_df) > 0) {
    raw_df <- raw_df[-1, , drop = FALSE]
  }
  raw_uuids <- trimws(as.character(raw_df[[raw_uuid_column]]))
  raw_cols <- names(raw_df)

  # ---- helpers ----
  is_empty <- function(x) is.na(x) | trimws(as.character(x)) %in% c("", "NA")

  cl <- cleaning_log
  cl[[uuid_col]] <- trimws(as.character(cl[[uuid_col]]))
  cl[[action_col]] <- trimws(tolower(as.character(cl[[action_col]])))
  cl[[question_col]] <- trimws(as.character(cl[[question_col]]))
  cl[[old_value_col]] <- as.character(cl[[old_value_col]])
  cl[[new_value_col]] <- as.character(cl[[new_value_col]])

  issues <- list()

  add_issue <- function(rows, issue_type, issue_msg) {
    if (length(rows) == 0) {
      return()
    }
    issues[[length(issues) + 1]] <<- data.frame(
      row = rows,
      uuid = cl[[uuid_col]][rows],
      question = cl[[question_col]][rows],
      action = cl[[action_col]][rows],
      issue_type = issue_type,
      issue = issue_msg,
      stringsAsFactors = FALSE
    )
  }

  # ---- CHECK 1: Action taken not filled ----
  blank_action <- which(is_empty(cl[[action_col]]))
  add_issue(
    blank_action,
    "missing_action",
    paste0(
      "'",
      action_col,
      "' is empty; the reviewer must select an action type"
    )
  )

  # ---- CHECK 2: Invalid action type ----
  valid_lc <- tolower(valid_actions)
  filled_action <- which(!is_empty(cl[[action_col]]))
  invalid_action <- filled_action[
    !(cl[[action_col]][filled_action] %in% valid_lc)
  ]
  add_issue(
    invalid_action,
    "invalid_action",
    paste0(
      "'",
      cl[[action_col]][invalid_action],
      "' is not a valid action type; valid values: ",
      paste(valid_actions, collapse = ", ")
    )
  )

  # ---- work only on rows with a valid, non-empty action from here on ----
  valid_rows <- which(cl[[action_col]] %in% valid_lc)

  # action-type sub-groups (exclude no_action rows from most checks)
  needs_new_value <- valid_rows[
    cl[[action_col]][valid_rows] %in% c("recoded", "addition", "other")
  ]
  must_be_blank <- valid_rows[
    cl[[action_col]][valid_rows] == "delete_data_point"
  ]
  discard_rows <- valid_rows[cl[[action_col]][valid_rows] == "discard"]
  no_action_rows <- valid_rows[cl[[action_col]][valid_rows] == "no_action"]
  change_rows <- valid_rows[
    cl[[action_col]][valid_rows] %in%
      c("recoded", "addition", "other", "delete_data_point")
  ]

  # ---- CHECK 3: recoded / addition / other missing New value ----
  missing_new <- needs_new_value[is_empty(cl[[new_value_col]][needs_new_value])]
  add_issue(
    missing_new,
    "missing_new_value",
    paste0(
      "Action '",
      cl[[action_col]][missing_new],
      "' requires a non-empty 'New value'"
    )
  )

  # ---- CHECK 4: delete_data_point must have empty New value ----
  nonempty_blank <- must_be_blank[!is_empty(cl[[new_value_col]][must_be_blank])]
  add_issue(
    nonempty_blank,
    "new_value_should_be_empty",
    paste0(
      "Action 'delete_data_point' blanks the cell; ",
      "'New value' should be empty but contains '",
      cl[[new_value_col]][nonempty_blank],
      "'"
    )
  )

  # ---- CHECK 5: New value same as Old value (no-op change) ----
  has_new <- needs_new_value[!is_empty(cl[[new_value_col]][needs_new_value])]
  same_val <- has_new[
    trimws(cl[[new_value_col]][has_new]) == trimws(cl[[old_value_col]][has_new])
  ]
  add_issue(
    same_val,
    "new_equals_old",
    paste0(
      "'New value' ('",
      cl[[new_value_col]][same_val],
      "') is identical to 'Old value' — no change will be made"
    )
  )

  # ---- CHECK 6: uuid not found in raw dataset (non-discard rows) ----
  non_discard_valid <- valid_rows[cl[[action_col]][valid_rows] != "discard"]
  uuid_missing <- non_discard_valid[
    !(cl[[uuid_col]][non_discard_valid] %in% raw_uuids)
  ]
  add_issue(
    uuid_missing,
    "uuid_not_in_raw",
    paste0(
      "uuid '",
      cl[[uuid_col]][uuid_missing],
      "' does not exist in the raw dataset"
    )
  )

  # ---- CHECK 7: discard uuid not found in raw dataset ----
  discard_missing_uuid <- discard_rows[
    !(cl[[uuid_col]][discard_rows] %in% raw_uuids)
  ]
  add_issue(
    discard_missing_uuid,
    "discard_uuid_not_in_raw",
    paste0(
      "uuid '",
      cl[[uuid_col]][discard_missing_uuid],
      "' marked for discard but does not exist in the raw dataset"
    )
  )

  # ---- CHECK 8: question not found in raw dataset ----
  # skip discard rows (question is not meaningful there) and uuid-level checks
  q_check_rows <- change_rows[
    cl[[uuid_col]][change_rows] %in% raw_uuids
  ]
  # also skip rows where question is "all_columns" (completeness checks)
  q_check_rows <- q_check_rows[
    !(cl[[question_col]][q_check_rows] %in% c("all_columns", "all"))
  ]
  q_not_found <- q_check_rows[
    !(cl[[question_col]][q_check_rows] %in% raw_cols)
  ]
  add_issue(
    q_not_found,
    "question_not_in_raw",
    paste0(
      "Question '",
      cl[[question_col]][q_not_found],
      "' does not exist as a column in the raw dataset"
    )
  )

  # ---- CHECK 9: duplicate uuid + question + issue combinations ----
  # The same cell cleaned twice under the same issue is ambiguous. However,
  # the same uuid + question can legitimately appear under two different issues
  # (e.g. Q13 flagged by both check_country_02 and check_country_04); those
  # should not be flagged. Group by uuid + question + issue, matching the
  # deduplication key used in read_cleaning_log().
  issue_vals_cl <- if ("issue" %in% names(cl)) {
    trimws(as.character(cl[["issue"]]))
  } else {
    rep("", nrow(cl))
  }
  dupe_key <- paste(
    cl[[uuid_col]],
    cl[[question_col]],
    issue_vals_cl,
    sep = "__|__"
  )
  dupe_rows <- which(
    duplicated(dupe_key) | duplicated(dupe_key, fromLast = TRUE)
  )
  dupe_rows <- intersect(
    dupe_rows,
    valid_rows[
      cl[[action_col]][valid_rows] != "no_action"
    ]
  )
  add_issue(
    dupe_rows,
    "duplicate_uuid_question",
    paste0(
      "Combination of uuid '",
      cl[[uuid_col]][dupe_rows],
      "', question '",
      cl[[question_col]][dupe_rows],
      "', and issue '",
      issue_vals_cl[dupe_rows],
      "' appears more than once \u2014 the same cell+issue is cleaned twice; ",
      "resolve to a single row"
    )
  )

  # ---- CHECK 10: no_action rows with a filled New value ----
  # Exclude rows where New value == Old value: read_cleaning_log() intentionally
  # copies Old value -> New value for no_action rows so the apply step has a
  # value to write. That is not a reviewer mistake.
  no_action_with_val <- no_action_rows[
    !is_empty(cl[[new_value_col]][no_action_rows]) &
      trimws(cl[[new_value_col]][no_action_rows]) !=
        trimws(cl[[old_value_col]][no_action_rows])
  ]
  add_issue(
    no_action_with_val,
    "no_action_has_new_value",
    paste0(
      "Action is 'no_action' but 'New value' ('",
      cl[[new_value_col]][no_action_with_val],
      "') differs from 'Old value' ('",
      cl[[old_value_col]][no_action_with_val],
      "') — this value will be ignored during cleaning"
    )
  )

  # ---- assemble evaluation log ----
  eval_log <- if (length(issues) == 0) {
    data.frame(
      row = integer(0),
      uuid = character(0),
      question = character(0),
      action = character(0),
      issue_type = character(0),
      issue = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, issues)
    out <- out[order(out$row), ]
    rownames(out) <- NULL
    out
  }

  # ---- optionally annotate the cleaning log inline ----
  if (flag_issues_inline) {
    cleaning_log[["evaluation_issue"]] <- NA_character_
    if (nrow(eval_log) > 0) {
      for (r in unique(eval_log$row)) {
        msgs <- eval_log$issue[eval_log$row == r]
        cleaning_log[["evaluation_issue"]][r] <- paste(msgs, collapse = " | ")
      }
    }
  }

  n_issues <- nrow(eval_log)
  n_rows_affected <- length(unique(eval_log$row))
  if (n_issues == 0) {
    message(
      "evaluate_cleaning_log: no issues found. The cleaning log is ready to apply."
    )
  } else {
    message(paste0(
      "evaluate_cleaning_log: ",
      n_issues,
      " issue(s) found across ",
      n_rows_affected,
      " row(s). Review the $evaluation_log before applying the cleaning log."
    ))
  }

  list(
    cleaning_log = cleaning_log,
    evaluation_log = eval_log
  )
}
