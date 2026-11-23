# Keep only the surveys not checked in earlier rounds

The in-memory counterpart of
[`filter_new_records()`](filter_new_records.md): no folder, no files
moved. Give it the new ONA download and what earlier rounds checked.

## Usage

``` r
keep_new_records(
  dataset,
  previous = NULL,
  uuid_column = "_uuid",
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  The new ONA download.

- previous:

  A `ck_round_info` (from [`read_round_info()`](read_round_info.md)), a
  character vector of survey IDs, or `NULL` for the first round.

- uuid_column, skip_label_row:

  As in [`round_fingerprint()`](round_fingerprint.md).

## Value

A list with `data` (the new surveys, ONA label row kept as row one),
`n_total`, `n_checked_before` and `n_new`.

## Examples

``` r
df <- data.frame(`_uuid` = c("a", "b", "c"), check.names = FALSE)
keep_new_records(df, previous = "a", skip_label_row = FALSE)$n_new
#> [1] 2
```
