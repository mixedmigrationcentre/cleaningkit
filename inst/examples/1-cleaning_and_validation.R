#----------------------------------
# Initialize the package and
# all required packages
#----------------------------------

rm(list = ls())
library(cleaningkit)

cleaningkit::load_packages()

#----------------------------------
# Setup project folders
# Run once
#----------------------------------

setup_project_folders(
  base_path = here::here(),
  extra_folders = NULL # any site-specific extras
)

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
# filter read raw data
# perform a filter on the raw dataset for multiple cleaning logs outputs
#----------------------------------
#----------------------------------
# keep only the newly collected records
# run this when validation happens several times during one data collection
# round. drop the new ONA download into ./data next to the file left by the
# previous round; the two are compared on `_uuid`, everything already
# validated is removed, the inputs are archived to ./data/archive and the
# new records are written to ./data/data.xlsx
# a running ./data/processed_uuids.csv ledger makes sure records from earlier
# rounds cannot come back from the third round onwards
# skip this section for the first round, or when the whole dataset is being
# validated in one go
#----------------------------------

cleaningkit::filter_new_records(
  data_folder = "./data",
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  output_name = "data.xlsx",
  sheet = 1,
  use_ledger = TRUE,
  ledger_name = "processed_uuids.csv",
  archive = TRUE,
  archive_folder = "archive",
  verbose = TRUE
)

#----------------------------------
# Read raw data
#----------------------------------

raw_data <- cleaningkit::read_raw_data(
  filename = "./data/data.xlsx",
  tool_survey = tool_survey
)

#----------------------------------
# prepare other responses
# add the other responses questions you to be included in the output
# in the question argument.
# for example
# questions = c(
#     "Q34_1",
#     "Q35_1",
#     "Q37_1",
#     "Q38_1",
#     "Q39_1",
#     "Q41_1",
#     "Q33_1"
#   )
# the result is written into the same workbook as the cleaning log further
# down, by create_review_workbook() - there is no separate file any more
#----------------------------------

df <- cleaningkit::prepare_other_responses(
  uuid_column = "_uuid",
  raw_data = raw_data,
  other_db = other_db,
  tool_choices = tool_choices,
  extra_columns = c("username")
)

#----------------------------------
# validate duration
# flags surveys shorter than lower_bound (15 mins).
# surveys longer than upper_bound are NOT flagged by default - long interviews
# are usually legitimate and only inflate the log - set flag_above_upper = TRUE
# to log those as well
#----------------------------------

duration_log <- cleaningkit::validate_duration(
  dataset = raw_data,
  column_to_check = "_duration",
  uuid_column = "_uuid",
  log_name = "duration_log",
  lower_bound = 15,
  upper_bound = 60,
  flag_above_upper = FALSE,
  skip_label_row = TRUE
)

#----------------------------------
# validate completeness
# metadata_cols holds the metadata columns ignored when counting answers
# c("start","end","today","deviceid","username","simserial","phonenumber",
#   "uuid","_uuid","id","_id","submission_time","_submission_time",
#   "index","_index","df_name")
# pass your own metadata_cols to change that list
#----------------------------------

completeness_log <- cleaningkit::validate_completeness(
  dataset = raw_data,
  uuid_column = "_uuid",
  log_name = "completeness_log",
  min_content_cells = 100,
  skip_label_row = TRUE
)

#----------------------------------
# validate refused
# flags any surveys that have more than 6 "Refused" be default
#----------------------------------

refused_log <- cleaningkit::validate_refused(
  dataset = raw_data,
  uuid_column = "_uuid",
  log_name = "refused_log",
  max_refused = 6,
  refused_value = "Refused",
  skip_label_row = TRUE
)

#----------------------------------
# validate back to back interviews
# flags any interviews from the same enumerator if they are 10 mins apart by default
#----------------------------------

back_to_back_log <- cleaningkit::validate_back_to_back(
  dataset = raw_data,
  uuid_column = "_uuid",
  enumerator_column = "username",
  start_column = "start",
  end_column = "end",
  log_name = "back_to_back_log",
  threshold_hours = 0,
  threshold_mins = 10,
  gap_from = c("end", "start"),
  skip_label_row = TRUE
)

#----------------------------------
# validate country of interview
# flags if the respondent is being interviewed in their country of nationality
#----------------------------------

country_of_interview_log <- cleaningkit::validate_country_of_interview(
  dataset = raw_data,
  uuid_column = "_uuid",
  country_interview_col = "Q13",
  nationality_col = "Q31",
  journey_start_col = "Q41",
  log_name = "country_of_interview_log",
  skip_label_row = TRUE
)

#----------------------------------
# validate time of interview
# flags the earliest and latest times of interview
# by default earliest hour is 5am and latest hour is 10pm
#----------------------------------

