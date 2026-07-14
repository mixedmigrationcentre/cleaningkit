# Validate Refused Responses

Checks the entire dataset and flags any records that have more than a
specified threshold of "Refused" responses.

## Usage

``` r
validate_refused(
  dataset,
  uuid_column = "_uuid",
  log_name = "refused_log",
  max_refused = 6,
  refused_value = "Refused",
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- uuid_column:

  The name of the column containing the unique identifier. Default is
  `"_uuid"`.

- log_name:

  The name of the log to create in the list. Default is `"refused_log"`.

- max_refused:

  The maximum allowable number of refused responses. Default is `6`.

- refused_value:

  The response value to flag as refused. Default is `"Refused"`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that should not be treated as survey
  data.

## Value

A list containing the original dataset and the new log dataframe.
