# Validate Dataset Completeness

Checks the entire dataset (excluding metadata columns) and flags any
records that have fewer than a specified threshold of non-empty cells.

## Usage

``` r
validate_completeness(
  dataset,
  uuid_column = "_uuid",
  log_name = "completeness_log",
  min_content_cells = 100,
  metadata_cols = c("start", "end", "today", "deviceid", "username", "simserial",
    "phonenumber", "uuid", "_uuid", "id", "_id", "submission_time", "_submission_time",
    "index", "_index", "df_name"),
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

  The name of the log to create in the list. Default is
  `"completeness_log"`.

- min_content_cells:

  The minimum number of cells that must contain content. Default is
  `100`.

- metadata_cols:

  A character vector of column names representing metadata to exclude
  from completeness calculation.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that should not be treated as survey
  data.

## Value

A list containing the original dataset and the new log dataframe.
