# Combine Validation Logs into a Single Cleaning Log

Stacks the individual logs produced by the `validate_*` functions into
one cleaning log ready for review and correction, and (optionally)
carries the checked dataset through unchanged. Every column of every log
is coerced to trimmed, non-scientific character before binding, so logs
whose columns have different types never clash when combined.

## Usage

``` r
create_combined_log(list_of_log, dataset_name = "checked_dataset")
```

## Arguments

- list_of_log:

  A list containing one or more log data frames, and optionally the
  checked dataset under the name given by `dataset_name`.

- dataset_name:

  The name of the element holding the dataset to carry through to the
  output, or `NULL` if the list contains only logs. Default is
  `"checked_dataset"`.

## Value

A list with, optionally, `checked_dataset` (the untouched dataset) and
`cleaning_log` (all logs combined, with `change_type`, `new_value` and
`check_binding` added).

## Details

The returned `cleaning_log` is the row-bind of all log elements, with
three columns added: `change_type` and `new_value` (both `NA`, to be
filled in during cleaning) and `check_binding`, a matching key of the
form `"question ~/~ uuid"`. If a log already carries its own
`check_binding`, existing values are kept and only the missing ones are
filled.
