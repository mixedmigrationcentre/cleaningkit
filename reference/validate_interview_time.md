# Validate Interview Time

Checks that each interview was conducted at a plausible time of day and
flags any records that fall outside an acceptable window (for example,
interviews recorded in the middle of the night), which may suggest the
data was fabricated or mis-recorded.

## Usage

``` r
validate_interview_time(
  dataset,
  uuid_column = "_uuid",
  time_column = "start",
  log_name = "interview_time_log",
  earliest_hour = 5,
  latest_hour = 22,
  flag_missing = FALSE,
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- uuid_column:

  The name of the column containing the unique identifier. Default is
  `"_uuid"`.

- time_column:

  The name of the column holding the interview start timestamp. Default
  is `"start"`. Accepts an ISO 8601 character string (as ONA exports it)
  or a `POSIXct` column (as produced by `readxl` when it auto-parses
  dates).

- log_name:

  The name of the log to create in the list. Default is
  `"interview_time_log"`.

- earliest_hour:

  Integer 0-23. Interviews starting before this hour are flagged.
  Default is `5`.

- latest_hour:

  Integer 0-24. Interviews starting at or after this hour are flagged.
  Default is `22`.

- flag_missing:

  Logical. If `TRUE`, records whose time is missing or cannot be parsed
  are also flagged. Default is `FALSE`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that should not be treated as survey
  data.

## Value

A list containing the original dataset and the new log dataframe.

## Details

The hour of the interview is taken from the interview start timestamp
(`time_column`). ONA exports this column as an ISO 8601 datetime such as
`"2023-05-12T09:34:21.000+03:00"`. The local wall-clock hour recorded in
the timestamp is used (the offset the enumerator's device recorded), so
no timezone conversion is applied. A record is flagged when its hour is
earlier than `earliest_hour` or at/after `latest_hour`.
