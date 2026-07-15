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
# read the cleaning log file
#----------------------------------
cl <- cleaningkit::read_cleaning_log(
  raw_dataset = raw_data,
  path = "./output/",
  sheet = 1,
  raw_uuid_column = "_uuid",
  uuid_col = "Survey UUID",
  action_col = "Action taken",
  question_col = "Question number",
  old_value_col = "Old value",
  new_value_col = "New value",
  file_pattern = "_follow-ups_edited\\.xlsx$",
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
# read and classify other responses
#----------------------------------
other_log <- cleaningkit::read_other_responses(
  path = "./output/other",
  dataset = clean_data$clean_dataset,
  uuid_column = "_uuid",
  log_uuid_col = "uuid",
  other_db = other_db,
  tool_choices = tool_choices,
  sm_separator = "/",
  file_pattern = "_other_responses_edited\\.xlsx$",
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
  output_path = "./output/P2P_cleaning_output.xlsx",
  project_name = "4Mi East Africa — Round 12",
  data_collection_round = "Round 12 — Q1 2025",
  prepared_by = "MMC Data Team"
)
