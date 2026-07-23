#' Validate Outliers in Integer and Numeric Columns
#'
#' Detects statistical outliers across all integer/numeric columns in the dataset
#' (or a user-specified subset), using two complementary methods:
#' \enumerate{
#'   \item \strong{Normal distribution} — flags any value more than
#'     \code{strongness_factor} standard deviations from the column mean.
#'   \item \strong{Log distribution} — applies \code{log(x + 1)} first, then
#'     applies the same z-score test. This catches outliers in right-skewed
#'     variables (e.g. income, journey duration, number of children) that would
#'     be missed by the normal check.
#' }
#' A record is flagged once per method per column. Both flags for the same record
#' share a \code{check_binding} so they are coloured as one group in the review
#' workbook.
#'
#' @details
#' \strong{Column selection} (in order of priority):
#' \enumerate{
#'   \item If \code{columns_to_check} is supplied, only those columns are tested.
#'   \item If \code{tool_survey} is supplied, the \code{integer}-type columns
#'     found there (excluding common metadata columns) are used.
#'   \item Otherwise all columns that are \code{integer} or \code{numeric} after
#'     \code{type.convert()} are used.
#' }
#'
#' \strong{Columns automatically excluded:}
#' \itemize{
#'   \item The uuid column.
#'   \item Select-multiple binary sub-columns (detected by \code{sm_separator}).
#'   \item Any column in \code{columns_to_skip}.
#'   \item Columns starting with \code{"_"} or \code{"X"} (ONA system columns).
#'   \item Columns with fewer than \code{min_unique_values} distinct non-missing
#'     values (avoids flagging binary or ordinal scales).
#' }
#'
#' @param dataset A dataframe or a list containing a dataframe named
#'   \code{checked_dataset}.
#' @param uuid_column Name of the uuid column. Default \code{"_uuid"}.
#' @param log_name Name of the log element in the returned list. Default
#'   \code{"outlier_log"}.
#' @param columns_to_check Optional character vector of specific column names to
#'   check. When supplied, only these columns are checked and \code{tool_survey}
#'   auto-detection is ignored. Default \code{NULL} (auto-detect).
#' @param tool_survey Optional XLSForm survey sheet dataframe. When provided,
#'   integer-type columns are identified from it rather than by R class alone,
#'   which is more reliable when the dataset was read as all-character (e.g. via
#'   \code{readxl::read_excel(..., col_types = "text")}). Must contain \code{name}
#'   and \code{type} columns. Default \code{NULL}.
#' @param strongness_factor Numeric. Number of standard deviations from the mean
#'   beyond which a value is considered an outlier. Higher = stricter. Default
#'   \code{3}.
#' @param min_unique_values Integer. Columns with fewer distinct non-missing
#'   values than this threshold are skipped (avoids false positives on binary or
#'   small ordinal scales). Default \code{5}.
#' @param remove_sm_binary Logical. If \code{TRUE} (the default), select-multiple
#'   binary sub-columns (detected by \code{sm_separator}) are excluded from
#'   checking — they only ever contain 0/1 and are not meaningful for outlier
#'   detection.
#' @param sm_separator Separator between a select-multiple parent column name and
#'   its binary sub-columns. Default \code{"/"} (ONA export style).
#' @param columns_to_skip Optional character vector of column names to always
#'   exclude, even when auto-detecting. Useful for computed or metadata columns
#'   that happen to be numeric. Default \code{NULL}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of
#'   the dataset is removed before validation. ONA exports include a
#'   label/description row immediately after the header that must not be treated
#'   as survey data (it would otherwise corrupt the mean and SD).
#'
#' @return A list containing:
#'   \item{checked_dataset}{The original dataset, unchanged.}
#'   \item{<log_name>}{A dataframe with columns \code{uuid}, \code{old_value},
#'     \code{question}, \code{issue}, and \code{check_binding}. One row per
#'     (record × column × method) flagged. \code{issue} is either
#'     \code{"outlier (normal distribution)"} or \code{"outlier (log distribution)"}.}
#' @export
validate_outliers <- function(
  dataset,
  uuid_column = "_uuid",
  log_name = "outlier_log",
  columns_to_check = NULL,
  tool_survey = NULL,
  strongness_factor = 3,
  min_unique_values = 5,
  remove_sm_binary = TRUE,
  sm_separator = "/",
  columns_to_skip = NULL,
  skip_label_row = TRUE
) {
  # ---- normalise input ----
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list.")
  }

  df_full <- dataset[["checked_dataset"]]

  if (!(uuid_column %in% names(df_full))) {
    stop(paste0("Cannot find '", uuid_column, "' in the names of the dataset."))
  }

  # ---- drop ONA label row ----
  if (skip_label_row && nrow(df_full) > 0) {
    df <- df_full[-1, , drop = FALSE]
  } else {
    df <- df_full
  }

  if (nrow(df) == 0) {
    warning("Dataset has no records after dropping the label row.")
    dataset[[log_name]] <- .empty_outlier_log()
    return(dataset)
  }

  uuids <- as.character(df[[uuid_column]])

  # ---- coerce all columns to their natural types for numeric detection ----
  df_converted <- suppressWarnings(
    utils::type.convert(df, as.is = TRUE, na.strings = c("", " ", "NA"))
  )

  # ---- detect select-multiple binary sub-columns to exclude ----
  all_cols <- names(df_converted)
  sm_sub_cols <- character(0)
  if (remove_sm_binary) {
    sm_sub_cols <- all_cols[
      vapply(
        all_cols,
        function(col) {
          parts <- strsplit(col, sm_separator, fixed = TRUE)[[1]]
          if (length(parts) < 2) {
            return(FALSE)
          }
          parent <- paste(parts[-length(parts)], collapse = sm_separator)
          parent %in% all_cols
        },
        logical(1)
      )
    ]
  }

  # ---- always-exclude set ----
  always_exclude <- unique(c(
    uuid_column,
    sm_sub_cols,
    columns_to_skip
  ))

  # ---- determine which columns to check ----
  if (!is.null(columns_to_check)) {
    # user-specified: validate they exist and are not excluded
    missing_cols <- setdiff(columns_to_check, names(df_converted))
    if (length(missing_cols) > 0) {
      warning(paste0(
        "The following columns_to_check were not found and will be skipped: ",
        paste(missing_cols, collapse = ", ")
      ))
    }
    cols_to_test <- intersect(columns_to_check, names(df_converted))
    cols_to_test <- setdiff(cols_to_test, always_exclude)
  } else if (!is.null(tool_survey)) {
    # tool_survey-based: use integer columns from the survey sheet
    if (!all(c("name", "type") %in% names(tool_survey))) {
      stop("'tool_survey' must contain 'name' and 'type' columns.")
    }
    # exclude common metadata column name patterns
    meta_patterns <- "enumerator|_instance_|_index|__index|submission|deviceid|simserial|phonenumber"
    integer_cols <- tool_survey$name[
      tool_survey$type == "integer" &
        !grepl(meta_patterns, tool_survey$name, ignore.case = TRUE)
    ]
    # supplement with any numeric columns detected by type.convert (catches recoded vars)
    r_numeric <- names(df_converted)[
      vapply(
        df_converted,
        function(x) is.numeric(x) || is.integer(x),
        logical(1)
      )
    ]
    cols_to_test <- unique(c(integer_cols, r_numeric))
    cols_to_test <- intersect(cols_to_test, names(df_converted))
    cols_to_test <- setdiff(cols_to_test, always_exclude)
    # also exclude ONA system columns (start with "_" or "X")
    cols_to_test <- cols_to_test[
      !grepl("^[_X]", cols_to_test)
    ]
  } else {
    # auto: all numeric/integer columns detected by type.convert
    cols_to_test <- names(df_converted)[
      vapply(
        df_converted,
        function(x) is.numeric(x) || is.integer(x),
        logical(1)
      )
    ]
    cols_to_test <- setdiff(cols_to_test, always_exclude)
    cols_to_test <- cols_to_test[!grepl("^[_X]", cols_to_test)]
  }

  if (length(cols_to_test) == 0) {
    warning("No numeric/integer columns found to check after filtering.")
    dataset[[log_name]] <- .empty_outlier_log()
    return(dataset)
  }

  message("validate_outliers: checking ", length(cols_to_test), " column(s).")

  # ---- outlier detection ----
  log_parts <- list()

  for (col in cols_to_test) {
    raw_vals <- suppressWarnings(as.numeric(df_converted[[col]]))

    # finite, non-missing values only for statistics
    finite_vals <- raw_vals[!is.na(raw_vals) & is.finite(raw_vals)]

    # skip columns with too few unique values (binary / small ordinal)
    if (length(unique(finite_vals)) < min_unique_values) {
      next
    }

    col_mean <- mean(finite_vals)
    col_sd <- stats::sd(finite_vals)

    if (is.na(col_sd) || col_sd == 0) {
      next
    } # constant column — no outliers possible

    # -- CHECK A: normal distribution (z-score) --
    z_scores <- abs(raw_vals - col_mean) / col_sd
    outlier_a <- !is.na(z_scores) &
      is.finite(z_scores) &
      z_scores > strongness_factor

    if (any(outlier_a)) {
      log_parts[[paste0(col, "__normal")]] <- data.frame(
        uuid = uuids[outlier_a],
        old_value = as.character(raw_vals[outlier_a]),
        question = col,
        issue = "outlier (normal distribution)",
        check_binding = paste0("outlier ~/~ ", uuids[outlier_a]),
        stringsAsFactors = FALSE
      )
    }

    # -- CHECK B: log distribution (log(x + 1) z-score) --
    log_vals <- suppressWarnings(log(raw_vals + 1))
    finite_log <- log_vals[!is.na(log_vals) & is.finite(log_vals)]

    if (length(unique(finite_log)) < min_unique_values) {
      next
    }

    log_mean <- mean(finite_log)
    log_sd <- stats::sd(finite_log)

    if (is.na(log_sd) || log_sd == 0) {
      next
    }

    z_log <- abs(log_vals - log_mean) / log_sd
    outlier_b <- !is.na(z_log) & is.finite(z_log) & z_log > strongness_factor

    if (any(outlier_b)) {
      log_parts[[paste0(col, "__log")]] <- data.frame(
        uuid = uuids[outlier_b],
        old_value = as.character(raw_vals[outlier_b]),
        question = col,
        issue = "outlier (log distribution)",
        check_binding = paste0("outlier ~/~ ", uuids[outlier_b]),
        stringsAsFactors = FALSE
      )
    }
  }

  # ---- assemble log ----
  if (length(log_parts) == 0) {
    log <- .empty_outlier_log()
  } else {
    log <- do.call(rbind, log_parts)
    rownames(log) <- NULL

    # Deduplicate on uuid + question: if the same value was flagged by both
    # normal and log distribution, keep only one row. Prefer the log
    # distribution flag when both fired (it is the more informative result —
    # extreme even after accounting for skew); fall back to normal otherwise.
    log[["._priority"]] <- ifelse(
      log$issue == "outlier (log distribution)",
      1L,
      2L
    )
    log <- log[order(log$uuid, log$question, log[["._priority"]]), ]
    log <- log[!duplicated(paste(log$uuid, log$question)), ]
    log[["._priority"]] <- NULL

    log <- log[order(log$question, log$uuid), ]
  }

  # convert old_value to character for consistency across combined logs
  log$old_value <- as.character(log$old_value)

  n_records <- length(unique(log$uuid))
  n_flags <- nrow(log)
  message(
    "validate_outliers: ",
    n_flags,
    " flag(s) across ",
    n_records,
    " record(s) in ",
    length(unique(log$question[log$question != ""])),
    " column(s)."
  )

  dataset[[log_name]] <- log
  return(dataset)
}

#' @keywords internal
.empty_outlier_log <- function() {
  data.frame(
    uuid = character(0),
    old_value = character(0),
    question = character(0),
    issue = character(0),
    check_binding = character(0),
    stringsAsFactors = FALSE
  )
}
