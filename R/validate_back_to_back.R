#' Validate Back-to-Back Interviews
#'
#' Flags interviews that follow one another too closely for the same enumerator.
#' When an enumerator's interviews are conducted one right after the other, with little
#' or no gap in between, it can indicate that interviews are being fabricated rather than
#' genuinely conducted with respondents.
#'
#' @details
#' For each enumerator the interviews are ordered chronologically and the gap between
#' consecutive interviews is measured. An interview is flagged when the gap before it is
#' shorter than the configured threshold (\code{threshold_hours} + \code{threshold_mins}),
#' including the case where it overlaps the previous interview (a negative gap, which is
#' physically impossible for a single enumerator).
#'
#' By default the gap is measured from the \emph{end} of the previous interview to the
#' \emph{start} of the current one (\code{gap_from = "end"}). If end times are unreliable,
#' set \code{gap_from = "start"} to measure start-to-start spacing instead.
#'
#' This signal is less reliable for remote (phone) data collection, where enumerators can
#' legitimately line up calls back-to-back. It is most useful when combined with other
#' checks such as below-average interview duration and repeated logical inconsistencies in
#' responses. Treat the log as a review queue, not an automatic rejection.
#'
#' @param dataset A dataframe or a list containing a dataframe named \code{checked_dataset}.
#' @param uuid_column The name of the column containing the unique identifier. Default is \code{"_uuid"}.
#' @param enumerator_column The name of the column identifying the enumerator. Default is \code{"username"}.
#' @param start_column The name of the interview start timestamp column. Default is \code{"start"}.
#' @param end_column The name of the interview end timestamp column. Default is \code{"end"}.
#'   Only required when \code{gap_from = "end"}.
#' @param log_name The name of the log to create in the list. Default is \code{"back_to_back_log"}.
#' @param threshold_hours Numeric. Hours component of the minimum acceptable gap. Default is \code{0}.
#' @param threshold_mins Numeric. Minutes component of the minimum acceptable gap. Default is \code{10}.
#'   The two components are added together; gaps shorter than this total are flagged.
#' @param gap_from Either \code{"end"} (default) to measure from the previous interview's end,
#'   or \code{"start"} to measure from the previous interview's start.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of the dataset is removed
#'   before validation. ONA exports include a label/description row immediately after the header
#'   that should not be treated as survey data.
#' @return A list containing the original dataset and the new log dataframe.
#' @export
validate_back_to_back <- function(
  dataset,
  uuid_column = "_uuid",
  enumerator_column = "username",
  start_column = "start",
  end_column = "end",
  log_name = "back_to_back_log",
  threshold_hours = 0,
  threshold_mins = 10,
  gap_from = c("end", "start"),
  skip_label_row = TRUE
) {
  gap_from <- match.arg(gap_from)

  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list")
  }

  df <- dataset[["checked_dataset"]]

  required_cols <- c(uuid_column, enumerator_column, start_column)
  if (gap_from == "end") {
    required_cols <- c(required_cols, end_column)
  }
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0) {
    msg <- paste0(
      "Cannot find the following column(s) in the dataset: ",
      paste(missing_cols, collapse = ", ")
    )
    stop(msg)
  }

  threshold_secs <- threshold_hours * 3600 + threshold_mins * 60
  threshold_label <- paste0(round(threshold_secs / 60, 1), " min")

  # Skip the ONA label/description row (first row after header)
  if (skip_label_row && nrow(df) > 0) {
    df <- df[-1, , drop = FALSE]
  }

  # Parse a timestamp column to POSIXct. Handles POSIXct input and ISO 8601 /
  # space-separated character strings. The timezone offset is dropped: differences
  # within a single enumerator's day are unaffected by a constant offset.
  parse_dt <- function(x) {
    if (inherits(x, c("POSIXct", "POSIXt"))) {
      return(as.POSIXct(x))
    }
    x_chr <- as.character(x)
    pattern <- "^.*?([0-9]{4}-[0-9]{2}-[0-9]{2})[T ]([0-9]{2}:[0-9]{2}(?::[0-9]{2})?).*$"
    has_dt <- grepl(pattern, x_chr, perl = TRUE)
    core <- rep(NA_character_, length(x_chr))
    core[has_dt] <- sub(pattern, "\\1 \\2", x_chr[has_dt], perl = TRUE)
    # Pad missing seconds (YYYY-MM-DD HH:MM -> add :00)
    core <- ifelse(!is.na(core) & nchar(core) == 16, paste0(core, ":00"), core)
    suppressWarnings(
      as.POSIXct(core, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
    )
  }

  start_dt <- parse_dt(df[[start_column]])
  end_dt <- if (gap_from == "end") parse_dt(df[[end_column]]) else start_dt

  if (nrow(df) > 0 && all(is.na(start_dt))) {
    warning(
      "Could not parse any value in '",
      start_column,
      "'. Check the column format (expected an ISO 8601 datetime or POSIXct)."
    )
  }

  work <- data.frame(
    .uuid = as.character(df[[uuid_column]]),
    .enum = trimws(as.character(df[[enumerator_column]])),
    .start = start_dt,
    .end = end_dt,
    .start_raw = as.character(df[[start_column]]),
    stringsAsFactors = FALSE
  )

  log <- work %>%
    dplyr::filter(!is.na(.start) & !is.na(.enum) & .enum != "") %>%
    dplyr::arrange(.enum, .start) %>%
    dplyr::group_by(.enum) %>%
    dplyr::mutate(
      prev_uuid = dplyr::lag(.uuid),
      prev_ref = if (gap_from == "end") {
        dplyr::lag(.end)
      } else {
        dplyr::lag(.start)
      },
      gap_secs = as.numeric(difftime(.start, prev_ref, units = "secs"))
    ) %>%
    dplyr::ungroup() %>%
    dplyr::filter(!is.na(gap_secs) & gap_secs < threshold_secs) %>%
    dplyr::mutate(
      gap_mins = round(gap_secs / 60, 1),
      ref_word = if (gap_from == "end") "ended" else "started",
      issue = ifelse(
        gap_secs < 0,
        paste0(
          "Overlapping interviews: this interview by enumerator '",
          .enum,
          "' starts before the previous one (uuid ",
          prev_uuid,
          ") ended, by ",
          abs(gap_mins),
          " min - possible fabrication"
        ),
        paste0(
          "Back-to-back interview: started ",
          gap_mins,
          " min after enumerator '",
          .enum,
          "' ",
          ref_word,
          " the previous interview (uuid ",
          prev_uuid,
          "); below the ",
          threshold_label,
          " threshold - possible fabrication"
        )
      ),
      question = start_column
    ) %>%
    dplyr::select(
      uuid = ".uuid",
      old_value = ".start_raw",
      question = "question",
      issue = "issue"
    )

  # Convert old_value to character to ensure consistency across logs if combined
  log$old_value <- as.character(log$old_value)

  dataset[[log_name]] <- log
  return(dataset)
}
