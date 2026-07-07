#' Validate Survey Duration
#'
#' Checks whether the survey duration (typically stored in a column like `_duration` in seconds)
#' falls within specified lower and upper bounds (in minutes). It generates a validation log
#' of surveys that are either too short or too long.
#'
#' @param dataset A dataframe or a list containing a dataframe named `checked_dataset`.
#' @param column_to_check The name of the column containing the duration in seconds. Default is \code{"_duration"}.
#' @param uuid_column The name of the column containing the unique identifier. Default is \code{"uuid"}.
#' @param log_name The name of the log to create in the list. Default is \code{"duration_log"}.
#' @param lower_bound The lower threshold for duration in minutes. Default is \code{15}.
#' @param upper_bound The upper threshold for duration in minutes. Default is \code{60}.
#' @return A list containing the original dataset and the new log dataframe.
#' @export
validate_duration <- function(
  dataset,
  column_to_check = "_duration",
  uuid_column = "uuid",
  log_name = "duration_log",
  lower_bound = 15,
  upper_bound = 60
) {
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list")
  }

  if (!(column_to_check %in% names(dataset[["checked_dataset"]]))) {
    msg <- paste0(
      "Cannot find ",
      column_to_check,
      " in the names of the dataset"
    )
    stop(msg)
  }

  log <- dataset[["checked_dataset"]] %>%
    dplyr::mutate(
      duration_check = (as.numeric(!!rlang::sym(column_to_check)) / 60) <
        lower_bound |
        (as.numeric(!!rlang::sym(column_to_check)) / 60) > upper_bound
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

  dataset[[log_name]] <- log
  return(dataset)
}
