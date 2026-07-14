# Validate Survey Duration

Checks whether the survey duration (typically stored in a column like
`_duration` in seconds) falls within specified lower and upper bounds
(in minutes). It generates a validation log of surveys that are either
too short or too long.

## Usage

``` r
validate_duration(
  dataset,
  column_to_check = "_duration",
  uuid_column = "_uuid",
  log_name = "duration_log",
  lower_bound = 15,
  upper_bound = 60,
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- column_to_check:

  The name of the column containing the duration in seconds. Default is
  `"_duration"`.

- uuid_column:

  The name of the column containing the unique identifier. Default is
  `"_uuid"`.

- log_name:

  The name of the log to create in the list. Default is
  `"duration_log"`.

- lower_bound:

  The lower threshold for duration in minutes. Default is `15`.

- upper_bound:

  The upper threshold for duration in minutes. Default is `60`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that should not be treated as survey
  data.

## Value

A list containing the original dataset and the new log dataframe.
