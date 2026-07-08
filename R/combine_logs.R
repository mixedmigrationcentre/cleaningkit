#' Combine Validation Logs into a Single Cleaning Log
#'
#' Stacks the individual logs produced by the \code{validate_*} functions into one cleaning
#' log ready for review and correction, and (optionally) carries the checked dataset through
#' unchanged. Every column of every log is coerced to trimmed, non-scientific character before
#' binding, so logs whose columns have different types never clash when combined.
#'
#' @details
#' The returned \code{cleaning_log} is the row-bind of all log elements, with three columns
#' added: \code{change_type} and \code{new_value} (both \code{NA}, to be filled in during
#' cleaning) and \code{check_binding}, a matching key of the form \code{"question ~/~ uuid"}.
#' If a log already carries its own \code{check_binding}, existing values are kept and only the
#' missing ones are filled.
#'
#' @param list_of_log A list containing one or more log data frames, and optionally the checked
#'   dataset under the name given by \code{dataset_name}.
#' @param dataset_name The name of the element holding the dataset to carry through to the
#'   output, or \code{NULL} if the list contains only logs. Default is \code{"checked_dataset"}.
#' @return A list with, optionally, \code{checked_dataset} (the untouched dataset) and
#'   \code{cleaning_log} (all logs combined, with \code{change_type}, \code{new_value} and
#'   \code{check_binding} added).
#' @export
create_combined_log <- function(
  list_of_log,
  dataset_name = "checked_dataset"
) {
  # ---- validate input ----
  if (!is.list(list_of_log) || is.data.frame(list_of_log)) {
    stop("`list_of_log` must be a list which should contain the logs.")
  }

  has_dataset <- !is.null(dataset_name)

  if (has_dataset && !(dataset_name %in% names(list_of_log))) {
    stop(paste0("'", dataset_name, "' cannot be found in `list_of_log`."))
  }
  if (!has_dataset && "checked_dataset" %in% names(list_of_log)) {
    warning(
      "`dataset_name` is NULL but `list_of_log` contains a 'checked_dataset' element, ",
      "so it will be treated as a log. Please check the parameter."
    )
  }
  if (!has_dataset && !("checked_dataset" %in% names(list_of_log))) {
    message(
      "No `dataset_name` provided; assuming the dataset is not in `list_of_log`."
    )
  }

  output <- list()
  if (has_dataset) {
    output[["checked_dataset"]] <- list_of_log[[dataset_name]]
  }

  # ---- keep only the log elements: drop the dataset, keep only data frames ----
  log_names <- setdiff(
    names(list_of_log),
    if (has_dataset) dataset_name else character(0)
  )
  is_df <- vapply(
    log_names,
    function(nm) is.data.frame(list_of_log[[nm]]),
    logical(1)
  )
  log_names <- log_names[is_df]

  # standard, empty cleaning-log shape used when there is nothing to combine
  empty_cleaning_log <- data.frame(
    uuid = character(0),
    old_value = character(0),
    question = character(0),
    issue = character(0),
    change_type = character(0),
    new_value = character(0),
    check_binding = character(0),
    stringsAsFactors = FALSE
  )

  if (length(log_names) == 0) {
    warning(
      "No log data frames found to combine; returning an empty cleaning_log."
    )
    output[["cleaning_log"]] <- empty_cleaning_log
    return(output)
  }

  message("Combining logs: ", paste(log_names, collapse = ", "))

  # ---- coerce every column to trimmed, non-scientific character so binding never
  #      fails on a type mismatch between logs ----
  logs_only <- lapply(list_of_log[log_names], function(lg) {
    dplyr::mutate(
      lg,
      dplyr::across(
        dplyr::everything(),
        ~ format(.x, scientific = FALSE, justify = "none", trim = TRUE)
      )
    )
  })

  combined <- dplyr::bind_rows(logs_only)

  if (nrow(combined) == 0) {
    warning("The logs contain no rows; returning an empty cleaning_log.")
    output[["cleaning_log"]] <- empty_cleaning_log
    return(output)
  }

  # ---- guarantee the columns the cleaning log relies on ----
  if (is.null(combined[["question"]])) {
    combined[["question"]] <- NA_character_
  }
  if (is.null(combined[["uuid"]])) {
    combined[["uuid"]] <- NA_character_
  }

  combined <- dplyr::mutate(
    combined,
    change_type = NA_character_,
    new_value = NA_character_
  )

  # ---- build / complete the check_binding key ----
  if (is.null(combined[["check_binding"]])) {
    combined <- dplyr::mutate(
      combined,
      check_binding = paste(question, uuid, sep = " ~/~ ")
    )
  } else {
    combined <- dplyr::mutate(
      combined,
      # the character coercion above turns a real NA into the string "NA",
      # so treat NA, "NA" and "" all as missing keys to fill
      check_binding = dplyr::case_when(
        is.na(check_binding) | check_binding %in% c("NA", "") ~
          paste(question, uuid, sep = " ~/~ "),
        TRUE ~ check_binding
      )
    )
  }

  output[["cleaning_log"]] <- combined
  output
}
