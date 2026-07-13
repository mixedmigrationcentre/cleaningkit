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
#' @param tool_survey XLSForm survey sheet dataframe. Must contain at least
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
  tool_survey,
  uuid_column = "_uuid",
  enumerator_column = "username",
  idnk_value = "Don't know",
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
  if (!all(c("name", "type") %in% names(tool_survey))) {
    stop("'tool_survey' must contain 'name' and 'type' columns.")
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
  type_map <- stats::setNames(
    as.character(tool_survey$type),
    as.character(tool_survey$name)
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
      typ <- type_map[col]
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

  # ---- convert to lowercase character; drop all-NA cols; replace NA -> "na" ----
  df_work <- as.data.frame(
    lapply(df_work, function(x) tolower(as.character(x))),
    stringsAsFactors = FALSE
  )
  all_na <- vapply(df_work, function(x) all(is.na(x) | x == "na"), logical(1))
  df_work <- df_work[, !all_na, drop = FALSE]
  df_work[is.na(df_work)] <- "na"

  # ---- Gower distance computed per enumerator ----
  # Only surveys from the same enumerator are compared. Cross-enumerator
  # similarity is irrelevant for fraud detection; we only care whether one
  # enumerator is copying their own surveys.
  total_cols <- ncol(df_work)

  # For enumerators with only one survey there is nothing to compare —
  # we record NA so they can be excluded from the flagged set cleanly.
  enumerator_groups <- if (!is.null(enum_vals)) {
    enum_vals
  } else {
    rep("__all__", nrow(df_work))
  }

  closest_dist <- rep(NA_real_, nrow(df_work))
  closest_idx <- rep(NA_integer_, nrow(df_work))

  for (grp in unique(enumerator_groups)) {
    grp_rows <- which(enumerator_groups == grp)
    if (length(grp_rows) < 2) {
      next
    } # only one survey for this enumerator

    df_grp <- df_work[grp_rows, , drop = FALSE]

    # drop columns that are constant within this enumerator's surveys
    # (Gower handles them but warnConst suppresses the noise)
    df_grp <- as.data.frame(
      lapply(df_grp, function(x) factor(as.character(x))),
      stringsAsFactors = TRUE
    )

    gower_mat <- as.matrix(cluster::daisy(
      df_grp,
      metric = "gower",
      warnBin = FALSE,
      warnAsym = FALSE,
      warnConst = FALSE
    ))

    for (local_i in seq_along(grp_rows)) {
      global_i <- grp_rows[local_i]
      dists <- gower_mat[local_i, ]
      dists[local_i] <- NA_real_ # exclude self
      best_local <- which.min(dists)
      closest_dist[global_i] <- dists[best_local]
      closest_idx[global_i] <- grp_rows[best_local]
    }
  }

  num_diff <- round(closest_dist * total_cols)

  # ---- build summary frame ----
  # Surveys with no within-enumerator peer get NA num_diff and are excluded
  # from flagging unless return_all_results = TRUE.
  summary_df <- data.frame(
    uuid = uuids,
    enumerator = if (!is.null(enum_vals)) enum_vals else NA_character_,
    id_most_similar_survey = ifelse(
      is.na(closest_idx),
      NA_character_,
      uuids[closest_idx]
    ),
    num_cols_not_na = rowSums(df_work != "na"),
    total_columns_compared = total_cols,
    num_cols_idnk = rowSums(df_work == tolower(idnk_value)),
    number_different_columns = num_diff,
    stringsAsFactors = FALSE
  )
  summary_df <- summary_df[
    order(
      is.na(summary_df$number_different_columns),
      summary_df$number_different_columns,
      summary_df$uuid
    ),
  ]

  flagged_df <- if (return_all_results) {
    summary_df
  } else {
    summary_df[
      !is.na(summary_df$number_different_columns) &
        summary_df$number_different_columns <= threshold,
    ]
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
    issue_text <- dplyr::case_when(
      is.na(flagged_df$number_different_columns) ~
        paste0(
          "Only survey for enumerator",
          if (!is.null(enum_vals)) {
            paste0(" '", flagged_df$enumerator, "'")
          } else {
            ""
          },
          "; no within-enumerator peer to compare"
        ),
      flagged_df$number_different_columns <= threshold ~
        paste0(
          "Possible duplicate within enumerator",
          if (!is.null(enum_vals)) {
            paste0(" '", flagged_df$enumerator, "'")
          } else {
            ""
          },
          ": only ",
          flagged_df$number_different_columns,
          " of ",
          flagged_df$total_columns_compared,
          " columns differ from survey ",
          flagged_df$id_most_similar_survey,
          " \u2014 threshold is ",
          threshold
        ),
      TRUE ~
        paste0(
          "Similar survey found within enumerator",
          if (!is.null(enum_vals)) {
            paste0(" '", flagged_df$enumerator, "'")
          } else {
            ""
          },
          " (",
          flagged_df$number_different_columns,
          " differing columns from survey ",
          flagged_df$id_most_similar_survey,
          ")"
        )
    )

    binding <- dplyr::case_when(
      is.na(flagged_df$id_most_similar_survey) ~
        paste0("soft_duplicate ~/~ solo ~/~ ", flagged_df$uuid),
      flagged_df$uuid < flagged_df$id_most_similar_survey ~
        paste0(
          "soft_duplicate ~/~ ",
          flagged_df$uuid,
          " ~/~ ",
          flagged_df$id_most_similar_survey
        ),
      TRUE ~
        paste0(
          "soft_duplicate ~/~ ",
          flagged_df$id_most_similar_survey,
          " ~/~ ",
          flagged_df$uuid
        )
    )

    log <- data.frame(
      uuid = flagged_df$uuid,
      old_value = as.character(flagged_df$number_different_columns),
      question = "number_different_columns",
      issue = issue_text,
      # Both surveys in a pair share the same binding (lexicographic min ~/~ max)
      # so they get the same colour in the review workbook.
      check_binding = binding,
      stringsAsFactors = FALSE
    )
  }

  dataset[[log_name]] <- log
  return(dataset)
}


#' Validate Duplicate Answers for Specific Questions Per Enumerator
#'
#' For each question in \code{questions_to_check}, groups surveys by enumerator
#' and flags any answer value that appears in more than one of that enumerator's
#' surveys. Only questions where at least one duplicate is found are reported.
#' All surveys that share the same duplicated answer for the same question get
#' an identical \code{check_binding} so they are coloured as a group in the
#' review workbook.
#'
#' @details
#' This is complementary to \code{validate_duplicates()}: where that function
#' uses Gower distance to detect globally similar surveys, this function
#' pinpoints specific questions (e.g. a destination country, a landmark, a
#' journey start point) that should vary between respondents but are suspiciously
#' repeated within one enumerator's workload.
#'
#' A common fraud pattern is an enumerator copying one answer across many
#' records. Passing \code{questions_to_check = c("Q41", "Q59", "Q13")} will
#' independently check each question; only those that are actually duplicated
#' produce log rows.
#'
#' Blank and \code{NA} values are never treated as duplicates — only non-empty
#' answers are compared, so unanswered questions do not generate false positives.
#'
#' @param dataset A dataframe or a list containing a dataframe named
#'   \code{checked_dataset}.
#' @param questions_to_check A character vector of column names to check for
#'   duplicate answers within each enumerator's surveys.
#' @param uuid_column Name of the unique-identifier column. Default \code{"_uuid"}.
#' @param enumerator_column Name of the enumerator column used to group surveys.
#'   Default \code{"username"}.
#' @param log_name Name of the log element in the returned list.
#'   Default \code{"duplicate_questions_log"}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of
#'   the dataset is removed before validation. ONA exports include a
#'   label/description row immediately after the header that must not be treated
#'   as a survey record.
#'
#' @return A list containing:
#'   \item{checked_dataset}{The original dataset, unchanged.}
#'   \item{<log_name>}{A dataframe with columns \code{uuid},
#'     \code{old_value} (the duplicated answer),
#'     \code{question} (the column name),
#'     \code{issue}, and \code{check_binding}. One row per survey per flagged
#'     question. Empty (zero rows) if no duplicates are found.}
#' @export
validate_duplicate_questions <- function(
  dataset,
  questions_to_check,
  uuid_column = "_uuid",
  enumerator_column = "username",
  log_name = "duplicate_questions_log",
  skip_label_row = TRUE
) {
  # ---- normalise input ----
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list.")
  }

  df <- dataset[["checked_dataset"]]

  if (!(uuid_column %in% names(df))) {
    stop(paste0("Cannot find '", uuid_column, "' in the names of the dataset."))
  }
  if (!(enumerator_column %in% names(df))) {
    stop(paste0(
      "Cannot find '",
      enumerator_column,
      "' in the names of the dataset."
    ))
  }
  if (!is.character(questions_to_check) || length(questions_to_check) == 0) {
    stop(
      "`questions_to_check` must be a non-empty character vector of column names."
    )
  }

  missing_qs <- setdiff(questions_to_check, names(df))
  if (length(missing_qs) > 0) {
    stop(paste0(
      "The following question(s) were not found in the dataset: ",
      paste(missing_qs, collapse = ", ")
    ))
  }

  # ---- drop ONA label row ----
  if (skip_label_row && nrow(df) > 0) {
    df <- df[-1, , drop = FALSE]
  }

  if (nrow(df) == 0) {
    warning("Dataset has no records after dropping the label row.")
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

  uuids <- as.character(df[[uuid_column]])
  enums <- trimws(as.character(df[[enumerator_column]]))

  # ---- check each question independently ----
  log_parts <- lapply(questions_to_check, function(q) {
    values <- trimws(as.character(df[[q]]))

    # collect one log row per survey per (enumerator, duplicated value) group
    rows <- lapply(unique(enums[enums != "" & !is.na(enums)]), function(enum) {
      enum_idx <- which(enums == enum)
      enum_vals <- values[enum_idx]
      enum_uuids <- uuids[enum_idx]

      # find answer values that appear more than once (ignore blank / NA)
      val_counts <- table(enum_vals[
        !is.na(enum_vals) & enum_vals != "" & enum_vals != "NA"
      ])
      dup_vals <- names(val_counts[val_counts > 1])

      if (length(dup_vals) == 0) {
        return(NULL)
      }

      do.call(
        rbind,
        lapply(dup_vals, function(v) {
          matched_uuids <- enum_uuids[!is.na(enum_vals) & enum_vals == v]
          n_surveys <- length(matched_uuids)

          # all surveys sharing this (question, enumerator, value) get one binding
          binding <- paste0(
            "dup_q ~/~ ",
            q,
            " ~/~ ",
            enum,
            " ~/~ ",
            v
          )

          data.frame(
            uuid = matched_uuids,
            old_value = v,
            question = q,
            issue = paste0(
              "Duplicate answer for '",
              q,
              "' within enumerator '",
              enum,
              "': value '",
              v,
              "' appears in ",
              n_surveys,
              " surveys"
            ),
            check_binding = binding,
            stringsAsFactors = FALSE
          )
        })
      )
    })

    do.call(rbind, rows)
  })

  log <- do.call(rbind, log_parts)

  if (is.null(log) || nrow(log) == 0) {
    log <- data.frame(
      uuid = character(0),
      old_value = character(0),
      question = character(0),
      issue = character(0),
      check_binding = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    rownames(log) <- NULL
    log <- log[order(log$question, log$check_binding, log$uuid), ]
  }

  dataset[[log_name]] <- log
  return(dataset)
}
