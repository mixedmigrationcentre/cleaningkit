# Headers of the flag columns, as written to the `dataset` sheet

A convenience wrapper over
[`ck_flag_column_defaults`](ck_flag_column_defaults.md) for code that
only needs the column names - for instance to drop the helper columns
again after reading a reviewed `dataset` sheet back in.

## Usage

``` r
ck_flag_column_names(flag_columns = ck_flag_column_defaults())
```

## Arguments

- flag_columns:

  A flag-column definition list. Default
  [`ck_flag_column_defaults()`](ck_flag_column_defaults.md).

## Value

Character vector of column headers.

## Examples

``` r
ck_flag_column_names()
#> [1] "duration"     "completeness" "refused"      "back to back" "similarity"  
```
