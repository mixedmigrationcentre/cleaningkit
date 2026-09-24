# Apply a Validated Cleaning Log to the Raw Dataset

Applies every change specified in a filled and validated cleaning log to
the raw dataset, producing a clean dataset and an audit trail of every
modification made.

## Usage

``` r
apply_cleaning_log(
  raw_dataset,
  cleaning_log,
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
```

## Arguments

- raw_dataset:

  A dataframe — the original raw data to be cleaned.

- cleaning_log:

  A dataframe containing the validated cleaning log, as returned by
  [`read_cleaning_log()`](read_cleaning_log.md) and checked by
  [`evaluate_cleaning_log()`](evaluate_cleaning_log.md). Must have no
  remaining issues in the evaluation log before being passed here.

- raw_uuid_column:

  Name of the uuid column in `raw_dataset`. Default `"_uuid"`.

- log_uuid_col:

  Name of the uuid column in `cleaning_log`. Default `"Survey UUID"`.

- log_question_col:

  Name of the question/column column in `cleaning_log`. Default
  `"Question number"`.

- log_new_value_col:

  Name of the new-value column in `cleaning_log`. Default `"New value"`.

- log_action_col:

  Name of the action-type column in `cleaning_log`. Default
  `"Action taken"`.

- change_response_values:

  Character vector of action values that mean "change this cell to
  new_value". Default covers all three that map to `change_response`:
  `c("recoded", "addition", "other")`.

- blank_response_values:

  Character vector of action values that mean "blank this cell (set to
  NA)". Default `"delete_data_point"`.

- remove_survey_values:

  Character vector of action values that mean "remove the entire
  survey". Default `"discard"`.

- no_action_values:

  Character vector of action values to skip entirely. Default
  `"no_action"`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of `raw_dataset` is
  preserved as the ONA label/description row and never modified by the
  cleaning log. Changes are only applied to rows 2+.

- restore_types:

  Logical. If `TRUE` (the default),
  [`type.convert()`](https://rdrr.io/r/utils/type.convert.html) is
  called on the cleaned dataset to restore numeric and logical column
  types that were coerced to character.

- verbose:

  Logical. If `TRUE` (the default), a summary message is printed on
  completion.

## Value

A list with two elements:

- clean_dataset:

  The cleaned dataframe.

- audit_log:

  A dataframe recording every change applied, with columns `uuid`,
  `question`, `action`, `value_before`, and `value_after`.

## Details

**Action types and what they do:**

- `recoded`:

  Sets the cell at `[uuid, question]` to `new_value`. Maps to
  `change_response`.

- `addition`:

  Sets the cell at `[uuid, question]` to `new_value` (filling a
  previously empty cell). Maps to `change_response`.

- `other`:

  Sets the cell at `[uuid, question]` to `new_value`. Maps to
  `change_response`.

- `delete_data_point`:

  Sets the cell at `[uuid, question]` to `NA`. Maps to `blank_response`.

- `discard`:

  Removes the entire survey (row) with this uuid from the dataset. Maps
  to `remove_survey`.

- `no_action`:

  Row is skipped; no change is made.

**Column-wide changes:** if `uuid` is `"all_data"` (case- insensitive),
the change is applied to every row of `question` rather than one
specific survey. This mirrors the original behaviour for bulk
corrections.

**Audit trail:** the returned list includes an `audit_log` dataframe
showing every cell-level change made (uuid, question, action, old value
actually in the dataset, new value written). This is separate from the
cleaning log that was passed in and reflects what was actually done.

**Type restoration:** after all changes are applied, `type.convert` is
used to restore numeric, logical, and integer columns that were coerced
to character during the cleaning process.
