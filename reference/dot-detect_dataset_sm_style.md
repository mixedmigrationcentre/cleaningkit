# Detect the "selected" marker used across the dataset as a whole

Used only as a last resort, when the question being cleaned has no
filled sub-column to learn from. Scans other select-multiple sub-columns
anywhere in the dataset: if their filled values are all `0`/`1`, the
export is binary; if any filled value equals its own column suffix, the
export writes the choice text.

## Usage

``` r
.detect_dataset_sm_style(
  ds,
  sm_separator,
  max_cols = 300L,
  rows = NULL,
  max_rows = 2000L
)
```

## Value

`"binary"`, `"suffix"`, or `NA_character_`.
