#' Prioritise Most Suspicious Enumerators
#'
#' Aggregates the validation logs produced by the \code{validate_*} functions and ranks
#' enumerators by how suspicious their work looks. Because every log shares the same
#' \code{uuid} / \code{old_value} / \code{question} / \code{issue} structure and the raw
#' dataset holds both the uuid and the enumerator id, each flag can be traced back to the
#' enumerator who collected it and then rolled up into a single priority table.
#'
#' @details
#' The function reflects the idea that no single check is conclusive: an enumerator who
#' trips several \emph{different} checks (e.g. short duration \emph{and} back-to-back
#' interviews \emph{and} repeated logical issues) is more suspicious than one who trips a
#' single check many times. This is captured by \code{diversity_bonus}, which increases the
#' score for each additional distinct check an enumerator triggers:
#' \deqn{priority\_score = weighted\_flags \times (1 + diversity\_bonus \times (n\_checks\_triggered - 1))}
#' where \code{weighted_flags} is the sum, over every included log, of the number of the
#' enumerator's interviews flagged by that log (optionally multiplied by a per-log weight).
#'
#' The table also reports \code{flag_rate} (share of the enumerator's interviews flagged at
#' least once), so a productive enumerator with many interviews is not penalised purely for
#' volume. Rows are ranked by \code{priority_score}, then by number of distinct checks, then
#' by flag rate. The result is a review queue, not an automatic rejection list.
#'
#' @param dataset A list produced by the \code{validate_*} functions, containing
#'   \code{checked_dataset} and one or more log dataframes.
#' @param uuid_column The name of the unique-identifier column in \code{checked_dataset}. Default \code{"_uuid"}.
#' @param enumerator_column The name of the enumerator-id column in \code{checked_dataset}. Default \code{"username"}.
#' @param logs Optional character vector naming which log elements to include. If \code{NULL}
#'   (the default) all dataframes in the list that look like logs (i.e. contain a \code{uuid}
#'   column, excluding \code{checked_dataset}) are used.
#' @param weights Optional named numeric vector giving a weight per log name (e.g.
#'   \code{c(back_to_back_log = 2, duration_log = 1)}). Logs not named default to weight 1.
#' @param diversity_bonus Numeric >= 0. How much each additional distinct check inflates the
#'   score. \code{0} ignores diversity; \code{0.5} (the default) adds 50\% per extra check.
#' @param include_clean Logical. If \code{TRUE}, enumerators with no flags are also listed
#'   (with a score of 0). Default \code{FALSE}.
#' @param min_interviews Integer. Enumerators with fewer than this many interviews are dropped
#'   to reduce small-sample noise (the "(unknown)" group is always kept). Default \code{1}.
#' @param output_name The name under which to store the priority table in the list. Default
#'   \code{"enumerator_priority"}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of
#'   \code{checked_dataset} is dropped when building the uuid-to-enumerator lookup, matching
#'   the ONA label/description row handling of the other functions.
#' @return The input list with an added \code{output_name} dataframe: one row per enumerator,
#'   ranked from most to least suspicious.
#' @export
prioritize_enumerators <- function(
  dataset,
  uuid_column = "_uuid",
  enumerator_column = "username",
  logs = NULL,
  weights = NULL,
  diversity_bonus = 0.5,
  include_clean = FALSE,
  min_interviews = 1,
  output_name = "enumerator_priority",
  skip_label_row = TRUE
) {
  if (is.data.frame(dataset)) {
    stop(
      "`dataset` must be the list produced by the validate_* functions ",
      "(containing checked_dataset and one or more logs), not a bare dataframe."
    )
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list")
  }

  checked <- dataset[["checked_dataset"]]

  if (!(uuid_column %in% names(checked))) {
    stop(paste0("Cannot find ", uuid_column, " in the names of the dataset"))
  }
  if (!(enumerator_column %in% names(checked))) {
    stop(paste0(
      "Cannot find ",
      enumerator_column,
      " in the names of the dataset"
    ))
  }

  if (is.null(weights)) {
    weights <- stats::setNames(numeric(0), character(0))
  }

  # ---- uuid -> enumerator lookup and per-enumerator interview counts ----
  if (skip_label_row && nrow(checked) > 0) {
    checked <- checked[-1, , drop = FALSE]
  }

  map <- data.frame(
    uuid = as.character(checked[[uuid_column]]),
    enumerator = trimws(as.character(checked[[enumerator_column]])),
    stringsAsFactors = FALSE
  )
  map$enumerator[is.na(map$enumerator) | map$enumerator == ""] <- "(unknown)"
  map <- dplyr::distinct(map, uuid, .keep_all = TRUE)

  interviews <- dplyr::count(map, enumerator, name = "n_interviews")

  # ---- identify which elements are logs ----
  candidate_logs <- setdiff(names(dataset), c("checked_dataset", output_name))
  is_log <- vapply(
    candidate_logs,
    function(nm) {
      is.data.frame(dataset[[nm]]) && ("uuid" %in% names(dataset[[nm]]))
    },
    logical(1)
  )
  detected_logs <- candidate_logs[is_log]

  if (!is.null(logs)) {
    detected_logs <- intersect(logs, detected_logs)
  }

  # empty-result template used when nothing is available
  empty_result <- data.frame(
    rank = integer(0),
    enumerator = character(0),
    priority_score = numeric(0),
    n_checks_triggered = integer(0),
    total_flags = integer(0),
    flagged_interviews = integer(0),
    n_interviews = integer(0),
    flag_rate = numeric(0),
    checks_triggered = character(0),
    stringsAsFactors = FALSE
  )

  if (length(detected_logs) == 0) {
    warning("No logs found in the list; nothing to prioritise.")
    dataset[[output_name]] <- empty_result
    return(dataset)
  }

  # ---- one row per (log, distinct flagged uuid) ----
  flags_uuid <- dplyr::bind_rows(lapply(detected_logs, function(nm) {
    l <- dataset[[nm]]
    if (nrow(l) == 0) {
      return(data.frame(
        uuid = character(0),
        check = character(0),
        stringsAsFactors = FALSE
      ))
    }
    dplyr::distinct(
      data.frame(
        uuid = as.character(l$uuid),
        check = nm,
        stringsAsFactors = FALSE
      )
    )
  }))

  if (nrow(flags_uuid) == 0) {
    warning("The logs contain no flagged records; nothing to prioritise.")
    dataset[[output_name]] <- empty_result
    return(dataset)
  }

  flags_long <- flags_uuid %>%
    dplyr::left_join(map, by = "uuid") %>%
    dplyr::mutate(
      enumerator = ifelse(
        is.na(enumerator) | enumerator == "",
        "(unknown)",
        enumerator
      )
    )

  # ---- per (enumerator, check) counts, with weights ----
  per_check <- flags_long %>%
    dplyr::group_by(enumerator, check) %>%
    dplyr::summarise(n = dplyr::n_distinct(uuid), .groups = "drop") %>%
    dplyr::mutate(
      w = unname(ifelse(check %in% names(weights), weights[check], 1)),
      wn = n * w
    ) %>%
    dplyr::arrange(enumerator, dplyr::desc(n))

  summary <- per_check %>%
    dplyr::group_by(enumerator) %>%
    dplyr::summarise(
      total_flags = sum(n),
      n_checks_triggered = dplyr::n(),
      weighted_flags = sum(wn),
      checks_triggered = paste0(check, " (", n, ")", collapse = "; "),
      .groups = "drop"
    )

  flagged <- flags_long %>%
    dplyr::distinct(enumerator, uuid) %>%
    dplyr::count(enumerator, name = "flagged_interviews")

  result <- summary %>%
    dplyr::left_join(flagged, by = "enumerator") %>%
    dplyr::left_join(interviews, by = "enumerator")

  # optionally add enumerators with no flags at all
  if (include_clean) {
    clean <- interviews %>%
      dplyr::filter(!(enumerator %in% result$enumerator)) %>%
      dplyr::mutate(
        total_flags = 0L,
        n_checks_triggered = 0L,
        weighted_flags = 0,
        checks_triggered = "",
        flagged_interviews = 0L
      )
    result <- dplyr::bind_rows(result, clean)
  }

  result <- result %>%
    dplyr::mutate(
      n_interviews = dplyr::coalesce(as.integer(n_interviews), 0L),
      flagged_interviews = dplyr::coalesce(as.integer(flagged_interviews), 0L),
      flag_rate = ifelse(
        n_interviews > 0,
        round(flagged_interviews / n_interviews, 3),
        NA_real_
      ),
      priority_score = round(
        weighted_flags * (1 + diversity_bonus * (n_checks_triggered - 1)),
        2
      )
    ) %>%
    dplyr::filter(
      n_interviews >= min_interviews | enumerator == "(unknown)"
    ) %>%
    dplyr::arrange(
      dplyr::desc(priority_score),
      dplyr::desc(n_checks_triggered),
      dplyr::desc(flag_rate)
    ) %>%
    dplyr::mutate(rank = dplyr::row_number()) %>%
    dplyr::select(
      rank,
      enumerator,
      priority_score,
      n_checks_triggered,
      total_flags,
      flagged_interviews,
      n_interviews,
      flag_rate,
      checks_triggered
    )

  dataset[[output_name]] <- as.data.frame(result, stringsAsFactors = FALSE)
  return(dataset)
}
