# cleaningkit

`cleaningkit` is a simple R package built to help clean and validate
survey data (especially Ona surveys).

## Installation

You can grab the v2026.07.0 version from GitHub using `pak`:

``` r

# install.packages("pak")
pak::pak("iAthmanMMC/cleaningkit")
```

## How to use it

Before running any other functions, you need to run
[`load_packages()`](reference/load_packages.md). This ensures that all
required dependencies for `cleaningkit` are installed and loaded
properly.

``` r

library(cleaningkit)
load_packages()
```

### Data Cleaning and Validation

The package provides a suite of `validate_*` functions to run various
data quality checks. Each function returns a list containing the checked
dataset and a log of flagged issues.

- **[`validate_duration()`](reference/validate_duration.md)**: Checks if
  the survey duration falls within an acceptable time range.
- **[`validate_completeness()`](reference/validate_completeness.md)**:
  Flags surveys that have fewer than a specified number of answered
  questions.
- **[`validate_refused()`](reference/validate_refused.md)**: Identifies
  surveys with an excessive number of “Refused” answers.
- **[`validate_logical_with_list()`](reference/validate_logical_with_list.md)**:
  Runs a batch of logical checks defined in an external checklist
  against the dataset.
- **[`validate_interview_time()`](reference/validate_interview_time.md)**:
  Flags interviews conducted at implausible times of the day (e.g.,
  middle of the night).
- **[`validate_duplicates()`](reference/validate_duplicates.md)**:
  Detects suspiciously similar surveys (soft duplicates) based on
  differing column counts.
- **[`validate_duplicate_questions()`](reference/validate_duplicate_questions.md)**:
  Flags specific questions where an enumerator has repeatedly recorded
  the exact same answer across multiple surveys.
- **[`validate_country_of_interview()`](reference/validate_country_of_interview.md)**:
  Flags cases where the interview country matches the respondent’s
  nationality or journey start.
- **[`validate_back_to_back()`](reference/validate_back_to_back.md)**:
  Flags interviews conducted by the same enumerator with suspiciously
  short or negative gaps between them.

Here is a quick look at how you can load your data and run a few
validation checks:

``` r

library(cleaningkit)

# Load your raw data and tool survey schema
raw_data <- read_raw_data("path/to/data.xlsx", tool_survey = survey_sheet)

# Run validations (each step passes the result to the next)
checked_data <- raw_data |>
  # 1. Survey duration makes sense (e.g. between 15 and 60 minutes)
  validate_duration(column_to_check = "_duration", lower_bound = 15, upper_bound = 60) |>
  # 2. Minimum of 100 answered questions
  validate_completeness(min_content_cells = 100) |>
  # 3. Maximum of 6 "Refused" answers
  validate_refused(max_refused = 6) |>
  # 4. Interviews conducted at a plausible time (e.g. between 5am and 10pm)
  validate_interview_time(earliest_hour = 5, latest_hour = 22) |>
  # 5. Suspiciously similar responses (soft duplicates differing in <= 7 columns)
  validate_duplicates(tool_survey = survey_sheet, threshold = 7) |>
  # 6. Duplicated answers for specific questions by the same enumerator
  validate_duplicate_questions(questions_to_check = c("Q161_1", "Q162_1")) |>
  # 7. Country of interview shouldn't match nationality or journey start
  validate_country_of_interview() |>
  # 8. Implausible back-to-back interviews (gap < 10 minutes)
  validate_back_to_back(threshold_mins = 10) |>
  # 9. External logical checks (requires a checklist dataframe)
  validate_logical_with_list(list_of_check = logical_list,
    check_id_column = "check_id",
    check_to_perform_column = "check_to_perform",
    columns_to_clean_column = "columns_to_clean",
    description_column = "description")

# Look at the issues logged for any of the checks
print(checked_data$duration_log)
print(checked_data$back_to_back_log)
```

### Combining and Exporting Logs

After running the validation checks, you can combine all the individual
logs and save them into an Excel file for review and follow-up:

