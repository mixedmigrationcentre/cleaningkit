# Fingerprint each survey in a dataset

A hash of each survey's answers, used to notice when a survey changed on
ONA between being checked and being cleaned. ONA metadata columns (names
starting with an underscore, such as `_submission_time` or `_status`)
are left out by default because they change without the answers
changing.

## Usage

``` r
round_fingerprint(
  dataset,
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  columns = NULL
)
```

## Arguments

- dataset:

  A data frame of surveys.

- uuid_column:

  Name of the survey ID column. Default `"_uuid"`.

- skip_label_row:

  Logical. If `TRUE` (the default), row one is the ONA label row and is
  left out.

- columns:

  Columns to hash. Default `NULL`: every column whose name does not
  start with an underscore. Columns missing from `dataset` count as
  empty, so a later download with extra columns still matches.

## Value

A data frame with `uuid` and `fingerprint`, and the columns used in the
attribute `"columns"`.

## Details

Compare fingerprints only between datasets read the same way (for
example both with [`read_raw_data()`](read_raw_data.md)), since the hash
is taken over the values as text.

## Examples

``` r
df <- data.frame(`_uuid` = c("a", "b"), Q1 = c("1", "2"), check.names = FALSE)
round_fingerprint(df, skip_label_row = FALSE)
#>   uuid                      fingerprint
#> 1    a 35d809971931b3571ecfbe44b523945d
#> 2    b 4a1be776ea59fc16cd08afbb3729b981
```
