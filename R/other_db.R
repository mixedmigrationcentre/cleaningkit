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
#' @return A dataframe containing the corresponding other labels.
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

  other_labels <- tool_survey %>%
    dplyr::filter(
      type == "text" &
        (stringr::str_detect(name, "_1$") | name %in% other_text_types)
    ) %>%
    dplyr::mutate(
      ref_question = as.character(lapply(relevant, get_ref_question))
    ) %>%
    dplyr::mutate(
      ref_question = ifelse(is.na(ref_question), name, ref_question)
    ) %>%
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
      option_other = stringr::str_replace_all(
        stringr::str_extract(relevant, "\'.*\'"),
        "'",
        ""
      )
    ) %>%
    dplyr::select(-relevant)

  # remove the "other" option from the choices available for recoding
  tool_choices_sub <- dplyr::filter(
    tool_choices,
    list_name %in% other_db$list_name
  )

  for (r in seq_len(nrow(other_db))) {
    if (!is.na(other_db$option_other[r])) {
      tool_choices_sub <- tool_choices_sub %>%
        dplyr::filter(
          !(list_name == other_db$list_name[r] &
            name == other_db$option_other[r])
        )
    }
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
