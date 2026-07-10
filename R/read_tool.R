#' Read XLSForm Survey Sheet.
#'
#' Reads and processes the survey sheet from an XLSForm tool. Column names are
#' lowercased, rows without a name are removed, and \code{q_type} and
#' \code{list_name} columns are extracted from the \code{type} column.
#'
#' @param filepath Path to the XLSForm XLS/XLSX tool file.
#' @param sheet_name Name of the survey sheet (default is "survey").
#' @return A dataframe containing the processed survey sheet with added
#'   \code{q_type} and \code{list_name} columns.
#' @export
read_tool_survey <- function(filepath, sheet_name = "survey") {
  tool_survey <- readxl::read_excel(
    filepath,
    sheet = sheet_name,
    col_types = "text"
  ) %>%
    rename_with(tolower) %>%
    filter(!is.na(name)) %>%
    mutate(
      q_type = as.character(lapply(type, function(x) {
        str_split(x, " ")[[1]][1]
      })),
      # split list name from type column
      list_name = as.character(lapply(type, function(x) {
        str_split(x, " ")[[1]][2]
      }))
    )

  cat(crayon::green(paste0(
    "--> XLSForm survey loaded: ",
    nrow(tool_survey),
    " questions\n"
  )))

  return(tool_survey)
}

#' Read XLSForm Choices Sheet.
#'
#' Reads and processes the choices sheet from an XLSForm tool. Column names
#' are lowercased, rows without a \code{list_name} are removed, and
#' duplicate entries are dropped.
#'
#' @param filepath Path to the XLSForm XLS/XLSX tool file.
#' @param sheet_name Name of the choices sheet (default is "choices").
#' @return A dataframe containing the processed choices sheet with columns
#'   \code{list_name}, \code{name}, and \code{label}.
#' @export
read_tool_choices <- function(filepath, sheet_name = "choices") {
  tool_choices <- readxl::read_excel(
    filepath,
    sheet = sheet_name,
    col_types = "text"
  ) %>%
    rename_with(tolower) %>%
    filter(!is.na(list_name)) %>%
    select(list_name, name, label) %>%
    distinct()

  cat(crayon::green(paste0(
    "--> XLSForm choices loaded: ",
    nrow(tool_choices),
    " choices\n"
  )))

  return(tool_choices)
}
