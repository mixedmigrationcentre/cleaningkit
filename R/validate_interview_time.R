#' Validate Interview Time
#'
#' Checks that each interview was conducted at a plausible time of day and flags any
#' records that fall outside an acceptable window (for example, interviews recorded in
#' the middle of the night), which may suggest the data was fabricated or mis-recorded.
#'
#' The hour of the interview is taken from the interview start timestamp
#' (\code{time_column}). ONA exports this column as an ISO 8601 datetime such as
#' \code{"2023-05-12T09:34:21.000+03:00"}. The local wall-clock hour recorded in the
#' timestamp is used (the offset the enumerator's device recorded), so no timezone
#' conversion is applied. A record is flagged when its hour is earlier than
#' \code{earliest_hour} or at/after \code{latest_hour}.
#'
#' @param dataset A dataframe or a list containing a dataframe named \code{checked_dataset}.
#' @param uuid_column The name of the column containing the unique identifier. Default is \code{"_uuid"}.
#' @param time_column The name of the column holding the interview start timestamp.
#'   Default is \code{"start"}. Accepts an ISO 8601 character string (as ONA exports it)
#'   or a \code{POSIXct} column (as produced by \code{readxl} when it auto-parses dates).
#' @param log_name The name of the log to create in the list. Default is \code{"interview_time_log"}.
#' @param earliest_hour Integer 0-23. Interviews starting before this hour are flagged. Default is \code{5}.
#' @param latest_hour Integer 0-24. Interviews starting at or after this hour are flagged. Default is \code{22}.
#' @param flag_missing Logical. If \code{TRUE}, records whose time is missing or cannot be
#'   parsed are also flagged. Default is \code{FALSE}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of the dataset is removed
#'   before validation. ONA exports include a label/description row immediately after the header
#'   that should not be treated as survey data.
#' @return A list containing the original dataset and the new log dataframe.
#' @export
validate_interview_time <- function(
  dataset,
  uuid_column = "_uuid",
  time_column = "start",
  log_name = "interview_time_log",
  earliest_hour = 5,
  latest_hour = 22,
  flag_missing = FALSE,
  skip_label_row = TRUE
) {
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list")
  }

  df <- dataset[["checked_dataset"]]

  if (!(uuid_column %in% names(df))) {
    msg <- paste0("Cannot find ", uuid_column, " in the names of the dataset")
    stop(msg)
  }
  if (!(time_column %in% names(df))) {
    msg <- paste0("Cannot find ", time_column, " in the names of the dataset")
    stop(msg)
  }

  earliest_hour <- as.integer(earliest_hour)
  latest_hour <- as.integer(latest_hour)

  # Skip the ONA label/description row (first row after header)
  if (skip_label_row && nrow(df) > 0) {
    df <- df[-1, , drop = FALSE]
  }

  # Extract the recorded hour (0-23) from the start timestamp.
  # Handles POSIXct columns (readxl) and ISO 8601 character strings (raw ONA export).
  get_hour <- function(x) {
    if (inherits(x, c("POSIXct", "POSIXt"))) {
      return(as.integer(format(x, "%H")))
    }
    x_chr <- as.character(x)
    # Capture the hour digits that follow the "T" (or space) in a datetime string.
    pattern <- "^[^T ]*[T ]([0-9]{1,2}):.*$"
    has_time <- grepl(pattern, x_chr)
    hh <- rep(NA_integer_, length(x_chr))
    hh[has_time] <- as.integer(sub(pattern, "\\1", x_chr[has_time]))
    hh[!is.na(hh) & (hh < 0 | hh > 23)] <- NA_integer_
    hh
  }

  interview_hour <- get_hour(df[[time_column]])
  interview_time_value <- as.character(df[[time_column]])

  if (nrow(df) > 0 && all(is.na(interview_hour))) {
    warning(
      "Could not extract an hour from any value in '",
      time_column,
      "'. Check the column format (expected an ISO 8601 datetime or POSIXct)."
    )
  }

  log <- df %>%
    dplyr::mutate(
      interview_hour = interview_hour,
      interview_time_value = interview_time_value,
      interview_time_check = (flag_missing & is.na(interview_hour)) |
        (!is.na(interview_hour) &
          (interview_hour < earliest_hour | interview_hour >= latest_hour))
    ) %>%
    dplyr::filter(interview_time_check) %>%
    dplyr::select(dplyr::all_of(c(
      uuid_column,
      "interview_time_value",
      "interview_hour"
    ))) %>%
    dplyr::mutate(
      question = time_column,
      issue = ifelse(
        is.na(interview_hour),
        "Interview start time is missing or could not be parsed",
        paste0(
          "Interview conducted at ",
          sprintf("%02d:00", interview_hour),
          ", outside the plausible window of ",
          sprintf("%02d:00", earliest_hour),
          "-",
          sprintf("%02d:00", latest_hour),
          " (possible fabrication)"
        )
      )
    ) %>%
    dplyr::select(dplyr::all_of(c(
      uuid_column,
      "interview_time_value",
      "question",
      "issue"
    ))) %>%
    dplyr::rename(
      old_value = "interview_time_value",
      uuid = !!rlang::sym(uuid_column)
    )

  # Convert old_value to character to ensure consistency across logs if combined
  log$old_value <- as.character(log$old_value)

  # Tag with check_binding so the cleaning log can colour-group related rows
  log$check_binding <- paste("interview_time_check", log$uuid, sep = " ~/~ ")

  dataset[[log_name]] <- log
  return(dataset)
}
