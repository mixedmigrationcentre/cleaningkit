#' Best available label for each row of an XLSForm sheet
#'
#' Row-wise label resolver shared by \code{get_other_labels()} and
#' \code{get_other_db()}. Detects a bare \code{label} column and any
#' \code{label::<language>} columns, orders them by preference (the requested
#' language first, else a bare \code{label}, else the first label column found),
#' and returns the first non-empty value per row. When a row has no label in any
#' language it falls back to the \code{name} column (if present) so nothing
#' resolves to \code{NA}.
#'
#' @param df An XLSForm survey or choices dataframe.
#' @param preferred_language Optional exact label column name (e.g.
#'   \code{"label::Arabic (ar)"}) or substring to match (e.g. \code{"English"},
#'   \code{"Arabic"}). When \code{NULL}, a bare \code{label} column is preferred;
#'   otherwise the first label column whose name contains the substring is used.
#' @param fallback_to_name Logical; if \code{TRUE} (default) unresolved rows use
#'   the \code{name} column value.
#' @return A character vector of labels, one per row of \code{df}.
#' @keywords internal
.best_label <- function(
  df,
  preferred_language = NULL,
  fallback_to_name = TRUE
) {
  if (nrow(df) == 0) {
    return(character(0))
  }

  label_cols <- names(df)[
    tolower(names(df)) == "label" |
      grepl("^label([:._[:space:]]|$)", names(df), ignore.case = TRUE)
  ]

  if (length(label_cols) == 0) {
    if (isTRUE(fallback_to_name) && "name" %in% names(df)) {
      return(as.character(df$name))
    }
    return(rep(NA_character_, nrow(df)))
  }

  # Order columns by preference:
  #   1. preferred_language match (exact or substring)
  #   2. bare "label" column (when no preferred_language given)
  #   3. remaining columns in their original order (fallback languages)
  if (!is.null(preferred_language)) {
    pref <- label_cols[
      label_cols == preferred_language |
        grepl(preferred_language, label_cols, ignore.case = TRUE)
    ]
    label_cols <- c(pref, setdiff(label_cols, pref))
  } else {
    bare <- label_cols[tolower(label_cols) == "label"]
    label_cols <- c(bare, setdiff(label_cols, bare))
  }

  mat <- as.matrix(df[, label_cols, drop = FALSE])
  out <- apply(mat, 1, function(vals) {
    vals <- vals[!is.na(vals) & nzchar(trimws(vals))]
    if (length(vals) == 0) NA_character_ else vals[[1]]
  })
  out <- as.character(out)

  if (isTRUE(fallback_to_name) && "name" %in% names(df)) {
    miss <- is.na(out) | !nzchar(trimws(out))
    out[miss] <- as.character(df$name)[miss]
  }
  out
}

