# Detect what value means "selected" in a dataset's select-multiple sub-columns

ONA exports use one of two conventions for binary sub-columns:

- **Binary**: selected = `"1"`, not-selected = `"0"` or `NA`.

- **Label-value**: selected = the sub-column suffix (the choice label or
  code, e.g. `"Travel in a group"`), not-selected = `NA` or blank.

We detect the convention by looking at a sub-column whose suffix is a
known token: if a selected row's value equals the suffix, it's
label-value convention; if it equals `"1"`, it's binary. The
`selected_val` returned is what must be written when marking a choice as
selected, and `NA` is always used when marking as not-selected (blank).

## Usage

``` r
.make_selected_val_fn(
  dataset,
  parent_col,
  sm_separator,
  uuid_column,
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  The dataset.

- parent_col:

  The parent select-multiple column name.

- sm_separator:

  Sub-column separator.

- uuid_column:

  UUID column name.

- skip_label_row:

  Whether to skip the first (label) row.

## Value

A function `f(suffix)` that returns the correct "selected" value for a
sub-column with the given suffix.
