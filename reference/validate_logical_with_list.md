# Validate Multiple Logical Checks from a Checklist

A wrapper around a single logical check that runs every row of a
checklist dataframe as its own check and collects the results into one
or more logs. Equivalent to calling a logical validator once per check
and assembling the results, but driven by a checklist so checks can be
maintained outside the code (e.g. in an Excel sheet).

## Usage

``` r
validate_logical_with_list(
  dataset,
  uuid_column = "_uuid",
  list_of_check,
  check_id_column,
  check_to_perform_column,
  columns_to_clean_column = NULL,
  description_column,
  log_name = "logical_log",
  bind_checks = TRUE,
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- uuid_column:

  Name of the uuid column. Default `"_uuid"`.

- list_of_check:

  A dataframe where each row defines one check. Must contain at minimum
  the columns named by `check_id_column`, `check_to_perform_column`, and
  `description_column`.

- check_id_column:

  Column in `list_of_check` holding a unique identifier for each check
  (used as the log name when `bind_checks = FALSE`, and in the `issue`
  text).

- check_to_perform_column:

  Column holding the R expression to evaluate (as a character string).
  Must produce a logical vector when evaluated against the dataset.

- columns_to_clean_column:

  Column holding a comma-separated string of column names whose values
  should be recorded in the log for each flagged record. `NULL`, `NA`,
  or `""` means no specific columns are recorded (the check id is used
  as the question instead).

- description_column:

  Column holding a human-readable description of what the check is
  testing (written into the `issue` field).

- log_name:

  Name under which the combined log is stored in the returned list when
  `bind_checks = TRUE`. Default `"logical_log"`.

- bind_checks:

  Logical. If `TRUE` (the default), all per-check logs are stacked into
  one dataframe. If `FALSE`, each check's log is stored separately under
  its check id.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that should not be treated as survey
  data.

## Value

A list containing:

- checked_dataset:

  The original dataset with one logical flag column added per check
  (named after the check id, `TRUE` = flagged).

- \<log_name\> or \<check_id\>:

  One log dataframe (bound or separate, depending on `bind_checks`).

## Details

Every row of `list_of_check` is evaluated as an R expression against the
dataset. Flagged records are written to a log with columns `uuid`,
`old_value`, `question`, and `issue` — the same shape as all other
`validate_*` logs so they can be combined with
[`create_combined_log()`](create_combined_log.md).

`columns_to_clean_column` may hold a comma-separated list of column
names (e.g. `"Q13, Q31"`). Each column produces one log row per flagged
record. If a check has no columns to clean, one row per flagged record
is still written with `question = check_id` and `old_value = NA`.

When `bind_checks = TRUE` (the default), all per-check logs are stacked
into one dataframe stored under `log_name`. When `FALSE`, each check's
log is stored separately under its `check_id` value.
