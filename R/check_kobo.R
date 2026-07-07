#' Check if Answer Exists in Choices List
#'
#' Validates a single constraint expression of the form
#' \code{selected(${question_name}, 'answer')} by checking whether the
#' answer value exists in the corresponding choices list.
#'
#' @param questions A dataframe containing the Kobo survey sheet.
#' @param choices A dataframe containing the Kobo choices sheet.
#' @param constraint A string containing a single constraint expression.
#' @return \code{TRUE} if the answer is valid or the constraint is not
#'   a selected() type, \code{FALSE} otherwise.
#' @keywords internal
check_answer_in_list <- function(questions, choices, constraint) {
  if (!str_detect(constraint, ",")) {
    return(TRUE)
  }

  question_regex <- "\\{([^()]+)\\}"
  answer_regex <- "\\'([^()]+)\\'"

  question <- gsub(
    question_regex,
    "\\1",
    str_extract_all(constraint, question_regex)[[1]]
  )
  answer <- gsub(
    answer_regex,
    "\\1",
    str_extract_all(constraint, answer_regex)[[1]]
  )

  question_type <- questions %>%
    filter(name == question) %>%
    filter(!grepl("^(begin|end)\\s+group$", type)) %>%
    pull(type)

  if (length(question_type) == 0 || question_type == "calculate") {
    return(TRUE)
  } else {
    listname <- gsub("^.*\\s", "", question_type)
    choices_list <- choices %>%
      filter(list_name == listname) %>%
      pull(name)
    return(answer %in% choices_list)
  }
}

#' Check Kobo Survey Constraints
#'
#' Scans the relevant column of a Kobo survey sheet for all
#' \code{selected()} constraint expressions and validates that each
#' referenced answer exists in the choices sheet. Returns a character
#' vector of invalid constraints, if any.
#'
#' @param questions A dataframe containing the Kobo survey sheet.
#' @param choices A dataframe containing the Kobo choices sheet.
#' @return A character vector of invalid constraint expressions, or
#'   \code{NULL} if all constraints are valid.
#' @export
check_constraints <- function(questions, choices) {
  # Verify survey and choices sheets
  if (!is.data.frame(questions)) {
    stop("Survey sheet (questions) must be a data frame.")
  }
  if (!is.data.frame(choices)) {
    stop("Choices sheet must be a data frame.")
  }

  required_survey_cols <- c("name", "type", "relevant")
  missing_survey <- setdiff(required_survey_cols, colnames(questions))
  if (length(missing_survey) > 0) {
    stop("Survey sheet is missing required columns: ", paste(missing_survey, collapse = ", "))
  }

  required_choices_cols <- c("list_name", "name")
  missing_choices <- setdiff(required_choices_cols, colnames(choices))
  if (length(missing_choices) > 0) {
    stop("Choices sheet is missing required columns: ", paste(missing_choices, collapse = ", "))
  }

  questions <- mutate_at(questions, c("name", "type"), ~ str_trim(.))
  choices <- mutate_at(choices, c("list_name", "name"), ~ str_trim(.))

  all_constraints <- questions %>%
    filter(grepl("selected", relevant)) %>%
    pull(relevant)
  all_constraints <- gsub('"', "'", all_constraints)

  # Extract all selected() expressions and validate each
  selected_pattern <- "selected\\s*\\([^\\)]*\\)"

  rs_list <- purrr::map(
    all_constraints,
    ~ purrr::map_lgl(
      str_extract_all(.x, selected_pattern)[[1]],
      ~ check_answer_in_list(questions, choices, .x)
    )
  )

  invalid <- purrr::map2(
    rs_list,
    seq_along(rs_list),
    ~ if (length(which(!.x)) != 0) {
      return(
        str_extract_all(all_constraints[.y], selected_pattern)[[1]][which(!.x)]
      )
    }
  ) %>%
    unlist() %>%
    unique()

  if (length(invalid) == 0) {
    cat(crayon::green("All constraints are valid!\n"))
    return(invisible(NULL))
  }

  return(invalid)
}
