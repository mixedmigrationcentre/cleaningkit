#' Best available label for each row of a Kobo sheet
#'
#' Row-wise label resolver shared by \code{get_other_labels()} and
#' \code{get_other_db()}. Detects a bare \code{label} column and any
#' \code{label::<language>} columns, orders them by preference (the requested
#' language first, else a bare \code{label}, else the first label column found),
#' and returns the first non-empty value per row. When a row has no label in any
#' language it falls back to the \code{name} column (if present) so nothing
#' resolves to \code{NA}.
#'
#' @param df A Kobo survey or choices dataframe.
#' @param preferred_language Optional exact label column name (e.g.
#'   \code{"label::Arabic (ar)"}) or substring (e.g. \code{"Arabic"}).
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

  # Order columns by preference.
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
#' Retrieves text labels for questions in the kobo survey that correspond to "other" responses.
#'
#' @param kobo_survey A dataframe containing the Kobo survey sheet.
#' @param preferred_language Optional label language to prefer for the question
#'   \code{full_label}. May be an exact label column name (e.g.
#'   \code{"label::Arabic (ar)"}) or a substring (e.g. \code{"Arabic"}). If
#'   \code{NULL} (the default), a bare \code{label} column is preferred, else the
#'   first label column found; other languages fill any gaps.
#' @param other_text_types Optional character vector of text question names
#'   whose text fields use a different suffix (e.g. \code{"_2"}, \code{"_3"}).
#'   Pass the full question names as they appear in the survey, for example
#'   \code{c("Q31_2", "Q45_3")}. Defaults to \code{NULL} (no extra text types).
#' @return A dataframe containing the corresponding other labels.
#' @export
get_other_labels <- function(kobo_survey, preferred_language = NULL,
                             other_text_types = NULL) {
  # Language-aware question labels: name -> best available full_label.
  survey_labels <- data.frame(
    ref_question = as.character(kobo_survey$name),
    full_label = .best_label(kobo_survey, preferred_language),
    stringsAsFactors = FALSE
  )

  other_labels <- kobo_survey %>%
    filter(type == "text" & (str_detect(name, "_1$") | name %in% other_text_types)) %>%
    mutate(
      ref_question = as.character(lapply(relevant, get_ref_question))
    ) %>%
    mutate(
      ref_question = ifelse(is.na(ref_question), name, ref_question)
    ) %>%
    select(name, ref_question) %>%
    left_join(survey_labels, by = "ref_question")

  cat(green(" - SAVING (./resources/labels_questions_others.xlsx) ... \n"))

  if (!dir.exists("resources")) {
    dir.create("resources", recursive = TRUE)
  }
  write.xlsx(
    other_labels,
    "resources/labels_questions_others.xlsx",
    overwrite = T
  )

  return(other_labels)
}

#' Get Other DB
#'
#' Processes the 'other_labels' alongside the survey inputs to map out the available choices for recoding.
#'
#' @param kobo_survey A dataframe representing the Kobo survey.
#' @param kobo_choices A dataframe representing the Kobo choices.
#' @param other_labels A dataframe retrieved from `get_other_labels`.
#' @param preferred_language Optional label language to prefer for the available
#'   choice labels used to build the recoding dropdowns. May be an exact label
#'   column name or a substring (e.g. \code{"Arabic"}). Should match the value
#'   passed to \code{get_other_labels()} so question labels and choice labels are
#'   in the same language. If \code{NULL} (the default), a bare \code{label}
#'   column is preferred, else the first label column found.
#' @return A dataframe representing the mapping required for other responses database.
#' @export
get_other_db <- function(
  kobo_survey,
  kobo_choices,
  other_labels,
  preferred_language = NULL
) {
  # generate other_db
  other_db <- other_labels %>%
    left_join(
      select(kobo_survey, name, q_type, list_name),
      by = c("ref_question" = "name")
    ) %>%
    left_join(select(kobo_survey, name, relevant), by = "name") %>%
    mutate(
      option_other = str_replace_all(
        str_extract(relevant, "\'.*\'"),
        "'",
        ""
      )
    ) %>%
    select(-relevant)

  # remove all of option_other from choices
  kobo_choices_sub <- filter(
    kobo_choices,
    list_name %in% other_db$list_name
  )

  for (r in seq_len(nrow(other_db))) {
    if (!is.na(other_db$option_other[r])) {
      kobo_choices_sub <- kobo_choices_sub %>%
        filter(
          !(list_name == other_db$list_name[r] &
            name == other_db$option_other[r])
        )
    }
  }

  # Resolve choice labels in the preferred language (fallback across languages,
  # then the choice name), so the recoding dropdowns are not English-only / NA.
  kobo_choices_sub$resolved_label <- .best_label(
    kobo_choices_sub,
    preferred_language
  )

  # add list of available choices
  other_db <- other_db %>%
    left_join(
      kobo_choices_sub %>%
        group_by(list_name) %>%
        summarise(
          num_choices = n(),
          choices = paste0(resolved_label, collapse = ";;"),
          .groups = "drop"
        ),
      by = "list_name"
    )

  return(other_db)
}
