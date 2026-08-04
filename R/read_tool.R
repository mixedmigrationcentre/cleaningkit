#' Read XLSForm Survey Sheet
#'
#' Reads and processes the survey sheet from an XLSForm tool. Column names are
#' lowercased, rows without a \code{name} are removed, and \code{q_type} and
#' \code{list_name} columns are extracted from the \code{type} column.
#'
#' A normalised \code{label} column is created from whichever label column
#' matches \code{label_column} (e.g. \code{label::English (en)}). This ensures
#' all downstream functions that reference \code{tool_survey$label} work
#' consistently regardless of whether the form uses a bare \code{label} column
#' or a language-tagged one. All original label columns are preserved alongside
#' the normalised one.
#'
#' @param filepath Path to the XLSForm XLS/XLSX tool file.
#' @param sheet_name Name of the survey sheet. Default \code{"survey"}.
#' @param label_column The label column to normalise as the primary \code{label}
#'   column. Accepts an exact column name (e.g. \code{"label::English (en)"}),
#'   a substring to match (e.g. \code{"English"}), or \code{NULL} to use a
#'   bare \code{label} column if present. Default \code{"English"}, which
#'   automatically picks up \code{label::English (en)}.
#'
#' @return A dataframe containing the processed survey sheet. Always includes a
#'   \code{label} column (the resolved preferred language label), \code{q_type},
#'   and \code{list_name}, plus all other original columns.
#' @export
read_tool_survey <- function(
  filepath,
  sheet_name = "survey",
  label_column = "English"
) {
  tool_survey <- readxl::read_excel(
    filepath,
    sheet = sheet_name,
    col_types = "text"
  ) %>%
    dplyr::rename_with(tolower) %>%
    dplyr::filter(!is.na(name)) %>%
    dplyr::mutate(
      q_type = as.character(lapply(type, function(x) {
        stringr::str_split(x, " ")[[1]][1]
      })),
      list_name = as.character(lapply(type, function(x) {
        stringr::str_split(x, " ")[[1]][2]
      }))
    )

  # ---- resolve and normalise the primary label column ----
  tool_survey <- .normalise_label_col(tool_survey, label_column)

  cat(crayon::green(paste0(
    "--> XLSForm survey loaded: ",
    nrow(tool_survey),
    " questions\n"
  )))

  return(tool_survey)
}

#' Read XLSForm Choices Sheet
#'
#' Reads and processes the choices sheet from an XLSForm tool. Column names are
#' lowercased, rows without a \code{list_name} are removed, and duplicate
#' entries are dropped.
#'
#' A normalised \code{label} column is created from whichever label column
#' matches \code{label_column} (e.g. \code{label::English (en)}). This ensures
#' \code{get_label_from_name()}, \code{get_name_from_label()}, and all other
#' downstream functions that reference \code{tool_choices$label} work
#' consistently regardless of form language setup.
#'
#' @param filepath Path to the XLSForm XLS/XLSX tool file.
#' @param sheet_name Name of the choices sheet. Default \code{"choices"}.
#' @param label_column The label column to normalise as the primary \code{label}
#'   column. Accepts an exact column name (e.g. \code{"label::English (en)"}),
#'   a substring to match (e.g. \code{"English"}), or \code{NULL} to use a
#'   bare \code{label} column if present. Default \code{"English"}, which
#'   automatically picks up \code{label::English (en)}.
#'
#' @return A dataframe containing the processed choices sheet. Always includes
#'   \code{list_name}, \code{name}, and \code{label} (the resolved preferred
#'   language label), plus any additional label columns present in the sheet.
#' @export
read_tool_choices <- function(
  filepath,
  sheet_name = "choices",
  label_column = "English"
) {
  tool_choices <- readxl::read_excel(
    filepath,
    sheet = sheet_name,
    col_types = "text"
  ) %>%
    dplyr::rename_with(tolower) %>%
    dplyr::filter(!is.na(list_name)) %>%
    dplyr::distinct()

  # ---- resolve and normalise the primary label column ----
  tool_choices <- .normalise_label_col(tool_choices, label_column)

  # keep list_name, name, label first; append any remaining label columns
  core_cols <- c("list_name", "name", "label")
  extra_cols <- setdiff(names(tool_choices), core_cols)
  tool_choices <- dplyr::select(
    tool_choices,
    dplyr::all_of(core_cols),
    dplyr::any_of(extra_cols)
  )

  cat(crayon::green(paste0(
    "--> XLSForm choices loaded: ",
    nrow(tool_choices),
    " choices\n"
  )))

  return(tool_choices)
}

#' Resolve and normalise the primary label column in an XLSForm sheet
#'
#' Finds the label column that best matches \code{label_column} and ensures a
#' column named exactly \code{"label"} exists, creating or overwriting it as
#' needed. All original label columns are preserved so no information is lost.
#'
#' Resolution order:
#' \enumerate{
#'   \item Exact match on \code{label_column}.
#'   \item Substring match (case-insensitive) in any \code{label*} column.
#'   \item Bare \code{"label"} column (when \code{label_column} is \code{NULL}).
#'   \item First \code{label*} column found (last resort).
#'   \item If no label column exists at all, an empty \code{label} column is
#'     added and a warning is issued.
#' }
#'
#' @param df A lowercased XLSForm dataframe.
#' @param label_column Substring or exact column name to match. \code{NULL}
#'   falls back to the bare \code{"label"} column.
#' @return \code{df} with a \code{"label"} column guaranteed to exist.
#' @keywords internal
.normalise_label_col <- function(df, label_column = NULL) {
  # all columns that look like label columns
  all_label_cols <- names(df)[
    tolower(names(df)) == "label" |
      grepl("^label([:._[:space:]]|$)", names(df), ignore.case = TRUE)
  ]

  if (length(all_label_cols) == 0) {
    warning(
      "No label column found in the sheet. ",
      "Adding an empty 'label' column. ",
      "Check that the XLSForm contains a 'label' or 'label::<language>' column."
    )
    df[["label"]] <- NA_character_
    return(df)
  }

  # --- find the best matching column ---
  matched_col <- NULL

  if (!is.null(label_column) && nzchar(label_column)) {
    # 1. exact match
    exact <- all_label_cols[all_label_cols == label_column]
    if (length(exact) > 0) {
      matched_col <- exact[1]
    } else {
      # 2. substring match (case-insensitive)
      partial <- all_label_cols[
        grepl(label_column, all_label_cols, ignore.case = TRUE)
      ]
      if (length(partial) > 0) matched_col <- partial[1]
    }
    if (is.null(matched_col)) {
      warning(paste0(
        "label_column '",
        label_column,
        "' did not match any column. ",
        "Available label columns: ",
        paste(all_label_cols, collapse = ", "),
        ". ",
        "Falling back to: ",
        all_label_cols[1]
      ))
    }
  }

  # 3. bare "label" fallback when label_column = NULL
  if (is.null(matched_col)) {
    bare <- all_label_cols[tolower(all_label_cols) == "label"]
    if (length(bare) > 0) {
      matched_col <- bare[1]
    } else {
      # 4. first label column found
      matched_col <- all_label_cols[1]
    }
  }

  # if the matched column is already named "label" we're done
  if (matched_col == "label") {
    return(df)
  }

  # otherwise create/overwrite the "label" column with the matched column's values
  # (keep the original column too so no information is lost)
  df[["label"]] <- df[[matched_col]]
  df
}
