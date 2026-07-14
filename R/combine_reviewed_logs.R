#' Combine Reviewed Logs into a Single Reviewer-Ready Log
#'
#' Merges the other-responses cleaning log (from \code{read_other_responses()})
#' with the main cleaning log (from \code{create_cleaning_log()}) into one
#' unified dataframe that follows the \code{create_cleaning_log()} column shape,
#' ready for review in Excel or for passing to \code{evaluate_cleaning_log()}.
#'
#' @details
#' \strong{Column mapping from the other-responses log:}
#' \describe{
#'   \item{\code{uuid}}{→ \code{Survey UUID}; also used to look up
#'     \code{Date} and \code{Enumerator} from the dataset.}
#'   \item{\code{question}}{→ \code{Question number}; label looked up from the
#'     dataset label row → \code{Question text}.}
#'   \item{\code{action_taken}}{→ \code{Action taken} (kept as-is) and used to
#'     generate a human-readable \code{Issue} description.}
#'   \item{\code{old_value}}{→ \code{Old value}.}
#'   \item{\code{new_value}}{→ \code{New value} (already filled by
#'     \code{read_other_responses()}).}
#' }
#'
#' \strong{Issue descriptions generated from \code{action_taken}:}
#' \describe{
#'   \item{\code{true_other}}{Translation or correction of a genuine other response}
#'   \item{\code{recode}}{Other response recoded to an existing choice}
#'   \item{\code{remove}}{Invalid other response — value removed}
#' }
#'
#' \strong{check_binding:} rows from the same other-response action on the same
#' record share a \code{check_binding} of \code{"other_response ~/~ <uuid>"},
#' so they are coloured as a group in the review workbook.
#'
#' @param main_log A list returned by \code{create_cleaning_log()} (containing
#'   \code{cleaning_log} and optionally \code{checked_dataset}), or a dataframe
#'   that is already in the \code{create_cleaning_log()} column shape.
#' @param other_log A dataframe returned by \code{read_other_responses()}, with
#'   columns \code{uuid}, \code{question}, \code{action_taken}, \code{old_value},
#'   \code{new_value}.
#' @param dataset The working dataset (with the ONA label row still as row 1 if
#'   \code{skip_label_row = TRUE}). Used to look up \code{Date} and
#'   \code{Enumerator} for each other-response row.
#' @param uuid_column Name of the uuid column in \code{dataset}. Default
#'   \code{"_uuid"}.
#' @param enumerator_column Name of the enumerator column. Default
#'   \code{"username"}.
#' @param date_column Name of the date column. Default \code{"today"}.
#' @param cleaning_log_name Name of the cleaning log element when
#'   \code{main_log} is a list. Default \code{"cleaning_log"}.
#' @param issue_labels Named character vector mapping \code{action_taken} values
#'   to human-readable issue descriptions. Defaults cover the three standard
#'   other-response action types.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row
#'   of \code{dataset} is treated as the ONA label/description row and skipped
#'   when building the date/enumerator lookup and question-text lookup.
#'
#' @return A single dataframe in the \code{create_cleaning_log()} column shape,
#'   with the other-response rows appended after the main cleaning log rows.
#'   Columns: \code{Date}, \code{Survey UUID}, \code{Survey Registration Date},
#'   \code{Enumerator}, \code{Section}, \code{Question number},
#'   \code{Question text}, \code{Issue}, \code{Old value}, \code{Action taken},
#'   \code{New value}, \code{Identified by}, \code{Comments},
#'   \code{PO feedback}, \code{check_binding}.
#' @export
combine_reviewed_logs <- function(
  main_log,
  other_log,
  dataset,
  uuid_column = "_uuid",
  enumerator_column = "username",
  date_column = "today",
  cleaning_log_name = "cleaning_log",
  issue_labels = c(
    true_other = "Translation or correction of a genuine other response",
    recode = "Other response recoded to an existing choice",
    remove = "Invalid other response — value removed"
  ),
  skip_label_row = TRUE
) {
  # ---- resolve main_log to a dataframe ----
  if (is.list(main_log) && !is.data.frame(main_log)) {
    if (!(cleaning_log_name %in% names(main_log))) {
      stop(paste0(
        "'",
        cleaning_log_name,
        "' not found in main_log list. ",
        "Available: ",
        paste(names(main_log), collapse = ", ")
      ))
    }
    main_df <- as.data.frame(
      main_log[[cleaning_log_name]],
      stringsAsFactors = FALSE
    )
  } else {
    main_df <- as.data.frame(main_log, stringsAsFactors = FALSE)
  }

  # ---- validate other_log ----
  if (!is.data.frame(other_log) || nrow(other_log) == 0) {
    message(
      "combine_cleaning_logs: other_log is empty — returning main_log unchanged."
    )
    return(main_df)
  }
  required_other_cols <- c(
    "uuid",
    "question",
    "action_taken",
    "old_value",
    "new_value"
  )
  missing_cols <- setdiff(required_other_cols, names(other_log))
  if (length(missing_cols) > 0) {
    stop(paste0(
      "other_log is missing required column(s): ",
      paste(missing_cols, collapse = ", ")
    ))
  }

  # ---- validate main_df has the expected shape ----
  expected_main_cols <- c(
    "Survey UUID",
    "Question number",
    "Old value",
    "Action taken",
    "New value"
  )
  missing_main <- setdiff(expected_main_cols, names(main_df))
  if (length(missing_main) > 0) {
    stop(paste0(
      "main_log is missing expected column(s): ",
      paste(missing_main, collapse = ", "),
      "\nEnsure it comes from create_cleaning_log()."
    ))
  }

  if (!(uuid_column %in% names(dataset))) {
    stop(paste0("Cannot find '", uuid_column, "' in dataset."))
  }

  # ---- build lookups from dataset ----
  clean_date <- function(x) {
    if (inherits(x, c("POSIXct", "POSIXt", "Date"))) {
      return(format(x, "%Y-%m-%d"))
    }
    x_chr <- as.character(x)
    is_iso <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", x_chr)
    x_chr[is_iso] <- substr(x_chr[is_iso], 1, 10)
    x_chr
  }

  if (skip_label_row && nrow(dataset) > 0) {
    label_row <- dataset[1, , drop = FALSE]
    data_rows <- dataset[-1, , drop = FALSE]
  } else {
    label_row <- NULL
    data_rows <- dataset
  }

  uuid_key <- trimws(as.character(data_rows[[uuid_column]]))

  # question-text from the label row (column name → label description)
  label_lookup <- if (!is.null(label_row)) {
    stats::setNames(
      trimws(as.character(unlist(label_row[1, ], use.names = FALSE))),
      names(label_row)
    )
  } else {
    stats::setNames(character(0), character(0))
  }

  # uuid → date
  date_lookup <- if (date_column %in% names(data_rows)) {
    stats::setNames(clean_date(data_rows[[date_column]]), uuid_key)
  } else {
    warning(paste0(
      "'",
      date_column,
      "' not found in dataset; Date left blank."
    ))
    NULL
  }

  # uuid → enumerator
  enum_lookup <- if (enumerator_column %in% names(data_rows)) {
    stats::setNames(
      trimws(as.character(data_rows[[enumerator_column]])),
      uuid_key
    )
  } else {
    warning(paste0(
      "'",
      enumerator_column,
      "' not found in dataset; Enumerator left blank."
    ))
    NULL
  }

  lkp <- function(tbl, key) {
    if (is.null(tbl)) {
      return(rep(NA_character_, length(key)))
    }
    unname(tbl[key])
  }

  # ---- reshape other_log into the main_log column shape ----
  or <- other_log
  or_uuids <- trimws(as.character(or$uuid))
  or_questions <- trimws(as.character(or$question))

  # map action_taken → human-readable issue
  or_issue <- vapply(
    trimws(as.character(or$action_taken)),
    function(a) {
      lbl <- issue_labels[a]
      if (is.na(lbl)) paste0("Other response cleaning: ", a) else lbl
    },
    character(1)
  )

  # check_binding: all rows from the same (action_type, uuid) share one colour
  # so the reviewer sees the full set of columns affected by one decision together
  or_binding <- paste0("other_response ~/~ ", or_uuids)

  other_shaped <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    "Date" = lkp(date_lookup, or_uuids),
    "Survey UUID" = or_uuids,
    "Survey Registration Date" = NA_character_,
    "Enumerator" = lkp(enum_lookup, or_uuids),
    "Section" = NA_character_,
    "Question number" = or_questions,
    "Question text" = unname(label_lookup[or_questions]),
    "Issue" = or_issue,
    "Old value" = as.character(or$old_value),
    "Action taken" = as.character(or$action_taken),
    "New value" = as.character(or$new_value),
    "Identified by" = NA_character_,
    "Comments" = NA_character_,
    "PO feedback" = NA_character_,
    "check_binding" = or_binding
  )

  # ---- ensure main_df has check_binding (may be absent in older logs) ----
  if (!("check_binding" %in% names(main_df))) {
    main_df[["check_binding"]] <- NA_character_
  }

  # ---- align columns: add any missing cols to either frame as NA ----
  all_cols <- union(names(main_df), names(other_shaped))
  for (col in setdiff(all_cols, names(main_df))) {
    main_df[[col]] <- NA_character_
  }
  for (col in setdiff(all_cols, names(other_shaped))) {
    other_shaped[[col]] <- NA_character_
  }

  # keep the main_log column order, appending any extra cols from other_shaped
  main_col_order <- names(main_df)
  extra_cols <- setdiff(names(other_shaped), main_col_order)
  col_order <- c(main_col_order, extra_cols)

  combined <- rbind(
    main_df[, col_order, drop = FALSE],
    other_shaped[, col_order, drop = FALSE]
  )
  rownames(combined) <- NULL

  message(
    "combine_reviewed_logs: ",
    nrow(main_df),
    " main row(s) + ",
    nrow(other_shaped),
    " other-response row(s) = ",
    nrow(combined),
    " total."
  )
  combined
}
