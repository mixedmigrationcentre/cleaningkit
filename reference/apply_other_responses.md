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

## Details

Values are written back in whatever convention the export already uses.
For select-multiple sub-columns this is detected from the data by
[`read_other_responses()`](read_other_responses.md) (see
[`.detect_sm_convention()`](dot-detect_sm_convention.md)): in a label
export a selected choice holds the choice text and an unselected one
stays blank, and in a binary export they hold `"1"` and `"0"`. `0`/`1`
are only ever introduced where the export already contains them.

Choices are matched to the dataset's own column headers first, and only
then translated through `tool_choices`. The `list_name` recorded in
`other_db` comes from whichever version of the tool produced the
original output, so when it is missing from the current `tool_choices`
the choice text is looked up across the remaining lists (and matched
ignoring case, spacing and punctuation). A recoded choice is written in
the form the column itself uses, so a label export is never given choice
codes.
