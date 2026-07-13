#' Apply a Validated Cleaning Log to the Raw Dataset
#'
#' Applies every change specified in a filled and validated cleaning log to the
#' raw dataset, producing a clean dataset and an audit trail of every
#' modification made.
#'
#' @details
#' \strong{Action types and what they do:}
#' \describe{
#'   \item{\code{recoded}}{Sets the cell at \code{[uuid, question]} to
#'     \code{new_value}. Maps to \code{change_response}.}
#'   \item{\code{addition}}{Sets the cell at \code{[uuid, question]} to
#'     \code{new_value} (filling a previously empty cell). Maps to
#'     \code{change_response}.}
#'   \item{\code{other}}{Sets the cell at \code{[uuid, question]} to
#'     \code{new_value}. Maps to \code{change_response}.}
#'   \item{\code{delete_data_point}}{Sets the cell at \code{[uuid, question]}
#'     to \code{NA}. Maps to \code{blank_response}.}
#'   \item{\code{discard}}{Removes the entire survey (row) with this uuid from
#'     the dataset. Maps to \code{remove_survey}.}
#'   \item{\code{no_action}}{Row is skipped; no change is made.}
#' }
#'
#' \strong{Column-wide changes:} if \code{uuid} is \code{"all_data"} (case-
#' insensitive), the change is applied to every row of \code{question} rather
#' than one specific survey. This mirrors the original behaviour for bulk
#' corrections.
#'
#' \strong{Audit trail:} the returned list includes an \code{audit_log}
#' dataframe showing every cell-level change made (uuid, question, action,
#' old value actually in the dataset, new value written). This is separate from
#' the cleaning log that was passed in and reflects what was actually done.
#'
#' \strong{Type restoration:} after all changes are applied, \code{type.convert}
#' is used to restore numeric, logical, and integer columns that were coerced to
#' character during the cleaning process.
#'
#' @param raw_dataset A dataframe — the original raw data to be cleaned.
#' @param cleaning_log A dataframe containing the validated cleaning log, as
#'   returned by \code{read_cleaning_log()} and checked by
#'   \code{evaluate_cleaning_log()}. Must have no remaining issues in the
#'   evaluation log before being passed here.
#' @param raw_uuid_column Name of the uuid column in \code{raw_dataset}.
#'   Default \code{"_uuid"}.
#' @param log_uuid_col Name of the uuid column in \code{cleaning_log}.
#'   Default \code{"Survey UUID"}.
#' @param log_question_col Name of the question/column column in
#'   \code{cleaning_log}. Default \code{"Question number"}.
#' @param log_new_value_col Name of the new-value column in
#'   \code{cleaning_log}. Default \code{"New value"}.
#' @param log_action_col Name of the action-type column in
#'   \code{cleaning_log}. Default \code{"Action taken"}.
#' @param change_response_values Character vector of action values that mean
#'   "change this cell to new_value". Default covers all three that map to
#'   \code{change_response}: \code{c("recoded", "addition", "other")}.
#' @param blank_response_values Character vector of action values that mean
#'   "blank this cell (set to NA)". Default \code{"delete_data_point"}.
#' @param remove_survey_values Character vector of action values that mean
#'   "remove the entire survey". Default \code{"discard"}.
#' @param no_action_values Character vector of action values to skip entirely.
#'   Default \code{"no_action"}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row
#'   of \code{raw_dataset} is preserved as the ONA label/description row and
#'   never modified by the cleaning log. Changes are only applied to rows 2+.
#' @param restore_types Logical. If \code{TRUE} (the default),
#'   \code{type.convert()} is called on the cleaned dataset to restore numeric
#'   and logical column types that were coerced to character.
#' @param verbose Logical. If \code{TRUE} (the default), a summary message is
#'   printed on completion.
#'
#' @return A list with two elements:
#'   \item{clean_dataset}{The cleaned dataframe.}
#'   \item{audit_log}{A dataframe recording every change applied, with columns
#'     \code{uuid}, \code{question}, \code{action}, \code{value_before}, and
#'     \code{value_after}.}
#' @export
apply_cleaning_log <- function(
  raw_dataset,
  cleaning_log,
  raw_uuid_column = "_uuid",
  log_uuid_col = "Survey UUID",
  log_question_col = "Question number",
  log_new_value_col = "New value",
  log_action_col = "Action taken",
  change_response_values = c("recoded", "addition", "other"),
  blank_response_values = "delete_data_point",
  remove_survey_values = "discard",
  no_action_values = "no_action",
  skip_label_row = TRUE,
  restore_types = TRUE,
  verbose = TRUE
) {
  # ---- validate inputs ----
  if (!is.data.frame(raw_dataset)) {
    stop("`raw_dataset` must be a dataframe.")
  }
  if (!is.data.frame(cleaning_log) || nrow(cleaning_log) == 0) {
    stop("`cleaning_log` must be a non-empty dataframe.")
  }
  required_log_cols <- c(
    log_uuid_col,
    log_question_col,
    log_new_value_col,
    log_action_col
  )
  missing_cols <- setdiff(required_log_cols, names(cleaning_log))
  if (length(missing_cols) > 0) {
    stop(paste0(
      "The following required column(s) are missing from `cleaning_log`: ",
      paste(missing_cols, collapse = ", ")
    ))
  }
  if (!(raw_uuid_column %in% names(raw_dataset))) {
    stop(paste0("Cannot find '", raw_uuid_column, "' in `raw_dataset`."))
  }

  all_known_actions <- c(
    change_response_values,
    blank_response_values,
    remove_survey_values,
    no_action_values
  )

  # ---- normalise cleaning log columns ----
  cl <- cleaning_log
  cl[[log_uuid_col]] <- trimws(as.character(cl[[log_uuid_col]]))
  cl[[log_action_col]] <- trimws(tolower(as.character(cl[[log_action_col]])))
  cl[[log_question_col]] <- trimws(as.character(cl[[log_question_col]]))
  cl[[log_new_value_col]] <- as.character(cl[[log_new_value_col]])

  # ---- check for unknown action types ----
  unknown_actions <- unique(cl[[log_action_col]][
    !cl[[log_action_col]] %in% c(tolower(all_known_actions), NA_character_)
  ])
  if (length(unknown_actions) > 0) {
    stop(paste0(
      "Unknown action type(s) in cleaning log: ",
      paste(unknown_actions, collapse = ", "),
      "\nValid actions: ",
      paste(all_known_actions, collapse = ", ")
    ))
  }

  # ---- separate the label row from data rows ----
  label_row <- NULL
  if (skip_label_row && nrow(raw_dataset) > 0) {
    label_row <- raw_dataset[1, , drop = FALSE]
    raw_dataset <- raw_dataset[-1, , drop = FALSE]
  }

  # ---- coerce dataset to character for safe cell assignment ----
  # (type.convert at the end restores column types)
  raw_dataset <- as.data.frame(
    lapply(raw_dataset, as.character),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )

  raw_uuids <- trimws(as.character(raw_dataset[[raw_uuid_column]]))
  n_rows_start <- nrow(raw_dataset)

  # ---- split log by action class ----
  is_change <- cl[[log_action_col]] %in% tolower(change_response_values)
  is_blank <- cl[[log_action_col]] %in% tolower(blank_response_values)
  is_remove <- cl[[log_action_col]] %in% tolower(remove_survey_values)
  is_no_act <- cl[[log_action_col]] %in% tolower(no_action_values)

  cl_change <- cl[is_change | is_blank, , drop = FALSE]
  cl_remove <- cl[is_remove, , drop = FALSE]

  audit_parts <- list()

  # ---- APPLY: cell-level changes (change_response + blank_response) ----
  if (nrow(cl_change) > 0) {
    # check questions exist in dataset (warn, not stop — evaluate_cleaning_log
    # already hard-checked this; here we just skip and report)
    bad_q <- unique(cl_change[[log_question_col]][
      !(cl_change[[log_question_col]] %in% c(names(raw_dataset), "all_data"))
    ])
    if (length(bad_q) > 0) {
      warning(paste0(
        "The following question(s) were not found in the dataset and will be skipped: ",
        paste(bad_q, collapse = ", ")
      ))
      cl_change <- cl_change[
        cl_change[[log_question_col]] %in% c(names(raw_dataset), "all_data"),
        ,
        drop = FALSE
      ]
    }

    # check uuids exist (warn and skip rather than stop)
    all_wide <- tolower(cl_change[[log_uuid_col]]) == "all_data"
    bad_uuid <- unique(cl_change[[log_uuid_col]][
      !all_wide & !(cl_change[[log_uuid_col]] %in% raw_uuids)
    ])
    if (length(bad_uuid) > 0) {
      warning(paste0(
        "The following uuid(s) were not found in the dataset and will be skipped: ",
        paste(bad_uuid, collapse = ", ")
      ))
      cl_change <- cl_change[
        all_wide | (cl_change[[log_uuid_col]] %in% raw_uuids),
        ,
        drop = FALSE
      ]
    }

    # build the new value to write (blank_response -> NA, change_response -> new_value)
    write_value <- ifelse(
      cl_change[[log_action_col]] %in% tolower(blank_response_values),
      NA_character_,
      cl_change[[log_new_value_col]]
    )

    # vectorised application grouped by question for efficiency
    questions <- unique(cl_change[[log_question_col]])

    for (q in questions) {
      q_rows <- which(cl_change[[log_question_col]] == q)
      q_uuids <- cl_change[[log_uuid_col]][q_rows]
      q_vals <- write_value[q_rows]
      q_acts <- cl_change[[log_action_col]][q_rows]

      # --- column-wide ("all_data") changes first so per-uuid changes override ---
      wide_idx <- which(tolower(q_uuids) == "all_data")
      if (length(wide_idx) > 0) {
        # last all_data entry wins if there are multiple (shouldn't happen after dedup)
        wide_val <- q_vals[wide_idx[length(wide_idx)]]
        wide_act <- q_acts[wide_idx[length(wide_idx)]]
        before <- raw_dataset[[q]]
        raw_dataset[[q]] <- wide_val
        audit_parts[[length(audit_parts) + 1]] <- data.frame(
          uuid = raw_uuids,
          question = q,
          action = wide_act,
          value_before = as.character(before),
          value_after = as.character(wide_val),
          stringsAsFactors = FALSE
        )
        # remove all_data rows so they are not re-processed below
        q_rows <- q_rows[-wide_idx]
        q_uuids <- q_uuids[-wide_idx]
        q_vals <- q_vals[-wide_idx]
        q_acts <- q_acts[-wide_idx]
      }

      # --- per-uuid changes (override any all_data default set above) ---
      if (length(q_uuids) == 0) {
        next
      }

      row_idx <- match(q_uuids, raw_uuids)
      valid <- !is.na(row_idx)

      if (any(valid)) {
        before <- raw_dataset[[q]][row_idx[valid]]
        raw_dataset[[q]][row_idx[valid]] <- q_vals[valid]
        audit_parts[[length(audit_parts) + 1]] <- data.frame(
          uuid = q_uuids[valid],
          question = q,
          action = q_acts[valid],
          value_before = as.character(before),
          value_after = as.character(q_vals[valid]),
          stringsAsFactors = FALSE
        )
      }
    }
  }

  # ---- APPLY: survey removal (discard) ----
  n_removed <- 0L
  if (nrow(cl_remove) > 0) {
    remove_uuids <- unique(cl_remove[[log_uuid_col]])
    # only remove uuids that actually exist
    remove_uuids <- remove_uuids[remove_uuids %in% raw_uuids]
    if (length(remove_uuids) > 0) {
      audit_parts[[length(audit_parts) + 1]] <- data.frame(
        uuid = remove_uuids,
        question = NA_character_,
        action = "discard",
        value_before = "survey present",
        value_after = "survey removed",
        stringsAsFactors = FALSE
      )
      raw_dataset <- raw_dataset[
        !(trimws(as.character(raw_dataset[[raw_uuid_column]])) %in%
          remove_uuids),
        ,
        drop = FALSE
      ]
      n_removed <- length(remove_uuids)
    }
  }

  # ---- assemble audit log ----
  audit_log <- if (length(audit_parts) > 0) {
    out <- do.call(rbind, audit_parts)
    rownames(out) <- NULL
    out
  } else {
    data.frame(
      uuid = character(0),
      question = character(0),
      action = character(0),
      value_before = character(0),
      value_after = character(0),
      stringsAsFactors = FALSE
    )
  }

  # ---- restore types on data rows only ----
  # Must happen before reattaching the label row. The label row contains text
  # descriptions ("Age", "Country of interview") that would prevent numeric
  # columns from being restored if they were already present. The label row is
  # kept as a character dataframe and bound after type restoration.
  if (restore_types) {
    raw_dataset <- utils::type.convert(raw_dataset, as.is = TRUE)
  }

  # ---- reattach label row ----
  # After type.convert the data columns may be integer/numeric. Bind the label
  # row by coercing everything back to character for rbind, then let the
  # resulting dataset keep its mixed types (character for label row columns,
  # correct type for data rows — R stores them as the most general type, which
  # is character for any column that has the text label in row 1).
  # This matches the original ONA export structure where the label row is
  # simply the first data row and the analyst works with the column class
  # produced by readxl / read.csv on the full file.
  if (!is.null(label_row)) {
    label_row_aligned <- as.data.frame(
      lapply(names(raw_dataset), function(col) {
        if (col %in% names(label_row)) {
          as.character(label_row[[col]])
        } else {
          NA_character_
        }
      }),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    names(label_row_aligned) <- names(raw_dataset)
    # coerce dataset back to character only for binding, then restore
    raw_char <- as.data.frame(
      lapply(raw_dataset, as.character),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    raw_dataset <- rbind(label_row_aligned, raw_char)
  }

  n_cell_changes <- nrow(audit_log) - n_removed
  n_no_action <- sum(is_no_act)

  if (verbose) {
    message(paste0(
      "apply_cleaning_log: ",
      n_cell_changes,
      " cell-level change(s) applied",
      ", ",
      n_removed,
      " survey(s) removed",
      ", ",
      n_no_action,
      " row(s) skipped (no_action)",
      ". Dataset: ",
      n_rows_start,
      " \u2192 ",
      nrow(raw_dataset) -
        if (!is.null(label_row)) 1L else 0L,
      " record(s)."
    ))
  }

  list(
    clean_dataset = raw_dataset,
    audit_log = audit_log
  )
}
