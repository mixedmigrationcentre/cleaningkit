# Apply Other Responses Cleaning Log to a Dataset

Applies every row of the cleaning log produced by
[`read_other_responses()`](read_other_responses.md) to the dataset. A
direct replacement for the manual apply loop.

## Usage

``` r
apply_other_responses(
  dataset,
  other_log,
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  verbose = TRUE
)
```

## Arguments

- dataset:

  The current working dataset to modify.

- other_log:

  The cleaning log produced by
  [`read_other_responses()`](read_other_responses.md).

- uuid_column:

  Name of the uuid column in `dataset`. Default `"_uuid"`.

- skip_label_row:

  Logical. If `TRUE` (the default), changes are never applied to the
  first (ONA label) row even if its uuid somehow matched.

- verbose:

  Logical. If `TRUE` (the default), a message is printed for each change
  applied, matching the original loop output.

## Value

A list with:

- dataset:

  The modified dataset.

- audit_log:

  A dataframe recording every change with columns `uuid`, `question`,
  `action_taken`, `value_before`, `value_after`.
