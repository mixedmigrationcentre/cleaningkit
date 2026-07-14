# Combine Reviewed Logs into a Single Reviewer-Ready Log

Merges the other-responses cleaning log (from
[`read_other_responses()`](read_other_responses.md)) with the main
cleaning log (from [`create_cleaning_log()`](create_cleaning_log.md))
into one unified dataframe that follows the
[`create_cleaning_log()`](create_cleaning_log.md) column shape, ready
for review in Excel or for passing to
[`evaluate_cleaning_log()`](evaluate_cleaning_log.md).

## Usage

``` r
combine_reviewed_logs(
  main_log,
  other_log,
  dataset,
  uuid_column = "_uuid",
  enumerator_column = "username",
  date_column = "today",
  cleaning_log_name = "cleaning_log",
  issue_labels = c(true_other = "Translation or correction of a genuine other response",
    recode = "Other response recoded to an existing choice", remove =
    "Invalid other response — value removed"),
  skip_label_row = TRUE
)
```

## Arguments

- main_log:

  A list returned by [`create_cleaning_log()`](create_cleaning_log.md)
  (containing `cleaning_log` and optionally `checked_dataset`), or a
  dataframe that is already in the
  [`create_cleaning_log()`](create_cleaning_log.md) column shape.

- other_log:

  A dataframe returned by
  [`read_other_responses()`](read_other_responses.md), with columns
  `uuid`, `question`, `action_taken`, `old_value`, `new_value`.

- dataset:

  The working dataset (with the ONA label row still as row 1 if
  `skip_label_row = TRUE`). Used to look up `Date` and `Enumerator` for
  each other-response row.

- uuid_column:

  Name of the uuid column in `dataset`. Default `"_uuid"`.

- enumerator_column:

  Name of the enumerator column. Default `"username"`.

- date_column:

  Name of the date column. Default `"today"`.

- cleaning_log_name:

  Name of the cleaning log element when `main_log` is a list. Default
  `"cleaning_log"`.

- issue_labels:

  Named character vector mapping `action_taken` values to human-readable
  issue descriptions. Defaults cover the three standard other-response
  action types.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of `dataset` is
  treated as the ONA label/description row and skipped when building the
  date/enumerator lookup and question-text lookup.

## Value

A single dataframe in the
[`create_cleaning_log()`](create_cleaning_log.md) column shape, with the
other-response rows appended after the main cleaning log rows. Columns:
`Date`, `Survey UUID`, `Survey Registration Date`, `Enumerator`,
`Section`, `Question number`, `Question text`, `Issue`, `Old value`,
`Action taken`, `New value`, `Identified by`, `Comments`, `PO feedback`,
`check_binding`.

## Details

**Column mapping from the other-responses log:**

- `uuid`:

  → `Survey UUID`; also used to look up `Date` and `Enumerator` from the
  dataset.

- `question`:

  → `Question number`; label looked up from the dataset label row →
  `Question text`.

- `action_taken`:

  → `Action taken` (kept as-is) and used to generate a human-readable
  `Issue` description.

- `old_value`:

  → `Old value`.

- `new_value`:

  → `New value` (already filled by
  [`read_other_responses()`](read_other_responses.md)).

**Issue descriptions generated from `action_taken`:**

- `true_other`:

  Translation or correction of a genuine other response

- `recode`:

  Other response recoded to an existing choice

- `remove`:

  Invalid other response — value removed

**check_binding:** rows from the same other-response action on the same
record share a `check_binding` of `"other_response ~/~ <uuid>"`, so they
are coloured as a group in the review workbook.
