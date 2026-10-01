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
#
# CUSTOMISE: base_path is the project root - here::here() keeps it portable.
# extra_folders adds any site-specific folders, e.g. c("output/archive").
# this call also copies logical_checklist.xlsx into resources/ - use
# copy_templates = FALSE to skip it, or
# templates = c("logical_checklist.xlsx" = "resources/my_checks.xlsx")
# to copy it under a different name. an existing file is never overwritten
# unless overwrite_templates = TRUE
#----------------------------------

cleaningkit::setup_project_folders(
  base_path = here::here(),
  extra_folders = NULL # any site-specific extras
)

#----------------------------------
# Read tool data
#
# CUSTOMISE: the path to your XLSForm. both functions read the same file -
# read_tool_survey() the `survey` sheet, read_tool_choices() the `choices`
# sheet
#----------------------------------

tool_survey <- cleaningkit::read_tool_survey("./resources/tool.xlsx")
tool_choices <- cleaningkit::read_tool_choices("./resources/tool.xlsx")

#----------------------------------
# create other response db
# in case other label has not been picked up, use
# the argument other_text_types = c("Q31_2") and add the "other" question that was missed
#
# CUSTOMISE: other_text_types on get_other_labels() - add any "other" text
# question the tool did not detect automatically. nothing else here is
# survey-specific
#----------------------------------

other_labels <- cleaningkit::get_other_labels(
  tool_survey = tool_survey
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
#
# the first round needs no filtering: with a single export and no ledger
# there is nothing to compare against, so filter_new_records() renames that
# file to data.xlsx, says the step was skipped and returns - it no longer
# errors, and the call can safely be left in the script from round one
#
# CUSTOMISE: data_folder and output_name if your exports do not live at
# ./data/data.xlsx; uuid_column if the id column is not "_uuid";
# use_ledger = FALSE to compare only against the previous file instead of
# the running ledger; archive = FALSE to leave the inputs where they are;
# rename_single_file = FALSE to keep the original file name on the first
# round
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
  rename_single_file = TRUE,
  verbose = TRUE
)

#----------------------------------
# Read raw data
#
# the file filter_new_records() left in ./data - the new records on a later
# round, the renamed export on the first one
#
# CUSTOMISE: filename, if your export lives somewhere else or you changed
# output_name above
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
#
# CUSTOMISE: questions to restrict the output to specific "other" questions
# (leave it out for all of them), and extra_columns for the columns the
# reviewer should see next to each response, e.g. c("username", "Q13")
#----------------------------------

other_responses_df <- cleaningkit::prepare_other_responses(
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
#
# CUSTOMISE: lower_bound and upper_bound in minutes, to match how long your
# interview actually takes; flag_above_upper; column_to_check if your
# duration column is not "_duration"
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
#
# CUSTOMISE: min_content_cells - roughly the number of questions a complete
# interview answers, so set it from your own tool; metadata_cols to change
# which columns are ignored in the count
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
#
# CUSTOMISE: max_refused for how many refusals a survey may contain, and
# refused_value if your tool labels the option something other than
# "Refused"
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
#
# CUSTOMISE: threshold_hours and threshold_mins for the smallest acceptable
# gap between two interviews by the same enumerator; enumerator_column,
# start_column and end_column for your tool's column names; gap_from for
# which timestamps the gap is measured between
#----------------------------------

back_to_back_log <- cleaningkit::validate_back_to_back(
  dataset = raw_data,
  uuid_column = "_uuid",
  enumerator_column = "username",
  start_column = "start",
  end_column = "end",
  log_name = "back_to_back_log",
  threshold_hours = 0,
  threshold_mins = 3,
  gap_from = c("end", "start"),
  skip_label_row = TRUE
)

#----------------------------------
# validate country of interview
# flags if the respondent is being interviewed in their country of nationality
#
# CUSTOMISE: the three question codes - country_interview_col,
# nationality_col and journey_start_col. these are 4Mi codes and will be
# different in any other tool
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
#
# CUSTOMISE: earliest_hour and latest_hour for the hours interviewing is
# plausible in your context; time_column for your timestamp column;
# flag_missing = TRUE to also log surveys with no time recorded
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
#
# CUSTOMISE: threshold - the lower the number, the stricter the check;
# idnk_value to match your tool's "Don't know" label; enumerator_column for
# your column name; return_all_results = TRUE for a row per survey rather
# than only the flagged ones
#----------------------------------
# similar_surveys_log <- raw_data %>%
#   cleaningkit::validate_similar_surveys(
#     tool_survey = tool_survey,
#     enumerator_column = "username",
#     idnk_value = "Don't know",
#     sm_separator = "/",
#     # flags a survey whose closest neighbour differs in at most this many columns
#     threshold = 7,
#     # TRUE returns a row for every survey, not only the flagged ones
#     return_all_results = FALSE
#   )

#----------------------------------
# validate outliers
# looks through all integer questions and checks for any outliers
# or checks on specific columns
# add columns_to_check = c("QN7_a") with you integer question to check for only that question
#
# CUSTOMISE: columns_to_check to check named integer questions only (drop it
# to scan them all); strongness_factor to loosen or tighten what counts as
# an outlier; min_unique_values to skip near-constant questions;
# columns_to_skip to exclude questions you do not want checked
#----------------------------------
outliers_log <- raw_data %>%
  cleaningkit::validate_outliers(
    columns_to_check = c("QN7_a"),
    tool_survey = tool_survey,
    strongness_factor = 2,
    min_unique_values = 5,
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
#
# CUSTOMISE: country_question and city_question for your tool;
# city_radius_km for how far from the claimed city still counts as
# acceptable; check_country, check_city and flag_missing_gps to switch
# individual checks off; lat_column, lon_column and location_column if your
# GPS columns are named differently
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
# system.file("extdata", "logical_checklist.xlsx", package = "cleaningkit")
#
# CUSTOMISE: nothing in this call - the checks themselves are what you edit,
# and they live in ./resources/logical_checklist.xlsx (one row per check).
# change the path below only if you renamed the checklist, and the four
# *_column arguments only if you renamed its columns
#----------------------------------
logical_list <- read.xlsx(
  "./resources/logical_checklist.xlsx",
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
#
# CUSTOMISE: the list below - drop any log you did not run, and add any you
# did. the names must match the objects created above
#----------------------------------

list_of_log_all <- c(
  duration_log,
  completeness_log,
  refused_log,
  back_to_back_log,
  country_of_interview_log,
  interview_time_log,
  interview_location_log,
  # similar_surveys_log,
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
# one file for the reviewer, holding both logs. the tabs come out in the order
# a reviewer works through them:
#   dataset           the checked dataset, flag columns in front
#   cleaning_log      the flagged values to act on
#   other_responses   the "other" text responses to review
#   readme            what each sheet is for, and the codes to use
#   Dropdown_values   backs the other-responses drop-downs
#
# pass `other_responses` and `other_db` and the other-responses sheets are
# added; leave them out and you get exactly what create_cleaning_log() produced.
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
#
# CUSTOMISE: vba for the file type, color_mode and color_columns for the
# highlighting, group_by for how the log is sorted, output_path for the file
# name, and other_enumerator_id for the enumerator column on the
# other-responses sheet. drop other_responses and other_db to produce the
# cleaning log on its own
#----------------------------------

cleaningkit::create_review_workbook(
  vba = TRUE,
  write_list = combined_log,
  other_responses = other_responses_df,
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
