# The surveys of the last round, from any later download

For applying corrections: picks the surveys of the round a workbook was
made for out of an ONA download (the one that was checked, or any later
one, since each holds everything collected so far), and compares their
fingerprints with those taken when the round was checked.

## Usage

``` r
round_records(
  dataset,
  round_info,
  uuid_column = "_uuid",
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  An ONA download.

- round_info:

  A `ck_round_info` from [`read_round_info()`](read_round_info.md).

- uuid_column, skip_label_row:

  As in [`round_fingerprint()`](round_fingerprint.md).

## Value

A list with `data` (the round's surveys, label row kept), `missing`
(survey IDs of the round not in `dataset`), `changed` (survey IDs whose
answers differ from when they were checked) and `n_round`.
