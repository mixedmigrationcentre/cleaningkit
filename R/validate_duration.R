#' Validate Survey Duration
#'
#' Checks whether the survey duration (typically stored in a column like `_duration` in seconds)
#' falls within specified lower and upper bounds (in minutes). It generates a validation log
#' of surveys that are either too short or too long.
#'
#' @param dataset A dataframe or a list containing a dataframe named `checked_dataset`.
#' @param column_to_check The name of the column containing the duration in seconds. Default is \code{"_duration"}.
#' @param uuid_column The name of the column containing the unique identifier. Default is \code{"_uuid"}.
#' @param log_name The name of the log to create in the list. Default is \code{"duration_log"}.
#' @param lower_bound The lower threshold for duration in minutes. Default is \code{15}.
#' @param upper_bound The upper threshold for duration in minutes. Default is \code{60}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of the dataset is removed
#'   before validation. ONA exports include a label/description row immediately after the header
#'   that should not be treated as survey data.
#' @return A list containing the original dataset and the new log dataframe.
#' @export
validate_duration <- function(
  dataset,
  column_to_check = "_duration",
  uuid_column = "_uuid",
  log_name = "duration_log",
  lower_bound = 15,
  upper_bound = 60,
  skip_label_row = TRUE
) {
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list")
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
      duration_check = !!rlang::sym(column_to_check) < lower_bound |
        !!rlang::sym(column_to_check) > upper_bound
    ) %>%
    dplyr::filter(duration_check) %>%
    dplyr::select(dplyr::all_of(c(uuid_column, column_to_check))) %>%
    dplyr::mutate(
      question = column_to_check,
      issue = "Duration is lower or higher than the thresholds"
    ) %>%
    dplyr::rename(
      old_value = !!rlang::sym(column_to_check),
      uuid = !!rlang::sym(uuid_column)
    )

  # Convert old_value to character to ensure consistency across logs if combined
  log$old_value <- as.character(log$old_value)

  dataset[[log_name]] <- log
  return(dataset)
}
