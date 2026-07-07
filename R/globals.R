# Define global variables to suppress R CMD check warnings about
# "no visible binding for global variable" (commonly found when using dplyr / tidyverse)
if (getRversion() >= "2.15.1") {
  utils::globalVariables(c(
    ".data",
    ".end",
    ".enum",
    ".loop_index",
    ".start",
    ".uuid",
    "_submission_time",
    "analysis_type",
    "analysis_var",
    "analysis_var_value",
    "cleaning_log_other",
    "completeness_check",
    "duration_check",
    "full_label",
    "gap_mins",
    "gap_secs",
    "group_var",
    "group_var_value",
    "interview_hour",
    "interview_time_check",
    "interview_time_value",
    "issue",
    "label",
    "list_name",
    "match_flag",
    "matched_value",
    "name",
    "non_empty_count",
    "prev_ref",
    "prev_uuid",
    "q_type",
    "question",
    "question_name",
    "ref_question",
    "ref_word",
    "refused_check",
    "refused_count",
    "relevant",
    "response_en",
    "type",
    "uuid"
  ))
}

#' @import dplyr
#' @import stringr
#' @import openxlsx
#' @import tidyr
#' @import jsonlite
#' @import pak
#' @importFrom rlang .data sym :=
#' @importFrom purrr map map_lgl map2
#' @importFrom crayon green yellow red
#' @importFrom stats setNames
#' @importFrom utils install.packages
NULL
