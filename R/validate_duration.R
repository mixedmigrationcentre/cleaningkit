#' Validate Survey Duration
#'
#' Checks whether the survey duration (typically stored in a column like `_duration` in seconds)
#' falls within specified lower and upper bounds (in minutes). It generates a validation log
#' of surveys that breach those thresholds.
#'
#' By default only surveys **below** \code{lower_bound} are logged. Surveys running longer than
#' \code{upper_bound} are usually legitimate (interruptions, long interviews) and simply add
#' noise to the cleaning log, so they are excluded unless \code{flag_above_upper = TRUE}.
#'
#' @param dataset A dataframe or a list containing a dataframe named `checked_dataset`.
#' @param column_to_check The name of the column containing the duration in seconds. Default is \code{"_duration"}.
#' @param uuid_column The name of the column containing the unique identifier. Default is \code{"_uuid"}.
#' @param log_name The name of the log to create in the list. Default is \code{"duration_log"}.
#' @param lower_bound The lower threshold for duration in minutes. Default is \code{15}.
#' @param upper_bound The upper threshold for duration in minutes. Default is \code{60}.
#' @param flag_above_upper Logical. If \code{FALSE} (the default), surveys longer than
#'   \code{upper_bound} are **not** reported, because long surveys are normally valid and
#'   would only inflate the cleaning log. Set to \code{TRUE} to also log them.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of the dataset is removed
#'   before validation. ONA exports include a label/description row immediately after the header
#'   that should not be treated as survey data.
#' @return A list containing the original dataset and the new log dataframe. The `issue`
#'   column states the direction of the breach: \code{"Duration is lower than the thresholds"}
#'   when the duration falls below \code{lower_bound}, and
#'   \code{"Duration is higher than the thresholds"} when it exceeds \code{upper_bound}
#'   (the latter only when \code{flag_above_upper = TRUE}).
#' @export
validate_duration <- function(
  dataset,
  column_to_check = "_duration",
  uuid_column = "_uuid",
  log_name = "duration_log",
  lower_bound = 15,
  upper_bound = 60,
  flag_above_upper = FALSE,
  skip_label_row = TRUE
) {
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list")
  }

  if (!is.logical(flag_above_upper) || length(flag_above_upper) != 1 ||
      is.na(flag_above_upper)) {
    stop("flag_above_upper must be TRUE or FALSE")
  }

  df <- dataset[["checked_dataset"]]

  if (!(column_to_check %in% names(df))) {
    msg <- paste0(
      "Cannot find ",
      column_to_check,
      " in the names of the dataset"
    )
    stop(msg)
  }

  # Skip the ONA label/description row (first row after header)
  if (skip_label_row && nrow(df) > 0) {
    df <- df[-1, , drop = FALSE]
  }

  # Divide the duration column by 60 first
  df[[column_to_check]] <- as.numeric(df[[column_to_check]]) / 60

  log <- df %>%
    dplyr::mutate(
      # Long surveys are usually valid, so they are only flagged on request
      above_upper = !!rlang::sym(column_to_check) > upper_bound &
        isTRUE(flag_above_upper),
      duration_check = !!rlang::sym(column_to_check) < lower_bound |
        above_upper,
      # Report the direction of the breach rather than a combined message
      duration_issue = dplyr::case_when(
        !!rlang::sym(column_to_check) < lower_bound ~
          "Duration is lower than the thresholds",
        above_upper ~
          "Duration is higher than the thresholds",
        TRUE ~ NA_character_
      )
    ) %>%
    dplyr::filter(duration_check) %>%
    dplyr::select(
      dplyr::all_of(c(uuid_column, column_to_check, "duration_issue"))
    ) %>%
    dplyr::mutate(question = column_to_check) %>%
    dplyr::rename(
      old_value = !!rlang::sym(column_to_check),
      uuid = !!rlang::sym(uuid_column),
      issue = "duration_issue"
    ) %>%
    dplyr::select(dplyr::all_of(c("uuid", "old_value", "question", "issue")))

  # Convert old_value to character to ensure consistency across logs if combined
  log$old_value <- as.character(log$old_value)

  # Tag with check_binding so the cleaning log can colour-group related rows
  log$check_binding <- paste("duration_check", log$uuid, sep = " ~/~ ")

  dataset[[log_name]] <- log
  return(dataset)
}
