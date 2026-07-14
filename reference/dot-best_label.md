# Best available label for each row of an XLSForm sheet

Row-wise label resolver shared by
[`get_other_labels()`](get_other_labels.md) and
[`get_other_db()`](get_other_db.md). Detects a bare `label` column and
any `label::<language>` columns, orders them by preference (the
requested language first, else a bare `label`, else the first label
column found), and returns the first non-empty value per row. When a row
has no label in any language it falls back to the `name` column (if
present) so nothing resolves to `NA`.

## Usage

``` r
.best_label(df, preferred_language = NULL, fallback_to_name = TRUE)
```

## Arguments

- df:

  An XLSForm survey or choices dataframe.

- preferred_language:

  Optional exact label column name (e.g. `"label::Arabic (ar)"`) or
  substring (e.g. `"Arabic"`).

- fallback_to_name:

  Logical; if `TRUE` (default) unresolved rows use the `name` column
  value.

## Value

A character vector of labels, one per row of `df`.
