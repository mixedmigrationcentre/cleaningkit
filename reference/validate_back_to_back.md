# Validate Back-to-Back Interviews

Flags interviews that follow one another too closely for the same
enumerator. When an enumerator's interviews are conducted one right
after the other, with little or no gap in between, it can indicate that
interviews are being fabricated rather than genuinely conducted with
respondents.

## Usage

``` r
validate_back_to_back(
  dataset,
  uuid_column = "_uuid",
  enumerator_column = "username",
  start_column = "start",
  end_column = "end",
  log_name = "back_to_back_log",
  threshold_hours = 0,
  threshold_mins = 10,
  gap_from = c("end", "start"),
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- uuid_column:

  The name of the column containing the unique identifier. Default is
  `"_uuid"`.

- enumerator_column:

  The name of the column identifying the enumerator. Default is
  `"username"`.

- start_column:

  The name of the interview start timestamp column. Default is
  `"start"`.

- end_column:

  The name of the interview end timestamp column. Default is `"end"`.
  Only required when `gap_from = "end"`.

- log_name:

  The name of the log to create in the list. Default is
  `"back_to_back_log"`.

- threshold_hours:

  Numeric. Hours component of the minimum acceptable gap. Default is
  `0`.

- threshold_mins:

  Numeric. Minutes component of the minimum acceptable gap. Default is
  `10`. The two components are added together; gaps shorter than this
  total are flagged.

- gap_from:

  Either `"end"` (default) to measure from the previous interview's end,
  or `"start"` to measure from the previous interview's start.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that should not be treated as survey
  data.

## Value

A list containing the original dataset and the new log dataframe.

## Details

For each enumerator the interviews are ordered chronologically and the
gap between consecutive interviews is measured. An interview is flagged
when the gap before it is shorter than the configured threshold
(`threshold_hours` + `threshold_mins`), including the case where it
overlaps the previous interview (a negative gap, which is physically
impossible for a single enumerator).

By default the gap is measured from the *end* of the previous interview
to the *start* of the current one (`gap_from = "end"`). If end times are
unreliable, set `gap_from = "start"` to measure start-to-start spacing
instead.

This signal is less reliable for remote (phone) data collection, where
enumerators can legitimately line up calls back-to-back. It is most
useful when combined with other checks such as below-average interview
duration and repeated logical inconsistencies in responses. Treat the
log as a review queue, not an automatic rejection.