#' Get Other Labels
#'
#' Retrieves text labels for questions in the XLSForm survey sheet that
#' correspond to "other" responses.
#'
#' @param tool_survey A dataframe containing the XLSForm survey sheet.
#' @param preferred_language Label column to prefer for \code{full_label}.
#'   Accepts an exact column name (e.g. \code{"label::English (en)"}) or a
#'   substring to match (e.g. \code{"English"}, \code{"Arabic"}). Defaults to
#'   \code{"English"} so that \code{label::English (en)} is picked up
#'   automatically on bilingual forms. Set to \code{NULL} to fall back to a
#'   bare \code{label} column, then the first label column found.
#' @param other_text_types Optional character vector of additional text question
#'   names to include (e.g. \code{c("Q31_2", "Q45_3")}). Default \code{NULL}.
#' @return A dataframe with one row per "other" text question and the columns
#'   \code{name}, \code{ref_question} and \code{full_label}.
#'
#' @details
#' The parent question (\code{ref_question}) is resolved from the question
#' \emph{name} first - \code{Q32_1} belongs to \code{Q32}, \code{Q86_b_1} to
#' \code{Q86_b} - and only falls back to parsing the relevance expression when
#' the name does not resolve to a question that exists in the survey sheet.
#' Reading the relevance expression first is what used to produce wrong
#' parents: a compound expression such as
#' \code{${Q31} = 'kenya' and selected(${Q32}, 'other')} references \code{Q31}
#' before \code{Q32}, so \code{Q32_1} was attributed to \code{Q31}. See
#' \code{.resolve_ref_question()} for the full resolution order.
#' @export
get_other_labels <- function(
  tool_survey,
  preferred_language = "English",
  other_text_types = NULL
) {
  # Language-aware question labels: name -> best available full_label.
  survey_labels <- data.frame(
    ref_question = as.character(tool_survey$name),
    full_label = .best_label(tool_survey, preferred_language),
    stringsAsFactors = FALSE
  )

  other_questions <- tool_survey %>%
    dplyr::filter(
      type == "text" &
        (stringr::str_detect(name, "_1$") | name %in% other_text_types)
    )

  # `relevant` is optional in an XLSForm; treat a missing column as all-NA
  # rather than failing, since the name convention resolves most forms anyway.
  relevant_expr <- if ("relevant" %in% names(other_questions)) {
    as.character(other_questions$relevant)
  } else {
    rep(NA_character_, nrow(other_questions))
  }

  resolved <- .resolve_ref_question(
    name = as.character(other_questions$name),
    relevant = relevant_expr,
    tool_survey = tool_survey
  )

  # Flag anything the survey sheet could not confirm, so a mis-named "other"
  # question is visible instead of silently pointing at the wrong column.
  unconfirmed <- resolved[resolved$resolved_via %in% c("relevance", "self"), ]
  if (nrow(unconfirmed) > 0) {
    warning(
      "get_other_labels(): could not confirm the parent question from the ",
      "question name for ",
      nrow(unconfirmed),
      " 'other' question(s); ",
      "fell back to the relevance expression or the question itself: ",
      paste0(
        unconfirmed$name,
        " -> ",
        unconfirmed$ref_question,
        " (",
        unconfirmed$resolved_via,
        ")",
        collapse = "; "
      ),
      call. = FALSE
    )
  }

  other_labels <- resolved %>%
    dplyr::select(name, ref_question) %>%
    dplyr::left_join(survey_labels, by = "ref_question")

  cat(crayon::green(
    " - SAVING (./resources/labels_questions_others.xlsx) ... \n"
  ))

  if (!dir.exists("resources")) {
    dir.create("resources", recursive = TRUE)
  }
  openxlsx::write.xlsx(
    other_labels,
    "resources/labels_questions_others.xlsx",
    overwrite = TRUE
  )

  return(other_labels)
}

