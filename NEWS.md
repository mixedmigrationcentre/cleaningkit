# cleaningkit (development version)

## Other responses
* `prepare_other_responses()` now fills **`selected_choices` for `select_one`
  questions** as well. The column was populated only for `select_multiple`, so a
  reviewer scanning the sheet saw it blank on every `select_one` row and could
  not tell a missing lookup from a question type that simply never wrote one. A
  `select_one` "other" response can only exist because the respondent picked the
  question's own "other" option, so that option (`other_db$option_other`) is
  written, resolved to its label in `tool_choices` &mdash; it reads exactly as in
  the tool (`Other`, `Other (please specify)`, the Arabic label) and goes through
  the same resolver and the same `preferred_language` /
  `label_language_fallback` settings as `select_multiple`. When the option code
  is missing or cannot be resolved, the literal `Other` is written, so the cell
  is never blank on a `select_one` row.
* `select_multiple` behaviour is unchanged: every selected choice, resolved to
  labels and separated by `";\n"`. Rows whose parent question is neither type
  (e.g. a plain `text` question) still keep `NA`.
* `save_other_responses()` needed no change &mdash; it writes and styles
  `selected_choices` as an ordinary column, so the newly filled cells appear
  with no change to the dropdowns or the reviewer columns.

## Cleaning log fixes
* `create_cleaning_log()` no longer errors on an **empty combined log** &mdash; a
  round where no check flagged anything. The reviewer columns left blank for
  review were built as scalars, which recycle into a log with rows but not into
  one with none, so the call failed with "arguments imply differing number of
  rows". They are now built at the log's own length.

## Check flags on the dataset sheet
* `create_cleaning_log()` and `create_cleaning_log_vba()` now prepend a block of
  helper columns to the `dataset` sheet &mdash; **duration**, **completeness**,
  **refused**, **back to back** and **similarity** &mdash; one per survey-level
  check. Each carries, for that record's uuid, the `old_value` of every
  cleaning-log row the matching check raised (the duration in minutes, the count
  of non-empty cells, the count of refused responses, the interview start time,
  the number of similar columns) and is blank when the check did not flag the
  survey. A reviewer weighing whether to keep or discard an interview can filter
  on one column or several at once and cross-check the flagged surveys against
  their raw answers without leaving the sheet.
* Rows are matched through `check_binding`, whose leading segment names the
  check that raised them, so any combination of `validate_*` functions works
  with no further configuration. Several hits for one record are joined with
  `flag_separator` (default `" | "`).
* **duration**, **completeness** and **refused** show the log's `old_value`,
  which speaks for itself. **back to back** and **similarity** show the `issue`
  instead: a bare interview start time, or a bare count of similar columns,
  tells a reviewer nothing without the gap, the threshold, the enumerator and
  the other survey involved &mdash; all of which the issue names. Any column can
  be switched either way with `list(prefixes = ..., value = "issue")` or
  `value = "old_value"`.
* The **similarity** label row reads `Flagged by: similar_surveys_log,
  similar_questions_log` rather than the internal binding prefixes
  (`soft_duplicate`, `dup_q`). Any column's label can be set with
  `list(prefixes = ..., label = ...)`.
* The new `flag_columns` argument controls which columns are written and which
  checks feed them; `ck_flag_column_defaults()` returns the defaults to extend,
  and `NULL` writes the `dataset` sheet exactly as before. A flag column whose
  header collides with a real survey question is renamed with a `_flag` suffix
  and a warning, rather than shadowing it.
* The five headers carry an MMC dark-blue fill (`flag_header_fill_color`,
  `#003D58`) instead of the teal used for the ONA headers, so the block is not
  mistaken for exported data. Everything below the header row keeps the
  ordinary body formatting.
* In the macro-enabled workbook these columns are exempt from change capture:
  editing one appends nothing to the cleaning log. Their headers are written to
  `_ck_config` as the new `ignore_columns` key. **This needs a rebuilt
  `inst/extdata/cleaningkit_vba.bin`** &mdash; see `inst/vba/README.md`; until
  then the flag columns behave like any other dataset column.

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
