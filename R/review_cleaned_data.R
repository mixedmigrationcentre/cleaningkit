#' Review Cleaned Data Against the Raw Dataset and Cleaning Log
#'
#' Compares the raw dataset, clean dataset, and combined cleaning log to verify
#' that every change documented in the log was actually applied, and that no
#' undocumented changes slipped through. Returns a single dataframe listing
#' every discrepancy found, ready for investigation before sign-off.
#'
#' @details
#' \strong{Checks performed:}
#' \describe{
#'   \item{uuid in discard log still present in clean data}{A survey marked
#'     \code{discard} was not removed from the clean dataset.}
#'   \item{uuid in discard log not in raw data}{The discard log references a
#'     uuid that doesn't exist in the raw dataset — probably a typo.}
#'   \item{uuid in cleaning log also in discard log}{A cell-level change was
#'     logged for a survey that is also marked for discard — contradictory.}
#'   \item{no_action with mismatched new/old value}{A \code{no_action} row has
#'     a \code{New value} that differs from \code{Old value} — the reviewer
#'     may have accidentally changed something.}
#'   \item{change not applied}{The \code{New value} in the cleaning log does
#'     not match the actual value in the clean dataset — the cleaning step
#'     missed this row.}
#'   \item{undocumented change}{A value differs between raw and clean datasets
#'     but has no corresponding row in the cleaning log.}
#'   \item{new value mismatch}{The cleaning log says the new value should be X
#'     but the clean dataset has Y.}
#'   \item{duplicate uuid+question}{The same \code{uuid + question} appears
#'     more than once in the cleaning log with different \code{New value}s —
#'     ambiguous.}
#'   \item{uuid missing from raw data}{The cleaning log references a uuid that
#'     does not exist in the raw dataset.}
#'   \item{question missing from raw data}{The cleaning log references a column
#'     that does not exist in the raw dataset.}
#' }
#'
#' \strong{Action type mapping (your log → internal):}
#' \describe{
#'   \item{\code{recoded}, \code{addition}, \code{other}}{Cell changed to
#'     \code{New value} — verified against the clean dataset.}
#'   \item{\code{delete_data_point}}{Cell set to \code{NA}/blank.}
#'   \item{\code{discard}}{Entire survey removed.}
#'   \item{\code{no_action}}{No change — \code{New value} should equal
#'     \code{Old value}.}
#' }
#'
#' @param raw_dataset The original raw dataset.
#' @param clean_dataset The cleaned dataset to verify.
#' @param cleaning_log The combined cleaning log as produced by
#'   \code{combine_reviewed_logs()} or \code{create_cleaning_log()}.
#' @param raw_uuid_column Name of the uuid column in \code{raw_dataset}.
#'   Default \code{"_uuid"}.
#' @param clean_uuid_column Name of the uuid column in \code{clean_dataset}.
#'   Default \code{"_uuid"}.
#' @param log_uuid_col Name of the uuid column in \code{cleaning_log}.
#'   Default \code{"Survey UUID"}.
#' @param log_question_col Name of the question column in \code{cleaning_log}.
#'   Default \code{"Question number"}.
#' @param log_new_value_col Name of the new-value column. Default
#'   \code{"New value"}.
#' @param log_old_value_col Name of the old-value column. Default
#'   \code{"Old value"}.
#' @param log_action_col Name of the action-type column. Default
#'   \code{"Action taken"}.
#' @param change_response_values Action values meaning "cell changed". Default
#'   \code{c("recoded", "addition", "other")}.
#' @param blank_response_values Action values meaning "cell blanked". Default
#'   \code{"delete_data_point"}.
#' @param discard_values Action values meaning "survey removed". Default
#'   \code{"discard"}.
#' @param no_action_values Action values meaning "no change". Default
#'   \code{"no_action"}.
#' @param columns_to_skip Column names to exclude from the undocumented-change
#'   check (e.g. system columns). Default covers common ONA metadata columns.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row
#'   of both \code{raw_dataset} and \code{clean_dataset} is treated as the ONA
#'   label/description row and excluded from all comparisons.
#' @param verbose Logical. If \code{TRUE} (the default), a summary of findings
#'   is printed on completion.
#'
#' @return A dataframe with columns \code{uuid}, \code{question},
#'   \code{action_in_log}, \code{old_value}, \code{new_value_log},
#'   \code{new_value_clean}, \code{check_type}, and \code{comment}. Zero rows
#'   means the clean dataset perfectly matches the cleaning log.
#' @export
review_cleaned_data <- function(
  raw_dataset,
  clean_dataset,
  cleaning_log,
  raw_uuid_column = "_uuid",
  clean_uuid_column = "_uuid",
  log_uuid_col = "Survey UUID",
  log_question_col = "Question number",
  log_new_value_col = "New value",
  log_old_value_col = "Old value",
  log_action_col = "Action taken",
  change_response_values = c("recoded", "addition", "other"),
  blank_response_values = "delete_data_point",
  discard_values = "discard",
  no_action_values = "no_action",
  columns_to_skip = c(
    "start",
    "end",
    "today",
    "deviceid",
    "uuid",
    "_uuid",
    "id",
    "_id",
    "submission_time",
    "_submission_time",
    "index",
    "_index",
    "df_name",
    "username",
    "simserial",
    "phonenumber",
    "_submission_time",
    "check_binding",
    "evaluation_issue"
  ),
  skip_label_row = TRUE,
  verbose = TRUE
) {
  # ---- helpers ----
  is_empty <- function(x) is.na(x) | trimws(as.character(x)) %in% c("", "NA")

  # coerce all columns to character for safe comparison
  coerce_chr <- function(df) {
    as.data.frame(
      lapply(df, as.character),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  }

  # fuzzy equality: "1"/"TRUE", "0"/"FALSE" treated as equivalent
  vals_equal <- function(a, b) {
    a <- trimws(as.character(a))
    b <- trimws(as.character(b))
    same <- a == b | (is.na(a) & is.na(b))
    bool_match <- (a %in% c("1", "TRUE") & b %in% c("1", "TRUE")) |
      (a %in% c("0", "FALSE") & b %in% c("0", "FALSE"))
    num_match <- suppressWarnings(
      !is.na(as.numeric(a)) &
        !is.na(as.numeric(b)) &
        as.numeric(a) == as.numeric(b)
    )
    same | bool_match | num_match
  }

  # ---- input validation ----
  for (p in list(
    list(raw_dataset, raw_uuid_column, "raw_dataset"),
    list(clean_dataset, clean_uuid_column, "clean_dataset")
  )) {
    if (!is.data.frame(p[[1]])) {
      stop(paste0("`", p[[3]], "` must be a dataframe."))
    }
    if (!(p[[2]] %in% names(p[[1]]))) {
      stop(paste0("UUID column '", p[[2]], "' not found in `", p[[3]], "`."))
    }
  }
  if (!is.data.frame(cleaning_log) || nrow(cleaning_log) == 0) {
    stop("`cleaning_log` must be a non-empty dataframe.")
  }

  required_log <- c(
    log_uuid_col,
    log_question_col,
    log_new_value_col,
    log_old_value_col,
    log_action_col
  )
  miss <- setdiff(required_log, names(cleaning_log))
  if (length(miss) > 0) {
    stop(paste0(
      "cleaning_log missing column(s): ",
      paste(miss, collapse = ", ")
    ))
  }

  all_action_values <- c(
    change_response_values,
    blank_response_values,
    discard_values,
    no_action_values
  )

  # ---- drop ONA label rows ----
  if (skip_label_row) {
    if (nrow(raw_dataset) > 0) {
      raw_dataset <- raw_dataset[-1, , drop = FALSE]
    }
    if (nrow(clean_dataset) > 0) {
      clean_dataset <- clean_dataset[-1, , drop = FALSE]
    }
  }

  raw <- coerce_chr(raw_dataset)
  clean <- coerce_chr(clean_dataset)

  raw_uuids <- trimws(raw[[raw_uuid_column]])
  clean_uuids <- trimws(clean[[clean_uuid_column]])

  # ---- normalise cleaning log ----
  cl <- cleaning_log
  cl[[log_uuid_col]] <- trimws(as.character(cl[[log_uuid_col]]))
  cl[[log_action_col]] <- trimws(tolower(as.character(cl[[log_action_col]])))
  cl[[log_question_col]] <- trimws(as.character(cl[[log_question_col]]))
  cl[[log_new_value_col]] <- as.character(cl[[log_new_value_col]])
  cl[[log_old_value_col]] <- as.character(cl[[log_old_value_col]])

  # convenience accessors
  cl_uuid <- cl[[log_uuid_col]]
  cl_action <- cl[[log_action_col]]
  cl_q <- cl[[log_question_col]]
  cl_new <- cl[[log_new_value_col]]
  cl_old <- cl[[log_old_value_col]]

  # unique key for dedup checks
  cl_key <- paste(cl_uuid, cl_q, sep = "__|__")

  issues <- list()

  emit <- function(
    name,
    uuids,
    questions,
    actions,
    old_vals,
    new_log,
    new_clean,
    ctype,
    comment
  ) {
    if (length(uuids) == 0) {
      return()
    }
    issues[[name]] <<- data.frame(
      uuid = uuids,
      question = questions,
      action_in_log = actions,
      old_value = old_vals,
      new_value_log = new_log,
      new_value_clean = new_clean,
      check_type = ctype,
      comment = comment,
      stringsAsFactors = FALSE
    )
  }

  # =====================================================================
  # CHECK 1: uuid in cleaning log not found in raw dataset
  # =====================================================================
  discard_rows <- which(cl_action %in% tolower(discard_values))
  cell_rows <- which(
    cl_action %in%
      c(
        tolower(change_response_values),
        tolower(blank_response_values),
        tolower(no_action_values)
      )
  )

  bad_uuid_cell <- cell_rows[!(cl_uuid[cell_rows] %in% raw_uuids)]
  emit(
    "uuid_not_in_raw",
    cl_uuid[bad_uuid_cell],
    cl_q[bad_uuid_cell],
    cl_action[bad_uuid_cell],
    cl_old[bad_uuid_cell],
    cl_new[bad_uuid_cell],
    NA_character_,
    "uuid_not_in_raw",
    paste0(
      "uuid '",
      cl_uuid[bad_uuid_cell],
      "' in cleaning log not found in raw dataset"
    )
  )

  # =====================================================================
  # CHECK 2: question in cleaning log not found in raw dataset
  # =====================================================================
  # (exclude discard rows and sentinel values)
  q_check_rows <- cell_rows[!(cl_q[cell_rows] %in% c("all_columns", "all"))]
  q_check_rows <- q_check_rows[cl_uuid[q_check_rows] %in% raw_uuids]
  bad_q <- q_check_rows[!(cl_q[q_check_rows] %in% names(raw))]
  emit(
    "question_not_in_raw",
    cl_uuid[bad_q],
    cl_q[bad_q],
    cl_action[bad_q],
    cl_old[bad_q],
    cl_new[bad_q],
    NA_character_,
    "question_not_in_raw",
    paste0(
      "Question '",
      cl_q[bad_q],
      "' in cleaning log not found in raw dataset"
    )
  )

  # =====================================================================
  # CHECK 3: no_action rows where New value ≠ Old value
  # =====================================================================
  no_act_rows <- which(cl_action %in% tolower(no_action_values))
  no_act_mismatch <- no_act_rows[
    !is_empty(cl_new[no_act_rows]) &
      !vals_equal(cl_new[no_act_rows], cl_old[no_act_rows])
  ]
  emit(
    "no_action_value_mismatch",
    cl_uuid[no_act_mismatch],
    cl_q[no_act_mismatch],
    cl_action[no_act_mismatch],
    cl_old[no_act_mismatch],
    cl_new[no_act_mismatch],
    NA_character_,
    "no_action_value_mismatch",
    "Action is no_action but New value differs from Old value"
  )

  # =====================================================================
  # CHECK 4: discard uuid still present in clean dataset
  # =====================================================================
  discard_uuids <- unique(cl_uuid[discard_rows])
  still_present <- discard_uuids[discard_uuids %in% clean_uuids]
  emit(
    "discard_not_applied",
    still_present,
    NA_character_,
    "discard",
    NA_character_,
    NA_character_,
    NA_character_,
    "discard_not_applied",
    paste0(
      "Survey '",
      still_present,
      "' is marked discard in the log but is still in the clean dataset"
    )
  )

  # =====================================================================
  # CHECK 5: discard uuid not found in raw dataset (bad uuid in log)
  # =====================================================================
  discard_not_in_raw <- discard_uuids[!(discard_uuids %in% raw_uuids)]
  emit(
    "discard_uuid_not_in_raw",
    discard_not_in_raw,
    NA_character_,
    "discard",
    NA_character_,
    NA_character_,
    NA_character_,
    "discard_uuid_not_in_raw",
    paste0(
      "Discard uuid '",
      discard_not_in_raw,
      "' not found in raw dataset — possible typo"
    )
  )

  # =====================================================================
  # CHECK 6: cell-level log row for a uuid that is also being discarded
  # =====================================================================
  contradicted <- cell_rows[cl_uuid[cell_rows] %in% discard_uuids]
  emit(
    "cell_change_for_discarded_uuid",
    cl_uuid[contradicted],
    cl_q[contradicted],
    cl_action[contradicted],
    cl_old[contradicted],
    cl_new[contradicted],
    NA_character_,
    "cell_change_for_discarded_uuid",
    "This uuid is also marked for discard — cell-level change is contradictory"
  )

  # =====================================================================
  # CHECK 7: duplicate uuid + question with different new values
  # =====================================================================
  # Only look at rows with real change actions (exclude no_action and discard)
  real_change <- which(
    cl_action %in%
      c(tolower(change_response_values), tolower(blank_response_values))
  )
  dup_key <- cl_key[real_change]
  dup_mask <- duplicated(dup_key) | duplicated(dup_key, fromLast = TRUE)
  dup_idx <- real_change[dup_mask]

  if (length(dup_idx) > 0) {
    # only flag groups where the new value actually differs
    dup_df <- data.frame(
      key = dup_key[dup_mask],
      new = cl_new[dup_idx],
      idx = dup_idx,
      stringsAsFactors = FALSE
    )
    flag_keys <- unique(dup_df$key[
      vapply(
        unique(dup_df$key),
        function(k) {
          vals <- dup_df$new[dup_df$key == k]
          length(unique(trimws(vals))) > 1
        },
        logical(1)
      )
    ])
    flag_idx <- dup_idx[dup_key[dup_mask] %in% flag_keys]
    emit(
      "duplicate_uuid_question",
      cl_uuid[flag_idx],
      cl_q[flag_idx],
      cl_action[flag_idx],
      cl_old[flag_idx],
      cl_new[flag_idx],
      NA_character_,
      "duplicate_uuid_question",
      "Same uuid+question appears more than once with different New values — ambiguous"
    )
  }

  # =====================================================================
  # CHECK 8: changes not applied / new value mismatch
  # Build a uuid+question → clean_value lookup via pivot for efficiency
  # =====================================================================
  check_action_idx <- which(
    cl_action %in%
      c(tolower(change_response_values), tolower(blank_response_values)) &
      cl_uuid %in% raw_uuids &
      cl_q %in% names(raw) &
      !(cl_uuid %in% discard_uuids)
  )

  if (length(check_action_idx) > 0) {
    # Build uuid → row-index lookup for clean dataset
    clean_row_idx <- stats::setNames(seq_along(clean_uuids), clean_uuids)

    for (i in check_action_idx) {
      uid <- cl_uuid[i]
      q <- cl_q[i]
      action <- cl_action[i]
      new_in_log <- cl_new[i]
      old_in_log <- cl_old[i]

      crow <- clean_row_idx[uid]
      if (is.na(crow)) {
        # uuid was removed (discard) — skip
        next
      }
      if (!(q %in% names(clean))) {
        next
      }

      val_in_clean <- clean[[q]][crow]

      # expected value after cleaning
      expected <- if (action %in% tolower(blank_response_values)) {
        NA_character_
      } else {
        new_in_log
      }

      if (!vals_equal(val_in_clean, expected)) {
        comment <- if (vals_equal(val_in_clean, old_in_log)) {
          "Change was not applied — clean dataset still has the old value"
        } else {
          paste0(
            "New value mismatch: log says '",
            ifelse(is.na(expected), "<blank>", expected),
            "' but clean dataset has '",
            ifelse(is.na(val_in_clean), "<blank>", val_in_clean),
            "'"
          )
        }
        issues[[paste0("change_check_", i)]] <- data.frame(
          uuid = uid,
          question = q,
          action_in_log = action,
          old_value = old_in_log,
          new_value_log = new_in_log,
          new_value_clean = val_in_clean,
          check_type = "change_not_applied",
          comment = comment,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  # =====================================================================
  # CHECK 9: undocumented changes — values differ between raw and clean
  #          with no corresponding log entry
  # =====================================================================
  # Build a set of (uuid, question) pairs that ARE documented
  documented_keys <- paste(
    cl_uuid[real_change],
    cl_q[real_change],
    sep = "__|__"
  )

  # Columns to compare: present in both datasets, not in skip list
  compare_cols <- intersect(names(raw), names(clean))
  compare_cols <- setdiff(compare_cols, c(raw_uuid_column, columns_to_skip))

  # Only compare uuids present in both (not discarded)
  compare_uuids <- intersect(raw_uuids, clean_uuids)
  compare_uuids <- setdiff(compare_uuids, discard_uuids)

  raw_idx <- stats::setNames(seq_along(raw_uuids), raw_uuids)
  clean_idx <- stats::setNames(seq_along(clean_uuids), clean_uuids)

  undoc_rows <- list()
  for (col in compare_cols) {
    r_vals <- raw[[col]][raw_idx[compare_uuids]]
    c_vals <- clean[[col]][clean_idx[compare_uuids]]

    changed_mask <- !vals_equal(r_vals, c_vals)
    if (!any(changed_mask, na.rm = TRUE)) {
      next
    }

    changed_uuids <- compare_uuids[changed_mask]
    keys <- paste(changed_uuids, col, sep = "__|__")
    undoc_mask <- !(keys %in% documented_keys)
    undoc_uuids <- changed_uuids[undoc_mask]

    if (length(undoc_uuids) == 0) {
      next
    }

    undoc_rows[[col]] <- data.frame(
      uuid = undoc_uuids,
      question = col,
      action_in_log = NA_character_,
      old_value = raw[[col]][raw_idx[undoc_uuids]],
      new_value_log = NA_character_,
      new_value_clean = clean[[col]][clean_idx[undoc_uuids]],
      check_type = "undocumented_change",
      comment = paste0(
        "Value differs between raw and clean datasets ",
        "but no entry found in the cleaning log"
      ),
      stringsAsFactors = FALSE
    )
  }
  if (length(undoc_rows) > 0) {
    issues[["undocumented_changes"]] <- do.call(rbind, undoc_rows)
  }

  # =====================================================================
  # Assemble results
  # =====================================================================
  if (length(issues) == 0) {
    result <- data.frame(
      uuid = character(0),
      question = character(0),
      action_in_log = character(0),
      old_value = character(0),
      new_value_log = character(0),
      new_value_clean = character(0),
      check_type = character(0),
      comment = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    result <- do.call(rbind, issues)
    rownames(result) <- NULL
    result <- result[order(result$uuid, result$question), ]
  }

  if (verbose) {
    if (nrow(result) == 0) {
      message(
        "review_cleaned_data: no issues found. ",
        "The clean dataset matches the cleaning log."
      )
    } else {
      by_type <- table(result$check_type)
      message(
        "review_cleaned_data: ",
        nrow(result),
        " issue(s) found across ",
        length(unique(result$uuid[!is.na(result$uuid)])),
        " uuid(s)."
      )
      for (nm in names(by_type)) {
        message("  ", by_type[[nm]], "x ", nm)
      }
    }
  }

  result
}
