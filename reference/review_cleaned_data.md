# Review Cleaned Data Against the Raw Dataset and Cleaning Log

Compares the raw dataset, clean dataset, and combined cleaning log to
verify that every change documented in the log was actually applied, and
that no undocumented changes slipped through. Returns a single dataframe
listing every discrepancy found, ready for investigation before
sign-off.

## Usage

``` r
review_cleaned_data(
  raw_dataset,
  clean_dataset,
  cleaning_log,
  raw_uuid_column = "_uuid",
  clean_uuid_column = "_uuid",
  log_uuid_col = "Survey UUID",
  log_question_col = "Question number",
  log_new_value_col = "New value",
  log_old_value_col = "Old value",
  log_action_col = "Action taken",
  change_response_values = c("recoded", "addition", "other"),
  blank_response_values = "delete_data_point",
  discard_values = "discard",
  no_action_values = "no_action",
  columns_to_skip = c("start", "end", "today", "deviceid", "uuid", "_uuid", "id", "_id",
    "submission_time", "_submission_time", "index", "_index", "df_name", "username",
    "simserial", "phonenumber", "_submission_time", "check_binding", "evaluation_issue"),
  skip_label_row = TRUE,
  verbose = TRUE
)
```

## Arguments

- raw_dataset:

  The original raw dataset.

- clean_dataset:

  The cleaned dataset to verify.

- cleaning_log:

  The combined cleaning log as produced by
  [`combine_reviewed_logs()`](combine_reviewed_logs.md) or
  [`create_cleaning_log()`](create_cleaning_log.md).

- raw_uuid_column:

  Name of the uuid column in `raw_dataset`. Default `"_uuid"`.

- clean_uuid_column:

  Name of the uuid column in `clean_dataset`. Default `"_uuid"`.

- log_uuid_col:

  Name of the uuid column in `cleaning_log`. Default `"Survey UUID"`.

- log_question_col:

  Name of the question column in `cleaning_log`. Default
  `"Question number"`.

- log_new_value_col:

  Name of the new-value column. Default `"New value"`.

- log_old_value_col:

  Name of the old-value column. Default `"Old value"`.

- log_action_col:

  Name of the action-type column. Default `"Action taken"`.

- change_response_values:

  Action values meaning "cell changed". Default
  `c("recoded", "addition", "other")`.

- blank_response_values:

  Action values meaning "cell blanked". Default `"delete_data_point"`.

- discard_values:

  Action values meaning "survey removed". Default `"discard"`.

- no_action_values:

  Action values meaning "no change". Default `"no_action"`.

- columns_to_skip:

  Column names to exclude from the undocumented-change check (e.g.
  system columns). Default covers common ONA metadata columns.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of both `raw_dataset`
  and `clean_dataset` is treated as the ONA label/description row and
  excluded from all comparisons.

- verbose:

  Logical. If `TRUE` (the default), a summary of findings is printed on
  completion.

## Value

A dataframe with columns `uuid`, `question`, `action_in_log`,
`old_value`, `new_value_log`, `new_value_clean`, `check_type`, and
`comment`. Zero rows means the clean dataset perfectly matches the
cleaning log.

## Details

**Checks performed:**

- uuid in discard log still present in clean data:

  A survey marked `discard` was not removed from the clean dataset.

- uuid in discard log not in raw data:

  The discard log references a uuid that doesn't exist in the raw
  dataset — probably a typo.

- uuid in cleaning log also in discard log:

  A cell-level change was logged for a survey that is also marked for
  discard — contradictory.

- no_action with mismatched new/old value:

  A `no_action` row has a `New value` that differs from `Old value` —
  the reviewer may have accidentally changed something.

- change not applied:

  The `New value` in the cleaning log does not match the actual value in
  the clean dataset — the cleaning step missed this row.

- undocumented change:

  A value differs between raw and clean datasets but has no
  corresponding row in the cleaning log.

- new value mismatch:

  The cleaning log says the new value should be X but the clean dataset
  has Y.

- duplicate uuid+question:

  The same `uuid + question` appears more than once in the cleaning log
  with different `New value`s — ambiguous.

- uuid missing from raw data:

  The cleaning log references a uuid that does not exist in the raw
  dataset.

- question missing from raw data:

  The cleaning log references a column that does not exist in the raw
  dataset.

**Action type mapping (your log → internal):**

- `recoded`, `addition`, `other`:

  Cell changed to `New value` — verified against the clean dataset.

- `delete_data_point`:

  Cell set to `NA`/blank.

- `discard`:

  Entire survey removed.

- `no_action`:

  No change — `New value` should equal `Old value`.
