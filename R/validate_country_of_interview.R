#' Validate Country of Interview
#'
#' Flags interviews for investigation where the country in which the interview was
#' conducted matches the respondent's country of nationality, or matches the country
#' where the respondent started their journey. In a mixed-migration survey the
#' respondent is expected to be on the move, so either of these matches is a possible
#' eligibility or data-quality problem worth reviewing (e.g. a respondent interviewed
#' in their own country, or who never crossed a border).
#'
#' By default the check compares:
#' \itemize{
#'   \item \code{Q13} - country where the interview is being conducted,
#'   \item \code{Q31} - country of nationality of the respondent,
#'   \item \code{Q41} - country where the respondent started their journey.
#' }
#' A record produces one log entry per matching field, so an interview can be flagged
#' for the nationality match, the journey-start match, or both. Comparisons are
#' case-insensitive and whitespace-trimmed; blank values are treated as unanswered and
#' never count as a match.
#'
#' @param dataset A dataframe or a list containing a dataframe named \code{checked_dataset}.
#' @param uuid_column The name of the column containing the unique identifier. Default is \code{"_uuid"}.
#' @param country_interview_col The name of the column for the country of interview. Default is \code{"Q13"}.
#' @param nationality_col The name of the column for the respondent's nationality. Default is \code{"Q31"}.
#' @param journey_start_col The name of the column for the country where the journey started. Default is \code{"Q41"}.
#' @param log_name The name of the log to create in the list. Default is \code{"country_of_interview_log"}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of the dataset is removed
#'   before validation. ONA exports include a label/description row immediately after the header
#'   that should not be treated as survey data.
#' @return A list containing the original dataset and the new log dataframe.
#' @export
validate_country_of_interview <- function(
  dataset,
  uuid_column = "_uuid",
  country_interview_col = "Q13",
  nationality_col = "Q31",
  journey_start_col = "Q41",
  log_name = "country_of_interview_log",
  skip_label_row = TRUE
) {
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list")
  }

  df <- dataset[["checked_dataset"]]

  required_cols <- c(
    uuid_column,
    country_interview_col,
    nationality_col,
    journey_start_col
  )
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0) {
    msg <- paste0(
      "Cannot find the following column(s) in the dataset: ",
      paste(missing_cols, collapse = ", ")
    )
    stop(msg)
  }

  # Skip the ONA label/description row (first row after header)
  if (skip_label_row && nrow(df) > 0) {
    df <- df[-1, , drop = FALSE]
  }

  # Normalise for comparison only: trim, blank -> NA, lower-case.
  normalise <- function(x) {
    x <- trimws(as.character(x))
    x[x == ""] <- NA_character_
    tolower(x)
  }

  country_interview <- normalise(df[[country_interview_col]])
  nationality <- normalise(df[[nationality_col]])
  journey_start <- normalise(df[[journey_start_col]])

  nationality_match <- !is.na(nationality) &
    !is.na(country_interview) &
    nationality == country_interview

  journey_match <- !is.na(journey_start) &
    !is.na(country_interview) &
    journey_start == country_interview

  # Build one log frame per condition, reporting the original (un-normalised) value.
  build_log <- function(mask, question_col, raw_values, issue_text) {
    df %>%
      dplyr::mutate(
        match_flag = mask,
        matched_value = raw_values
      ) %>%
      dplyr::filter(match_flag) %>%
      dplyr::select(dplyr::all_of(c(uuid_column, "matched_value"))) %>%
      dplyr::mutate(
        question = question_col,
        issue = issue_text
      ) %>%
      dplyr::rename(
        old_value = "matched_value",
        uuid = !!rlang::sym(uuid_column)
      )
  }

  log <- dplyr::bind_rows(
    build_log(
      nationality_match,
      nationality_col,
      as.character(df[[nationality_col]]),
      paste0(
        "Respondent nationality (",
        nationality_col,
        ") matches the country of interview (",
        country_interview_col,
        "); respondent may not be a migrant - investigate"
      )
    ),
    build_log(
      journey_match,
      journey_start_col,
      as.character(df[[journey_start_col]]),
      paste0(
        "Journey start country (",
        journey_start_col,
        ") matches the country of interview (",
        country_interview_col,
        "); respondent may not have crossed a border - investigate"
      )
    )
  )

  # Convert old_value to character to ensure consistency across logs if combined
  log$old_value <- as.character(log$old_value)

  # Tag with check_binding so the cleaning log can colour-group related rows.
  # Both nationality-match and journey-start-match rows for the same UUID
  # share a colour, making it easy for the reviewer to spot related flags.
  log$check_binding <- paste("country_of_interview_check", log$uuid, sep = " ~/~ ")

  dataset[[log_name]] <- log
  return(dataset)
}
