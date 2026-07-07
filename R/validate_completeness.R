#' Validate Dataset Completeness
#'
#' Checks the entire dataset (excluding metadata columns) and flags any records that have
#' fewer than a specified threshold of non-empty cells.
#'
#' @param dataset A dataframe or a list containing a dataframe named \code{checked_dataset}.
#' @param uuid_column The name of the column containing the unique identifier. Default is \code{"uuid"}.
#' @param log_name The name of the log to create in the list. Default is \code{"completeness_log"}.
#' @param min_content_cells The minimum number of cells that must contain content. Default is \code{100}.
#' @param metadata_cols A character vector of column names representing metadata to exclude from completeness calculation.
#' @return A list containing the original dataset and the new log dataframe.
#' @export
validate_completeness <- function(
  dataset,
  uuid_column = "uuid",
  log_name = "completeness_log",
  min_content_cells = 100,
  metadata_cols = c(
    "start",
    "end",
    "today",
    "deviceid",
    "username",
    "simserial",
    "phonenumber",
    "uuid",
    "_uuid",
    "id",
    "_id",
    "submission_time",
    "_submission_time",
    "index",
    "_index",
    "df_name"
  )
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

  # Exclude metadata columns
  cols_to_check <- setdiff(names(df), metadata_cols)
  df_sub <- df[, cols_to_check, drop = FALSE]

  # Vectorized check for non-empty content: not NA, not NaN, not blank/whitespace
  col_non_empty <- lapply(df_sub, function(x) {
    !is.na(x) & !is.nan(x) & trimws(as.character(x)) != ""
  })
  non_empty_count <- rowSums(do.call(cbind, col_non_empty), na.rm = TRUE)

  log <- df %>%
    dplyr::mutate(
      non_empty_count = non_empty_count,
      completeness_check = non_empty_count < min_content_cells
    ) %>%
    dplyr::filter(completeness_check) %>%
    dplyr::select(dplyr::all_of(c(uuid_column, "non_empty_count"))) %>%
    dplyr::mutate(
      question = "all_columns",
      issue = paste0(
        "Survey has fewer than ",
        min_content_cells,
        " cells with content"
      )
    ) %>%
    dplyr::rename(
      old_value = "non_empty_count",
      uuid = !!rlang::sym(uuid_column)
    )

  # Convert old_value to character to ensure consistency across logs if combined
  log$old_value <- as.character(log$old_value)

  dataset[[log_name]] <- log
  return(dataset)
}

#' Validate Refused Responses
#'
#' Checks the entire dataset and flags any records that have more than a specified
#' threshold of "Refused" responses.
#'
#' @param dataset A dataframe or a list containing a dataframe named \code{checked_dataset}.
#' @param uuid_column The name of the column containing the unique identifier. Default is \code{"uuid"}.
#' @param log_name The name of the log to create in the list. Default is \code{"refused_log"}.
#' @param max_refused The maximum allowable number of refused responses. Default is \code{6}.
#' @param refused_value The response value to flag as refused. Default is \code{"Refused"}.
#' @return A list containing the original dataset and the new log dataframe.
#' @export
validate_refused <- function(
  dataset,
  uuid_column = "uuid",
  log_name = "refused_log",
  max_refused = 6,
  refused_value = "Refused"
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

  # Vectorized check for "Refused" values (case-sensitive as specified, using trimws)
  col_refused <- lapply(df, function(x) {
    !is.na(x) & trimws(as.character(x)) == refused_value
  })
  refused_count <- rowSums(do.call(cbind, col_refused), na.rm = TRUE)

  log <- df %>%
    dplyr::mutate(
      refused_count = refused_count,
      refused_check = refused_count > max_refused
    ) %>%
    dplyr::filter(refused_check) %>%
    dplyr::select(dplyr::all_of(c(uuid_column, "refused_count"))) %>%
    dplyr::mutate(
      question = "all_columns",
      issue = paste0(
        "Survey has more than ",
        max_refused,
        " '",
        refused_value,
        "' responses"
      )
    ) %>%
    dplyr::rename(
      old_value = "refused_count",
      uuid = !!rlang::sym(uuid_column)
    )

  # Convert old_value to character to ensure consistency across logs if combined
  log$old_value <- as.character(log$old_value)

  dataset[[log_name]] <- log
  return(dataset)
}
