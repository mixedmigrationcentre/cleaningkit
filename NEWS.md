# cleaningkit (development version)

## Duration check
* `validate_duration()` no longer logs surveys that run **longer** than
  `upper_bound`. Long surveys are normally valid and only added rows to the
  cleaning log. The new `flag_above_upper` argument (default `FALSE`) restores
  the old behaviour when set to `TRUE`; surveys below `lower_bound` are still
  flagged as before.

## Similar-answer check
* **Breaking:** `validate_duplicate_questions()` has been renamed to
  `validate_similar_questions()`, and its default `log_name` is now
  `"similar_questions_log"` (was `"duplicate_questions_log"`). The arguments,
  issue text and `check_binding` format are unchanged.

## Similar-survey check
* **Breaking:** `validate_duplicates()` has been renamed to
  `validate_similar_surveys()`. The arguments, defaults and log shape are
  unchanged &mdash; update the call name only.
* The issue text is now phrased in terms of how many columns *match* rather than
  how many differ, e.g. "Similarity with surveys from enumerator 'x': 226 of 227
  columns are similar from survey <uuid> &mdash; threshold is 30".
* **Breaking:** the log now reports the similar-column count instead of the
  differing-column count: `question` is `"number_similar_columns"` (was
  `"number_different_columns"`) and `old_value` holds that count. `threshold`
  still applies to *differing* columns, so existing calls need no change.

## Cleaning log layout
* `create_cleaning_log()` and `create_cleaning_log_vba()` now group the reviewer
  log by **Issue** by default, so every row raising the same issue sits in one
  contiguous block and a reviewer can work through one kind of problem at a
  time. Blocks still appear in the order each value is first met in the combined
  log, and rows keep their original order inside a block.
* The grouping column is now chosen with the new `group_by` argument, which
  accepts either the raw log names (`"issue"`, `"uuid"`, `"question"`,
  `"old_value"`, `"check_binding"`) or the reviewer-facing headers (`"Issue"`,
  `"Survey UUID"`, `"Enumerator"`, ...), matching case- and
  punctuation-insensitively. `NULL` or `FALSE` keeps the incoming
  check-by-check order.
* **Breaking:** `group_by_uuid` has been removed in favour of `group_by`. Calls
  passing `group_by_uuid = TRUE` should now pass `group_by = "uuid"`, and
  `group_by_uuid = FALSE` becomes `group_by = NULL`.

## Other-response cleaning
* `read_other_responses()` now detects the select-multiple convention from the
  data itself instead of defaulting to a binary (`0`/`1`) export. In an ONA
  label export — where sub-columns are named `Q83/<choice label>`, a selected
  choice holds the choice text and an unselected one is blank — the log now
  writes the choice text and leaves unselected children blank, so
  `apply_other_responses()` no longer introduces `0`/`1` into label data.
  Detection scans every sub-column of the question (previously only the first
  five), then the parent concat column, then the rest of the dataset, and falls
  back to the choice-text convention when nothing indicates a binary export.
* Sub-columns are now matched to choices case- and whitespace-insensitively and
  by either the choice label or the choice code, so questions whose labels are
  single words (e.g. `Q10/Kenya`) are no longer mistaken for coded headers. A
  choice with no matching sub-column now warns instead of silently doing
  nothing.
* The value written to unselect a choice now also follows the export: `"0"`
  only where the data already contains zeros, blank otherwise.

## Round-to-round data preparation
* Added `filter_new_records()` to reduce a cumulative ONA export to the records
  collected since the last validation round, so repeated rounds over a long
  data collection period do not regenerate cleaning log entries that were
  already reviewed. It compares the two files in `data/`, keeps a running
  `processed_uuids.csv` ledger so records from earlier rounds cannot reappear,
  preserves the ONA label row, archives the inputs and writes `data.xlsx`.

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
