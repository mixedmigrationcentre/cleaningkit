#' Read Raw Main Dataset
#'
#' Reads the main raw dataset from an Excel file, converts date and datetime
#' columns based on the Kobo survey definition, and converts integer/decimal
#' columns to numeric.
#'
#' @param filename Path to the Excel file containing the raw data.
#' @param kobo_survey A dataframe containing the Kobo survey sheet (used for
#'   identifying date and numeric columns).
#' @param extra_date_cols Optional character vector of additional date column
#'   names to convert (default is NULL). These are appended to the auto-detected
#'   "today" and "date" type columns from the survey.
#' @param extra_datetime_cols Optional character vector of additional datetime
#'   column names to convert (default is NULL). These are appended to the
#'   auto-detected "start", "end", and "datetime" columns and "_submission_time".
#' @param sheet Sheet number or name to read from the Excel file (default is 1).
#' @return A dataframe with dates and datetimes converted, and numeric columns cast to numeric.
#' @export
read_raw_data <- function(
  filename,
  kobo_survey,
  extra_date_cols = NULL,
  extra_datetime_cols = NULL,
  sheet = 1
) {
  df <- readxl::read_excel(filename, sheet = sheet, col_types = "text")
  cat(crayon::green(paste0(
    "--> RAW --> ",
    filename,
    " --> ",
    nrow(df),
    " entries, ",
    ncol(df),
    " columns \n"
  )))

  # --- Auto-detect date and datetime columns from kobo_survey ---
  cat(crayon::green("--> convert dates \n"))
  # Date columns: survey types "today" and "date"
  cols_date <- c(
    kobo_survey$name[kobo_survey$type %in% c("today", "date")],
    extra_date_cols
  )
  cols_date <- intersect(cols_date, colnames(df))

  if (length(cols_date) > 0) {
    df <- df %>%
      mutate_at(
        cols_date,
        ~ dplyr::case_when(
          is.na(.) ~ NA_character_,
          stringr::str_detect(., "^[0-9]{4}-[0-9]{2}-[0-9]{2}") ~ as.character(
            .
          ),
          TRUE ~ as.character(as.Date(suppressWarnings(openxlsx::convertToDate(as.numeric(
            .
          )))))
        )
      )
  }

  # --- Convert datetime columns ---
  # Datetime columns: survey types "start", "end", "datetime"
  cols_datetime <- c(
    kobo_survey$name[kobo_survey$type %in% c("start", "end", "datetime")],
    "_submission_time",
    extra_datetime_cols
  )
  cols_datetime <- intersect(cols_datetime, colnames(df))

  if (length(cols_datetime) > 0) {
    df <- df %>%
      mutate_at(
        cols_datetime,
        ~ dplyr::case_when(
          is.na(.) ~ NA_character_,
          stringr::str_detect(., "^[0-9]{4}-[0-9]{2}-[0-9]{2}") ~ as.character(
            .
          ),
          TRUE ~ as.character(suppressWarnings(openxlsx::convertToDateTime(as.numeric(
            .
          ))))
        )
      )
  }

  # --- Convert numeric columns ---
  cat(crayon::green("--> convert integer columns to numeric \n"))
  cols_numeric <- get_cols_numeric(kobo_survey)
  df <- df %>%
    mutate_at(intersect(cols_numeric, colnames(df)), as.numeric)

  return(df)
}