interview_time_log <- cleaningkit::validate_interview_time(
  dataset = raw_data,
  uuid_column = "_uuid",
  time_column = "start",
  log_name = "interview_time_log",
  earliest_hour = 5,
  latest_hour = 22,
  flag_missing = FALSE,
  skip_label_row = TRUE
)

#----------------------------------
# validate similar surveys
# groups data by enumerator and checks surveys which are similar
#----------------------------------
similar_surveys_log <- raw_data %>%
  cleaningkit::validate_similar_surveys(
    tool_survey = tool_survey,
    enumerator_column = "username",
    idnk_value = "Don't know",
    sm_separator = "/",
    # flags a survey whose closest neighbour differs in at most this many columns
    threshold = 7,
    # TRUE returns a row for every survey, not only the flagged ones
    return_all_results = FALSE
  )

#----------------------------------
# validate outliers
# looks through all integer questions and checks for any outliers
# or checks on specific columns
# add columns_to_check = c("Q141_3") with you integer question to check for only that question
#----------------------------------
outliers_log <- raw_data %>%
  cleaningkit::validate_outliers(
    # leave columns_to_check = NULL to check every numeric column
    columns_to_check = NULL,
    # tool_survey lets the function pick the numeric questions from the tool
    tool_survey = tool_survey,
    strongness_factor = 3,
    min_unique_values = 5,
    remove_sm_binary = TRUE, # skip the 0/1 select_multiple columns
    sm_separator = "/",
    columns_to_skip = NULL
  )

#----------------------------------
# validate interview location
# checks the GPS point of each in-person interview against the country
# and the city the respondent claims the interview took place in.
# the country check needs the {rnaturalearthdata} package, and the city
# check geocodes each unique city + country pair once via OpenStreetMap
# (Nominatim), so an internet connection is required
#----------------------------------

interview_location_log <- cleaningkit::validate_interview_location(
  dataset = raw_data,
  uuid_column = "_uuid",
  lat_column = "_location_latitude",
  lon_column = "_location_longitude",
  # raw ONA geopoint column ("lat lon altitude precision"), used when the
  # split lat/lon columns are empty or unusable
  location_column = "location",
  country_question = "Q13",
  city_question = "Q14",
  log_name = "interview_location_log",
  city_radius_km = 75,
  check_country = TRUE,
  check_city = TRUE,
  flag_missing_gps = TRUE,
  nominatim_delay_s = 1,
  skip_label_row = TRUE
)

#----------------------------------
# validate logical
# reads the logical excel sheets and uses that for validating the survey
# a ready-made template of the checklist ships with the package, see:
# system.file("extdata", "logical_checklist_example.xlsx", package = "cleaningkit")
#----------------------------------
logical_list <- read.xlsx(
  "./resources/logical_checklist_example.xlsx",
  sheet = 1
)

logical_check_log <- raw_data %>%
  cleaningkit::validate_logical_with_list(
    list_of_check = logical_list,
    check_id_column = "check_id",
    check_to_perform_column = "check_to_perform",
    columns_to_clean_column = "columns_to_clean",
    description_column = "description"
  )

#----------------------------------
# combine logs
#----------------------------------

list_of_log_all <- c(
  duration_log,
  completeness_log,
  refused_log,
  back_to_back_log,
  country_of_interview_log,
  interview_time_log,
  interview_location_log,
  similar_surveys_log,
  outliers_log,
  logical_check_log
)

combined_log <- cleaningkit::create_combined_log(
  list_of_log = list_of_log_all,
  dataset_name = "checked_dataset"
)

#----------------------------------
# create the review workbook
#
# one file for the reviewer, holding both logs:
#   cleaning_log      the flagged values to act on
#   dataset           the checked dataset, flag columns in front
#   readme            what each sheet is for, and the codes to use
#   other_responses   the "other" text responses to review
#   Dropdown_values   backs the other-responses drop-downs
#
# pass `other_responses` and `other_db` and the last two sheets are added;
# leave them out and you get exactly what create_cleaning_log() produced.
#
# the row colours on the cleaning_log sheet are controlled with `color_mode`:
#   "on"      -> the whole row is coloured by check_binding
#   "partial" -> default, only the columns listed in `color_columns`
#   "off"     -> no colouring at all
# the header keeps the same MMC formatting in all three cases
#
# vba = FALSE -> plain .xlsx
# vba = TRUE  -> macro-enabled .xlsm, so give the path an .xlsm extension
#                (an .xlsx path is corrected to .xlsm with a message)
#
# flag_columns puts the check flags at the front of the `dataset` sheet, so a
# reviewer can filter on them; group_by = "issue" sets the column the log is
# sorted and coloured by
#----------------------------------

cleaningkit::create_review_workbook(
  vba = TRUE,
  write_list = combined_log,
  other_responses = df,
  other_db = other_db,
  other_enumerator_id = "username",
  color_mode = "partial",
  color_columns = c("old_value"),
  group_by = "issue",
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsx"
  )
)
