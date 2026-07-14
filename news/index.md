# Changelog

## cleaningkit 2026.07.0

### New features and validations

- Added [`validate_duration()`](../reference/validate_duration.md) to
  check survey durations.
- Added
  [`validate_completeness()`](../reference/validate_completeness.md) to
  flag surveys with too few answers.
- Added [`validate_refused()`](../reference/validate_refused.md) to
  identify excessive refused answers.
- Added
  [`validate_interview_time()`](../reference/validate_interview_time.md)
  to check for implausible interview times.
- Added
  [`validate_country_of_interview()`](../reference/validate_country_of_interview.md)
  to check if the country of interview matches nationality or journey
  start.
- Added
  [`validate_back_to_back()`](../reference/validate_back_to_back.md) to
  flag suspiciously short gaps between interviews by the same
  enumerator.
- Added [`validate_duplicates()`](../reference/validate_duplicates.md)
  to detect soft duplicates based on differing column counts.
- Added
  [`validate_duplicate_questions()`](../reference/validate_duplicate_questions.md)
  to flag specific questions where an enumerator repeatedly gives the
  same answer.
- Added
  [`validate_logical_with_list()`](../reference/validate_logical_with_list.md)
  for external logical checks.

### Data processing and output

- Added [`create_cleaning_log()`](../reference/create_cleaning_log.md)
  and [`create_combined_log()`](../reference/create_combined_log.md) to
  handle validation logs.
- Added functions to prepare and save other responses
  ([`prepare_other_responses()`](../reference/prepare_other_responses.md),
  [`save_other_responses()`](../reference/save_other_responses.md),
  [`read_other_responses()`](../reference/read_other_responses.md)).
- Added [`read_cleaning_log()`](../reference/read_cleaning_log.md),
  [`evaluate_cleaning_log()`](../reference/evaluate_cleaning_log.md),
  and [`apply_cleaning_log()`](../reference/apply_cleaning_log.md) to
  process and apply data cleaning steps.
- Added
  [`apply_other_responses()`](../reference/apply_other_responses.md) to
  integrate cleaned “other” responses.
- Added
  [`combine_reviewed_logs()`](../reference/combine_reviewed_logs.md) to
  merge main cleaning and other-response logs.
- Added [`review_cleaned_data()`](../reference/review_cleaned_data.md)
  to verify cleaning applications.
- Added [`export_final_output()`](../reference/export_final_output.md)
  for generating the final Excel workbook.
