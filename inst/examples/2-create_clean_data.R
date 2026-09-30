#----------------------------------
# Initialize the package and
# all required packages
#----------------------------------

rm(list = ls())
library(cleaningkit)

cleaningkit::load_packages()

#----------------------------------
# Read tool data
#----------------------------------

tool_survey <- cleaningkit::read_tool_survey("./resources/tool.xlsx")
tool_choices <- cleaningkit::read_tool_choices("./resources/tool.xlsx")

#----------------------------------
# create other response db
#----------------------------------

other_labels <- cleaningkit::get_other_labels(
  tool_survey = tool_survey,
  other_text_types = c("Q31_2")
)

other_db <- cleaningkit::get_other_db(
  other_labels = other_labels,
  tool_choices = tool_choices,
  tool_survey = tool_survey
)

#----------------------------------
# Read raw data
#----------------------------------

raw_data <- cleaningkit::read_raw_data(
  filename = "./data/data.xlsx",
  tool_survey = tool_survey
)
#----------------------------------
# read cleaning log
#
# one reviewed workbook now carries both logs, so this and
# read_other_responses() below are pointed at the same folder and the same
# file. each finds its own sheet by name - `cleaning_log` here,
# `other_responses` there - so neither depends on the tab order.
#----------------------------------
cl <- cleaningkit::read_cleaning_log(
  raw_dataset = raw_data,
  path = "./output/follow_ups/",
  raw_uuid_column = "_uuid",
  uuid_col = "Survey UUID",
  action_col = "Action taken",
  question_col = "Question number",
  old_value_col = "Old value",
  new_value_col = "New value",
  # matches both the plain workbook and a macro-enabled one; readxl reads
  # .xlsm exactly like .xlsx
  file_pattern = "_follow-ups_edited\\.xls[xm]$",
  # sheet = "cleaning_log" is the default; pass a name or a number to override
  extra_questions = NULL,
  skip_label_row = TRUE,
  verbose = TRUE
)

#----------------------------------
# evaluate cleaning log
# This checks for any errors in the file, like action taken column blank
#----------------------------------
review_cleaning_log <- cleaningkit::evaluate_cleaning_log(
  raw_dataset = raw_data,
  cleaning_log = cl,
  uuid_col = "Survey UUID",
  action_col = "Action taken",
  question_col = "Question number",
  old_value_col = "Old value",
  new_value_col = "New value",
  raw_uuid_column = "_uuid",
  valid_actions = c(
    "recoded",
    "delete_data_point",
    "addition",
    "discard",
    "other",
    "no_action"
  ),
  skip_label_row = TRUE,
  flag_issues_inline = TRUE
)

#----------------------------------
# Filter surveys in raw data that exist in cleaning log
#
#----------------------------------
# Keep label row
label_row <- raw_data[1, ]

# Apply filter
raw_data <- raw_data[-1, ] %>%
  filter(`_uuid` %in% cl$`Survey UUID`)

# Bind back the label row
raw_data <- bind_rows(label_row, raw_data)

#----------------------------------
# apply cleaning log
# This function performs the actions to clean the data
#----------------------------------
clean_data <- cleaningkit::apply_cleaning_log(
  raw_dataset = raw_data,
  cleaning_log = cl,
  raw_uuid_column = "_uuid",
  log_uuid_col = "Survey UUID",
  log_question_col = "Question number",
  log_new_value_col = "New value",
  log_action_col = "Action taken",
  change_response_values = c("recoded", "addition", "other"),
  blank_response_values = "delete_data_point",
  remove_survey_values = "discard",
  no_action_values = "no_action",
  skip_label_row = TRUE,
  restore_types = TRUE,
  verbose = TRUE
)

#----------------------------------
# read other responses log
#
# the same reviewed file as above, read from its `other_responses` sheet.
# for a file produced by the older standalone save_other_responses() route,
# point `path` at ./output/other_responses/ and set
# file_pattern = "_other_responses_edited\\.xlsx$" - the sheet is found either
# way, whether it is called `other_responses` or the older `Sheet1`.
#----------------------------------
other_log <- cleaningkit::read_other_responses(
  path = "./output/follow_ups/",
  dataset = clean_data$clean_dataset,
  uuid_column = "_uuid",
  log_uuid_col = "uuid",
  other_db = other_db,
  tool_choices = tool_choices,
  sm_separator = "/",
  file_pattern = "_follow-ups_edited\\.xls[xm]$",
  skip_questions = NULL,
  skip_label_row = TRUE,
  verbose = TRUE
)

#----------------------------------
# apply other responses log
# perform the cleaning of other text responses
# using the reviewed other responses output
#----------------------------------
result <- cleaningkit::apply_other_responses(
  clean_data$clean_dataset,
  other_log,
  uuid_column = "_uuid"
)
clean_data <- result$dataset

#----------------------------------
# combine cleaning logs
#----------------------------------
final_log <- cleaningkit::combine_reviewed_logs(
  main_log = cl,
  other_log = other_log,
  dataset = raw_data,
  uuid_column = "_uuid",
  enumerator_column = "username",
  date_column = "today",
  cleaning_log_name = "cleaning_log",
  issue_labels = c(
    true_other = "Translation or correction of a genuine other response",
    recode = "Other response recoded to an existing choice",
    remove = "Invalid other response — value removed"
  ),
  skip_label_row = TRUE
)

#----------------------------------
# review clean dataset
#----------------------------------
review_cleaning <- cleaningkit::review_cleaned_data(
  raw_dataset = raw_data,
  clean_dataset = clean_data,
  cleaning_log = final_log,
  raw_uuid_column = "_uuid",
  clean_uuid_column = "_uuid",
  log_uuid_col = "Survey UUID",
  log_question_col = "Question number",
  log_new_value_col = "New value",
  log_old_value_col = "Old value",
  log_action_col = "Action taken",
  change_response_values = c(
    "recoded",
    "addition",
    "other",
    "recode",
    "remove",
    "true_other"
  ),
  blank_response_values = "delete_data_point",
  discard_values = "discard",
  no_action_values = "no_action",
  columns_to_skip = c(
    "start",
    "end",
    "today",
    "deviceid",
    "uuid",
    "_uuid",
    "id",
    "_id",
    "submission_time",
    "_submission_time",
    "index",
    "_index",
    "df_name",
    "username",
    "simserial",
    "phonenumber",
    "_submission_time",
    "check_binding",
    "evaluation_issue",
    "_location_altitude"
  ),
  skip_label_row = TRUE,
  verbose = TRUE
)

#----------------------------------
# create final workbook
#----------------------------------

cleaningkit::export_final_output(
  raw_dataset = raw_data,
  clean_dataset = clean_data,
  combined_log = final_log,
  output_path = paste0("./output/final/", Sys.Date(), "_4Mi_final_output.xlsx"),
  project_name = "4Mi East Africa — Round 12",
  data_collection_round = "Round 12 — Q1 2025",
  prepared_by = "MMC Data Team",
  project_description = paste0(
    "Add project description here.",
  ),
)