#' Get Other DB
#'
#' Processes \code{other_labels} alongside the survey and choices sheets to map
#' out the available choices for recoding "other" responses.
#'
#' @param tool_survey A dataframe representing the XLSForm survey sheet.
#' @param tool_choices A dataframe representing the XLSForm choices sheet.
#' @param other_labels A dataframe retrieved from \code{get_other_labels()}.
#' @param preferred_language Label column to prefer for the choice labels used
#'   to build the recoding dropdowns. Should match the value passed to
#'   \code{get_other_labels()} so question labels and choice labels are in the
#'   same language. Accepts an exact column name or a substring. Defaults to
#'   \code{"English"} so that \code{label::English (en)} is used automatically.
#'   Set to \code{NULL} to fall back to a bare \code{label} column.
#' @return A dataframe representing the mapping required for the other-responses
#'   database.
#' @export
get_other_db <- function(
  tool_survey,
  tool_choices,
  other_labels,
  preferred_language = "English"
) {
  # generate other_db
  other_db <- other_labels %>%
    dplyr::left_join(
      dplyr::select(tool_survey, name, q_type, list_name),
      by = c("ref_question" = "name")
    ) %>%
    dplyr::left_join(
      dplyr::select(tool_survey, name, relevant),
      by = "name"
    ) %>%
    dplyr::mutate(
      # Take the option that `ref_question` is actually compared against in the
      # relevance expression. The previous greedy str_extract(relevant, "'.*'")
      # over-captured on compound expressions: for
      # ${Q31} = 'kenya' and selected(${Q32}, 'other') it returned
      # "kenya' and selected(${Q32}, 'other" instead of "other".
      option_other = .relevant_option_for_ref(relevant, ref_question)
    ) %>%
    dplyr::select(-relevant)

  # Remove the "other" option from the choices available for recoding.
  #
  # The option is identified by the PAIR (list_name, option_other) and matched
  # exactly. Two things used to go wrong here, and both silently deleted a
  # legitimate choice from every recoding dropdown rather than from one list:
  #
  #   * NA propagation. A row whose parent is not a select question carries
  #     list_name = NA, so `list_name == NA` is NA for every choice and
  #     `!(NA & TRUE)` is NA for the choice whose name equals option_other.
  #     dplyr::filter() drops NA rows, so that choice vanished from EVERY
  #     list. With the 4Mi "other" codes this is invisible (97 is meant to go
  #     from all of them anyway), but when option_other was read as 197 or 297
  #     - a code that only looks like an "other" code because it ends in 97 -
  #     those real choices disappeared from every dropdown.
  #   * Unscoped codes. option_other is read from the relevance expression and
  #     only means anything for a select_one / select_multiple parent, so a
  #     row of any other q_type must not remove a choice at all.
  #
  # Both are handled by building the set of (list_name, name) keys to drop
  # first, keeping only rows where both halves are known and the parent is a
  # select question, and then matching on the key itself.
  tool_choices_sub <- dplyr::filter(
    tool_choices,
    !is.na(list_name) & list_name %in% other_db$list_name
  )

  drop_rows <- !is.na(other_db$option_other) &
    nzchar(trimws(as.character(other_db$option_other))) &
    !is.na(other_db$list_name) &
    !is.na(other_db$q_type) &
    grepl("^select", as.character(other_db$q_type), ignore.case = TRUE)

  if (any(drop_rows)) {
    drop_keys <- unique(paste(
      trimws(as.character(other_db$list_name[drop_rows])),
      trimws(as.character(other_db$option_other[drop_rows])),
      sep = "\u0001"
    ))
    choice_keys <- paste(
      trimws(as.character(tool_choices_sub$list_name)),
      trimws(as.character(tool_choices_sub$name)),
      sep = "\u0001"
    )

    # An option_other that is not a choice of its own list means the relevance
    # expression was read wrong - most often a filter clause such as
    # `${Q12} = '197'` taken for the "other" option. Removing nothing and
    # saying so is better than removing a choice that is not the one.
    unknown <- setdiff(drop_keys, choice_keys)
    if (length(unknown) > 0) {
      parts <- strsplit(unknown, "\u0001", fixed = TRUE)
      warning(
        "get_other_db(): the 'other' option recorded for ",
        length(unknown),
        " question(s) is not a choice of its own list, so nothing was ",
        "removed from those drop-downs (list / option): ",
        paste0(
          vapply(parts, function(p) paste0(p[1], " / ", p[2]), character(1)),
          collapse = "; "
        ),
        call. = FALSE
      )
    }

    tool_choices_sub <- tool_choices_sub[
      !(choice_keys %in% drop_keys),
      ,
      drop = FALSE
    ]
  }

  # Resolve choice labels in the preferred language (fallback across languages,
  # then the choice name), so recoding dropdowns are not English-only / NA.
  tool_choices_sub$resolved_label <- .best_label(
    tool_choices_sub,
    preferred_language
  )

  # add list of available choices
  other_db <- other_db %>%
    dplyr::left_join(
      tool_choices_sub %>%
        dplyr::group_by(list_name) %>%
        dplyr::summarise(
          num_choices = dplyr::n(),
          choices = paste0(resolved_label, collapse = ";;"),
          .groups = "drop"
        ),
      by = "list_name"
    )

  return(other_db)
}
