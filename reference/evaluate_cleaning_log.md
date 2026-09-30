# Evaluate a Filled Cleaning Log

Validates a completed cleaning log before it is applied to the raw
dataset. Catches missing values, invalid action types, logical
inconsistencies, and references to uuids or questions that do not exist
in the raw data, so that errors are surfaced at review time rather than
silently corrupting the clean dataset.

## Usage

``` r
evaluate_cleaning_log(
  cleaning_log,
  raw_dataset,
  uuid_col = "Survey UUID",
  action_col = "Action taken",
  question_col = "Question number",
  old_value_col = "Old value",
  new_value_col = "New value",
  raw_uuid_column = "_uuid",
  valid_actions = c("recoded", "delete_data_point", "addition", "discard", "other",
    "no_action"),
  default_blank_action = "no_action",
  skip_label_row = TRUE,
  flag_issues_inline = TRUE
)
```

## Arguments

- cleaning_log:

  A dataframe containing the filled cleaning log as produced by
  [`create_cleaning_log()`](create_cleaning_log.md) and completed by the
  reviewer.

- raw_dataset:

  The original raw dataset. Used to verify that uuids and question names
  referenced in the log actually exist.

- uuid_col:

  Name of the uuid column in `cleaning_log`. Default `"Survey UUID"`
  (the column name produced by
  [`create_cleaning_log()`](create_cleaning_log.md)).

- action_col:

  Name of the action-type column in `cleaning_log`. Default
  `"Action taken"`.

- question_col:

  Name of the question column in `cleaning_log`. Default
  `"Question number"`.

- old_value_col:

  Name of the old-value column in `cleaning_log`. Default `"Old value"`.

- new_value_col:

  Name of the new-value column in `cleaning_log`. Default `"New value"`.

- raw_uuid_column:

  Name of the uuid column in `raw_dataset`. Default `"_uuid"`.

- valid_actions:

  Character vector of accepted action-type values. Default matches the
  six types defined in the
  [`create_cleaning_log()`](create_cleaning_log.md) readme sheet.

- default_blank_action:

  Action used for rows whose `action_col` cell is blank. Default
  `"no_action"`: a flagged row the reviewer did not fill in is taken to
  mean the data point stays as it is, and the value is written back into
  the returned cleaning log. Set to `NULL` to flag blank cells as
  `missing_action` instead.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of `raw_dataset` is
  removed before checking uuid existence. ONA exports include a
  label/description row immediately after the header.

- flag_issues_inline:

  Logical. If `TRUE` (the default), an `evaluation_issue` column is
  added to the returned cleaning log so issues are visible alongside the
  rows that caused them.

## Value

A list with:

- cleaning_log:

  The original cleaning log, with an optional `evaluation_issue` column
  when `flag_issues_inline = TRUE`.

- evaluation_log:

  A dataframe with columns `row`, `uuid`, `question`, `action`,
  `issue_type`, and `issue` describing every problem found. Zero rows
  means the log is clean.

## Details

The five valid action types and how they are interpreted:

- `recoded`:

  A data point was changed (maps to `change_response`). **New value**
  must be filled and must differ from **Old value**.

- `delete_data_point`:

  A data point was set to blank / NA (maps to `blank_response`). **New
  value** must be empty.

- `addition`:

  A previously empty cell was filled in (maps to `change_response`).
  **New value** must be filled.

- `discard`:

  The entire survey is removed (maps to `remove_survey`). **New value**
  is ignored. The uuid must exist in the raw dataset.

- `other`:

  Any other change (maps to `change_response`). **New value** must be
  filled.

- `no_action`:

  No change is applied. Rows are skipped entirely during cleaning.

**Blank actions:** an empty **Action taken** cell is filled with
`default_blank_action` (`"no_action"` by default) before the checks run,
so a reviewer who only filled in the rows that needed a change does not
get an issue on every row they left alone. The filled value is written
back into the returned `cleaning_log`, so the action is explicit from
here on. Set `default_blank_action = NULL` to restore the old behaviour,
where a blank cell is reported as `missing_action`.

One case is still reported: a row with a blank action but a **New
value** that differs from the **Old value**
(`blank_action_has_new_value`). The reviewer most likely typed the new
value and forgot the action, and defaulting the row to `no_action` would
throw that change away, so it is surfaced rather than applied.

The function returns a list with two elements: `cleaning_log` (the
original log, possibly with an added `evaluation_issue` column when
`flag_issues_inline = TRUE`) and `evaluation_log` (a dataframe
summarising every issue found, one row per problem, with the row number
and a description).
