# Resolve and normalise the primary label column in an XLSForm sheet

Finds the label column that best matches `label_column` and ensures a
column named exactly `"label"` exists, creating or overwriting it as
needed. All original label columns are preserved so no information is
lost.

## Usage

``` r
.normalise_label_col(df, label_column = NULL)
```

## Arguments

- df:

  A lowercased XLSForm dataframe.

- label_column:

  Substring or exact column name to match. `NULL` falls back to the bare
  `"label"` column.

## Value

`df` with a `"label"` column guaranteed to exist.

## Details

Resolution order:

1.  Exact match on `label_column`.

2.  Substring match (case-insensitive) in any `label*` column.

3.  Bare `"label"` column (when `label_column` is `NULL`).

4.  First `label*` column found (last resort).

5.  If no label column exists at all, an empty `label` column is added
    and a warning is issued.
