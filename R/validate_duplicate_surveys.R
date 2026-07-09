#' Validate Survey Similarities (Soft Duplicates)
#'
#' Detects suspiciously similar surveys by computing the Gower distance between
#' every pair of records and flagging any survey whose closest neighbour differs
#' in fewer than \code{threshold} columns. A low number of differing columns
#' suggests the enumerator may have duplicated or fabricated a response rather
#' than interviewing a distinct respondent.
#'
#' @details
#' The check works in five steps:
#' \enumerate{
#'   \item Metadata columns (start, end, today, deviceid, geopoint, …) and
#'     select-multiple binary sub-columns are dropped, keeping only the
#'     concatenated parent column.
#'   \item All remaining columns are converted to lowercase character and then
#'     to factor so Gower distance can handle mixed types.
#'   \item Columns that are entirely \code{NA} are removed; remaining \code{NA}s
#'     are replaced with the string \code{"NA"} so they are treated as a valid
#'     (unknown) category rather than missing.
#'   \item Gower distance is computed across all retained columns. For each
#'     survey the closest *other* survey (second-smallest distance, since
#'     distance to itself is always 0) is identified and the raw distance is
#'     converted to an approximate count of differing columns.
#'   \item Records whose closest-neighbour difference is at or below
#'     \code{threshold} are flagged.
#' }
#'
#' The log follows the same \code{uuid / old_value / question / issue /
#' check_binding} shape as all other \code{validate_*} functions so it can be
#' combined with \code{create_combined_log()} and coloured in
#' \code{create_cleaning_log()}. \code{check_binding} is set to
#' \code{"soft_duplicate ~/~ <uuid>"} for the flagged survey and the matching
#' pair survey so both rows share the same colour in the review workbook.
#'
#' @param dataset A dataframe or a list containing a dataframe named
#'   \code{checked_dataset}.
#' @param kobo_survey Kobo survey sheet dataframe. Must contain at least
#'   \code{name} and \code{type} columns.
#' @param uuid_column Name of the unique-identifier column. Default \code{"_uuid"}.
#' @param enumerator_column Name of the enumerator column. Used to annotate the
#'   log so reviewers can see which enumerator collected each flagged pair.
#'   Default \code{"username"}. Set to \code{NULL} to omit.
#' @param idnk_value The value used in the dataset for "I don't know" responses.
#'   The number of such responses per survey is reported in the log.
#'   Default \code{"idnk"}.
#' @param sm_separator Separator between a select-multiple parent column name and
#'   its binary sub-columns. Default \code{"/"} (ONA export style). Binary
#'   sub-columns are excluded from the comparison; only the concatenated parent
#'   is kept.
#' @param log_name Name of the log element in the returned list.
#'   Default \code{"soft_duplicate_log"}.
#' @param threshold Flag all surveys whose closest neighbour differs in at most
#'   this many columns. Default \code{7}.
#' @param return_all_results If \code{TRUE}, return a row for every survey (not
#'   only flagged ones). Useful for per-enumerator analysis. Default \code{FALSE}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of
#'   the dataset is removed before validation. ONA exports include a
#'   label/description row immediately after the header that must not be treated
#'   as a survey record.
#'
#' @return A list containing:
#'   \item{checked_dataset}{The original dataset, unchanged.}
#'   \item{<log_name>}{A dataframe with columns \code{uuid},
#'     \code{old_value} (number of differing columns),
#'     \code{question} (\code{"number_different_columns"}),
#'     \code{issue}, and \code{check_binding}.}
#' @export
validate_duplicates <- function(
  dataset,
  kobo_survey,
  uuid_column = "_uuid",
  enumerator_column = "username",
  idnk_value = "idnk",
  sm_separator = "/",
  log_name = "soft_duplicate_log",
  threshold = 7,
  return_all_results = FALSE,
  skip_label_row = TRUE
) {
  if (!requireNamespace("cluster", quietly = TRUE)) {
    stop(
      "The 'cluster' package is required for validate_duplicates(). ",
      "Install it with: install.packages('cluster')"
    )
  }

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
  if (!is.null(enumerator_column) && !(enumerator_column %in% names(df_full))) {
    warning(paste0(
      "'",
      enumerator_column,
      "' not found in the dataset; ",
      "enumerator will not be included in the log."
    ))
    enumerator_column <- NULL
  }
  if (!all(c("name", "type") %in% names(kobo_survey))) {
    stop("'kobo_survey' must contain 'name' and 'type' columns.")
  }

  # ---- drop label row ----
  if (skip_label_row && nrow(df_full) > 0) {
    df_full <- df_full[-1, , drop = FALSE]
  }

  if (nrow(df_full) < 2) {
    warning(
      "Dataset has fewer than 2 records after dropping the label row; nothing to compare."
    )
    dataset[[log_name]] <- data.frame(
      uuid = character(0),
      old_value = character(0),
      question = character(0),
      issue = character(0),
      check_binding = character(0),
      stringsAsFactors = FALSE
    )
    return(dataset)
  }

  # ---- store uuids and enumerator before any transformation ----
  uuids <- as.character(df_full[[uuid_column]])
  enum_vals <- if (!is.null(enumerator_column)) {
    as.character(df_full[[enumerator_column]])
  } else {
    NULL
  }

  # ---- detect select-multiple sub-columns to drop ----
  # Sub-columns follow the pattern <parent><sm_separator><choice>, e.g. Q5/food.
  # We keep only the parent (concatenated) column.
  all_cols <- names(df_full)
  sm_parents <- unique(unlist(lapply(all_cols, function(col) {
    # a sub-column contains exactly one separator and its left side is another column
    parts <- strsplit(col, sm_separator, fixed = TRUE)[[1]]
    if (length(parts) >= 2) {
      parent <- paste(parts[-length(parts)], collapse = sm_separator)
      if (parent %in% all_cols) parent else NA_character_
    } else {
      NA_character_
    }
  })))
  sm_parents <- sm_parents[!is.na(sm_parents)]
  sm_sub_cols <- all_cols[
    vapply(
      all_cols,
      function(col) {
        any(vapply(
          sm_parents,
          function(p) {
            startsWith(col, paste0(p, sm_separator)) && col != p
          },
          logical(1)
        ))
      },
      logical(1)
    )
  ]

  # ---- columns to drop: metadata types + sub-columns + uuid + enumerator ----
  types_to_remove <- c(
    "start",
    "end",
    "today",
    "deviceid",
    "date",
    "geopoint",
    "audit",
    "note",
    "calculate",
    "begin_group",
    "end_group",
    "begin_repeat",
    "end_repeat"
  )
  kobo_type_map <- stats::setNames(
    as.character(kobo_survey$type),
    as.character(kobo_survey$name)
  )

  always_drop <- c(
    uuid_column,
    if (!is.null(enumerator_column)) enumerator_column else character(0),
    sm_sub_cols
  )

  cols_to_keep <- vapply(
    all_cols,
    function(col) {
      if (col %in% always_drop) {
        return(FALSE)
      }
      typ <- kobo_type_map[col]
      if (!is.na(typ) && typ %in% types_to_remove) {
        return(FALSE)
      }
      if (startsWith(col, "X_") || startsWith(col, "_")) {
        return(FALSE)
      }
      if (grepl("^[[:punct:]]", col)) {
        return(FALSE)
      }
      TRUE
    },
    logical(1)
  )

  df_work <- df_full[, cols_to_keep, drop = FALSE]

  if (ncol(df_work) == 0) {
    warning("No columns remain after filtering; cannot compute distances.")
    dataset[[log_name]] <- data.frame(
      uuid = character(0),
      old_value = character(0),
      question = character(0),
      issue = character(0),
      check_binding = character(0),
      stringsAsFactors = FALSE
    )
    return(dataset)
  }

  # ---- convert to lowercase character ----
  df_work <- as.data.frame(
    lapply(df_work, function(x) tolower(as.character(x))),
    stringsAsFactors = FALSE
  )

  # ---- drop all-NA columns; replace remaining NA with "na" ----
  all_na <- vapply(df_work, function(x) all(is.na(x) | x == "na"), logical(1))
  df_work <- df_work[, !all_na, drop = FALSE]
  df_work[is.na(df_work)] <- "na"

  total_cols <- ncol(df_work)

  # ---- convert to factor for Gower distance ----
  df_work <- as.data.frame(
    lapply(df_work, factor),
    stringsAsFactors = TRUE
  )
  if (sum(is.na(df_work)) > 0) {
    stop(
      "NA values remain after conversion to factor; check the dataset for unexpected values."
    )
  }

  # ---- Gower distance ----
  gower_dist <- cluster::daisy(
    df_work,
    metric = "gower",
    warnBin = FALSE,
    warnAsym = FALSE,
    warnConst = FALSE
  )
  gower_mat <- as.matrix(gower_dist)

  # ---- for each survey: find closest *other* survey and number of differing cols ----
  n <- nrow(df_work)
  closest_dist <- numeric(n)
  closest_idx <- integer(n)

  for (i in seq_len(n)) {
    row_dists <- gower_mat[i, ]
    row_dists[i] <- NA_real_ # exclude self
    idx <- which.min(row_dists)
    closest_idx[i] <- idx
    closest_dist[i] <- row_dists[idx]
  }

  num_diff <- round(closest_dist * total_cols)

  # ---- build summary frame ----
  summary_df <- data.frame(
    uuid = uuids,
    enumerator = if (!is.null(enum_vals)) enum_vals else NA_character_,
    id_most_similar_survey = uuids[closest_idx],
    enumerator_most_similar = if (!is.null(enum_vals)) {
      enum_vals[closest_idx]
    } else {
      NA_character_
    },
    num_cols_not_na = rowSums(df_work != "na"),
    total_columns_compared = total_cols,
    num_cols_idnk = rowSums(df_work == tolower(idnk_value)),
    number_different_columns = num_diff,
    stringsAsFactors = FALSE
  )
  summary_df <- summary_df[
    order(summary_df$number_different_columns, summary_df$uuid),
  ]

  flagged_df <- if (return_all_results) {
    summary_df
  } else {
    summary_df[summary_df$number_different_columns <= threshold, ]
  }

  # ---- build log in validate_* shape ----
  if (nrow(flagged_df) == 0) {
    log <- data.frame(
      uuid = character(0),
      old_value = character(0),
      question = character(0),
      issue = character(0),
      check_binding = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    issue_text <- ifelse(
      flagged_df$number_different_columns <= threshold,
      paste0(
        "Possible duplicate: only ",
        flagged_df$number_different_columns,
        " of ",
        flagged_df$total_columns_compared,
        " columns differ from survey ",
        flagged_df$id_most_similar_survey,
        if (!is.null(enum_vals)) {
          paste0(
            " (enumerator: ",
            flagged_df$enumerator,
            "; similar survey enumerator: ",
            flagged_df$enumerator_most_similar,
            ")"
          )
        } else {
          ""
        },
        " — threshold is ",
        threshold
      ),
      paste0(
        "Similar survey found (",
        flagged_df$number_different_columns,
        " differing columns from survey ",
        flagged_df$id_most_similar_survey,
        ")"
      )
    )

    log <- data.frame(
      uuid = flagged_df$uuid,
      old_value = as.character(flagged_df$number_different_columns),
      question = "number_different_columns",
      issue = issue_text,
      # Both surveys in a pair share the same binding (lexicographic min ~/~ max)
      # so they get the same colour in the review workbook.
      check_binding = paste0(
        "soft_duplicate ~/~ ",
        ifelse(
          flagged_df$uuid < flagged_df$id_most_similar_survey,
          paste0(flagged_df$uuid, " ~/~ ", flagged_df$id_most_similar_survey),
          paste0(flagged_df$id_most_similar_survey, " ~/~ ", flagged_df$uuid)
        )
      ),
      stringsAsFactors = FALSE
    )
  }

  dataset[[log_name]] <- log
  return(dataset)
}