``` r

#----------------------------------
# combine logs
#----------------------------------

# Since all logs are stored in the `checked_data` list, 
# you can pass it directly to create a single combined log:
combined_log <- cleaningkit::create_combined_log(
  list_of_log = checked_data,
  dataset_name = "checked_dataset"
)

#----------------------------------
# create cleaning log
#----------------------------------

cleaningkit::create_cleaning_log(
  write_list = combined_log,
  output_path = paste0(
    "path/to/output/",
    Sys.Date(),
    "_follow-ups.xlsx"
  )
)
```

### Creating Other Responses

You can extract and prepare “other” responses from your dataset using
two functions:

- **[`prepare_other_responses()`](reference/prepare_other_responses.md)**:
  Combines other responses from all sheets into a single dataframe ready
  for use with
  [`save_other_responses()`](reference/save_other_responses.md). You can
  optionally pass a character vector of specific question names to the
  `questions` parameter if you only want to process a subset of
  questions.
- **[`save_other_responses()`](reference/save_other_responses.md)**:
  This function saves the prepared other responses into an Excel
  workbook with specific formatting and data validation.

``` r

# Prepare the other responses dataframe
other_responses_df <- prepare_other_responses(
  raw_data = raw_data,
  other_db = other_db,
  tool_choices = choices_sheet
)

# Save to an Excel workbook for review
save_other_responses(
  df = other_responses_df,
  save_location = "output"
)
```

### Apply Cleaning

Once the cleaning logs and other responses have been reviewed and
edited, you can apply these changes to produce the final clean dataset.

- **[`read_cleaning_log()`](reference/read_cleaning_log.md)**: Reads the
  edited cleaning log from an Excel file and removes duplicates.
- **[`evaluate_cleaning_log()`](reference/evaluate_cleaning_log.md)**:
  Evaluates the cleaning log for correctness, ensuring UUIDs and actions
  match the raw data.
- **[`apply_cleaning_log()`](reference/apply_cleaning_log.md)**: Applies
  the actions from the cleaning log directly to the raw dataset to
  produce a clean dataset.
- **[`read_other_responses()`](reference/read_other_responses.md)**:
  Reads and processes edited “other” responses from an Excel file.
- **[`apply_other_responses()`](reference/apply_other_responses.md)**:
  Integrates the cleaned “other” responses into the dataset.
- **[`combine_reviewed_logs()`](reference/combine_reviewed_logs.md)**:
  Merges the main cleaning log and the other-responses log into a single
  comprehensive log.
- **[`review_cleaned_data()`](reference/review_cleaned_data.md)**:
  Compares the cleaned dataset against the log to verify all changes
  were successfully applied.
- **[`export_final_output()`](reference/export_final_output.md)**:
  Creates a final Excel workbook containing the raw data, clean data,
  and the comprehensive cleaning log.

``` r

#----------------------------------
# apply cleaning
#----------------------------------
cleaning_log <- read_cleaning_log(path = "path/to/log.xlsx", raw_dataset = raw_data)
evaluated_log <- evaluate_cleaning_log(cleaning_log = cleaning_log, raw_dataset = raw_data)
cleaned_data_list <- apply_cleaning_log(raw_dataset = raw_data, cleaning_log = evaluated_log$cleaning_log)

other_log <- read_other_responses(path = "path/to/other.xlsx", dataset = raw_data, other_db = other_db, tool_choices = choices_sheet)
cleaned_data_list <- apply_other_responses(dataset = cleaned_data_list$clean_dataset, other_log = other_log)

#----------------------------------
# combine cleaning logs
#----------------------------------
final_log <- combine_reviewed_logs(main_log = evaluated_log$cleaning_log, other_log = other_log, dataset = raw_data)

#----------------------------------
# review clean dataset
#----------------------------------
review_log <- review_cleaned_data(raw_dataset = raw_data, clean_dataset = cleaned_data_list$dataset, cleaning_log = final_log)

#----------------------------------
# create final workbook
#----------------------------------
export_final_output(
  raw_dataset = raw_data, 
  clean_dataset = cleaned_data_list$dataset, 
  combined_log = final_log, 
  output_path = "output/final_output.xlsx"
)
```
