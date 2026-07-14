# cleaningkit 2026.07.0

## New features and validations
* Added `validate_duration()` to check survey durations.
* Added `validate_completeness()` to flag surveys with too few answers.
* Added `validate_refused()` to identify excessive refused answers.
* Added `validate_interview_time()` to check for implausible interview times.
* Added `validate_country_of_interview()` to check if the country of interview matches nationality or journey start.
* Added `validate_back_to_back()` to flag suspiciously short gaps between interviews by the same enumerator.
* Added `validate_duplicates()` to detect soft duplicates based on differing column counts.
* Added `validate_duplicate_questions()` to flag specific questions where an enumerator repeatedly gives the same answer.
* Added `validate_logical_with_list()` for external logical checks.

## Data processing and output
* Added `create_cleaning_log()` and `create_combined_log()` to handle validation logs.
* Added functions to prepare and save other responses (`prepare_other_responses()`, `save_other_responses()`, `read_other_responses()`).
* Added `read_cleaning_log()`, `evaluate_cleaning_log()`, and `apply_cleaning_log()` to process and apply data cleaning steps.
* Added `apply_other_responses()` to integrate cleaned "other" responses.
* Added `combine_reviewed_logs()` to merge main cleaning and other-response logs.
* Added `review_cleaned_data()` to verify cleaning applications.
* Added `export_final_output()` for generating the final Excel workbook.
