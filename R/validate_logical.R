#' Validate Multiple Logical Checks from a Checklist
#'
#' A wrapper around a single logical check that runs every row of a checklist
#' dataframe as its own check and collects the results into one or more logs.
#' Equivalent to calling a logical validator once per check and assembling the
#' results, but driven by a checklist so checks can be maintained outside the
#' code (e.g. in an Excel sheet).
#'
#' @details
#' Every row of \code{list_of_check} is evaluated as an R expression against the
#' dataset. Flagged records are written to a log with columns \code{uuid},
#' \code{old_value}, \code{question}, and \code{issue} — the same shape as all
#' other \code{validate_*} logs so they can be combined with
#' \code{create_combined_log()}.
#'
#' \code{columns_to_clean_column} may hold a comma-separated list of column
#' names (e.g. \code{"Q13, Q31"}). Each column produces one log row per flagged
#' record. If a check has no columns to clean, one row per flagged record is
#' still written with \code{question = check_id} and \code{old_value = NA}.
#'
#' When \code{bind_checks = TRUE} (the default), all per-check logs are stacked
#' into one dataframe stored under \code{log_name}. When \code{FALSE}, each
#' check's log is stored separately under its \code{check_id} value.
#'
#' @param dataset A dataframe or a list containing a dataframe named
#'   \code{checked_dataset}.
#' @param uuid_column Name of the uuid column. Default \code{"_uuid"}.
#' @param list_of_check A dataframe where each row defines one check. Must
#'   contain at minimum the columns named by \code{check_id_column},
#'   \code{check_to_perform_column}, and \code{description_column}.
#' @param check_id_column Column in \code{list_of_check} holding a unique
#'   identifier for each check (used as the log name when
#'   \code{bind_checks = FALSE}, and in the \code{issue} text).
#' @param check_to_perform_column Column holding the R expression to evaluate
#'   (as a character string). Must produce a logical vector when evaluated
#'   against the dataset.
#' @param columns_to_clean_column Column holding a comma-separated string of
#'   column names whose values should be recorded in the log for each flagged
#'   record. \code{NULL}, \code{NA}, or \code{""} means no specific columns
#'   are recorded (the check id is used as the question instead).
#' @param description_column Column holding a human-readable description of
#'   what the check is testing (written into the \code{issue} field).
#' @param log_name Name under which the combined log is stored in the returned
#'   list when \code{bind_checks = TRUE}. Default \code{"logical_log"}.
#' @param bind_checks Logical. If \code{TRUE} (the default), all per-check logs
#'   are stacked into one dataframe. If \code{FALSE}, each check's log is stored
#'   separately under its check id.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of
#'   the dataset is removed before validation. ONA exports include a
#'   label/description row immediately after the header that should not be
#'   treated as survey data.
#'
#' @return A list containing:
#'   \item{checked_dataset}{The original dataset with one logical flag column
#'     added per check (named after the check id, \code{TRUE} = flagged).}
#'   \item{<log_name> or <check_id>}{One log dataframe (bound or separate,
#'     depending on \code{bind_checks}).}
#' @export
validate_logical_with_list <- function(
  dataset,
  uuid_column = "_uuid",
  list_of_check,
  check_id_column,
  check_to_perform_column,
  columns_to_clean_column = NULL,
  description_column,
  log_name = "logical_log",
  bind_checks = TRUE,
  skip_label_row = TRUE
) {
  # ---- input validation ----
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list.")
  }
  if (!is.data.frame(list_of_check) || nrow(list_of_check) == 0) {
    stop("`list_of_check` must be a non-empty dataframe.")
  }
  required_cols <- c(
    check_id_column,
    check_to_perform_column,
    description_column
  )
  missing_cols <- setdiff(required_cols, names(list_of_check))
  if (length(missing_cols) > 0) {
    stop(paste0(
      "The following column(s) are missing from `list_of_check`: ",
      paste(missing_cols, collapse = ", ")
    ))
  }
  dupes <- list_of_check[[check_id_column]][
    duplicated(list_of_check[[check_id_column]])
  ]
  if (length(dupes) > 0) {
    stop(paste0(
      "Duplicate check id(s) found in '",
      check_id_column,
      "': ",
      paste(unique(dupes), collapse = ", ")
    ))
  }

  df <- dataset[["checked_dataset"]]

  if (!(uuid_column %in% names(df))) {
    stop(paste0("Cannot find '", uuid_column, "' in the dataset."))
  }

  if (skip_label_row && nrow(df) > 0) {
    df <- df[-1, , drop = FALSE]
  }

  # normalise columns_to_clean_column: if missing/blank, use a synthetic NA col
  has_cols_to_clean <- !is.null(columns_to_clean_column) &&
    !all(is.na(columns_to_clean_column)) &&
    !all(nchar(trimws(as.character(columns_to_clean_column))) == 0)

  if (!has_cols_to_clean) {
    list_of_check[["._cols_clean"]] <- NA_character_
    columns_to_clean_column <- "._cols_clean"
  }

  # ---- helper: run one check row and return a tidy log ----
  run_one_check <- function(check_row) {
    cid <- as.character(check_row[[check_id_column]])
    expr_str <- as.character(check_row[[check_to_perform_column]])
    desc <- as.character(check_row[[description_column]])
    cols_str <- as.character(check_row[[columns_to_clean_column]])

    # evaluate the expression safely, inside filter() so data-masking verbs
    # like across() and starts_with() work correctly
    flagged <- tryCatch(
      dplyr::filter(df, !!rlang::parse_expr(expr_str)),
      error = function(e) {
        stop(paste0(
          "Error evaluating check '",
          cid,
          "': ",
          conditionMessage(e),
          "\n  Expression: ",
          expr_str
        ))
      }
    )

    # also build the full-length logical flag to attach to checked_dataset
    flag <- tryCatch(
      {
        f <- rep(FALSE, nrow(df))
        matched <- as.character(df[[uuid_column]]) %in%
          as.character(flagged[[uuid_column]])
        f[matched] <- TRUE
        f
      },
      error = function(e) rep(FALSE, nrow(df))
    )

    # parse columns_to_clean
    cols_to_log <- if (!is.na(cols_str) && nzchar(trimws(cols_str))) {
      trimws(unlist(strsplit(cols_str, ",")))
    } else {
      character(0)
    }
    cols_to_log <- intersect(cols_to_log, names(df))

    # Empty log template — same shape regardless of which branch builds it.
    empty_log <- data.frame(
      uuid = character(0),
      old_value = character(0),
      question = character(0),
      issue = character(0),
      check_binding = character(0),
      stringsAsFactors = FALSE
    )

    if (nrow(flagged) == 0) {
      return(list(flag = flag, log = empty_log, cid = cid))
    }

    uuids <- as.character(flagged[[uuid_column]])

    if (length(cols_to_log) == 0) {
      # no specific columns: one row per flagged record
      log <- data.frame(
        uuid = uuids,
        old_value = NA_character_,
        question = cid,
        issue = desc,
        # binding = check_id ~/~ uuid so all rows from this check+record
        # share a colour in the cleaning log
        check_binding = paste(cid, uuids, sep = " ~/~ "),
        stringsAsFactors = FALSE
      )
    } else {
      # one row per (flagged record × column to clean), all with the same
      # check_binding so the reviewer sees them grouped by colour
      log <- do.call(
        rbind,
        lapply(cols_to_log, function(col) {
          data.frame(
            uuid = uuids,
            old_value = as.character(flagged[[col]]),
            question = col,
            issue = paste0("[", cid, "] ", desc),
            check_binding = paste(cid, uuids, sep = " ~/~ "),
            stringsAsFactors = FALSE
          )
        })
      )
      # sort so all columns for the same uuid sit together
      log <- log[order(log$uuid), , drop = FALSE]
    }
    list(flag = flag, log = log, cid = cid)
  }

  # ---- run all checks ----
  check_rows <- split(list_of_check, seq_len(nrow(list_of_check)))
  results <- lapply(check_rows, run_one_check)
  names(results) <- list_of_check[[check_id_column]]

  # ---- add one flag column per check to checked_dataset ----
  # Work on the full original df (before label-row removal) so the row count
  # stays consistent with what was passed in.
  full_df <- dataset[["checked_dataset"]]
  for (res in results) {
    flag_col <- rep(FALSE, nrow(full_df))
    # offset by 1 if we dropped the label row (the flag vector is over df[-1,])
    if (skip_label_row && nrow(full_df) > 0) {
      flag_col[-1] <- res$flag
    } else {
      flag_col <- res$flag
    }
    full_df[[res$cid]] <- flag_col
  }
  dataset[["checked_dataset"]] <- full_df

  # ---- collect logs ----
  all_logs <- lapply(results, `[[`, "log")

  total_flags <- sum(vapply(all_logs, nrow, integer(1)))
  message(
    "validate_logical_with_list: ran ",
    length(results),
    " check(s); ",
    total_flags,
    " log row(s) produced across ",
    length(unique(unlist(lapply(all_logs, `[[`, "uuid")))),
    " unique record(s)."
  )

  if (bind_checks) {
    combined <- do.call(rbind, all_logs)
    combined$old_value <- as.character(combined$old_value)
    dataset[[log_name]] <- combined
  } else {
    for (nm in names(all_logs)) {
      all_logs[[nm]]$old_value <- as.character(all_logs[[nm]]$old_value)
      dataset[[nm]] <- all_logs[[nm]]
    }
  }

  return(dataset)
}
