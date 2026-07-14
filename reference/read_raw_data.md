# Read Raw Main Dataset

Reads the main raw dataset from an Excel file, converts date and
datetime columns based on the XLSForm survey definition, and converts
integer/decimal columns to numeric.

## Usage

``` r
read_raw_data(
  filename,
  tool_survey,
  extra_date_cols = NULL,
  extra_datetime_cols = NULL,
  sheet = 1,
  skip_label_row = TRUE
)
```

## Arguments

- filename:

  Path to the Excel file containing the raw data.

- tool_survey:

  A dataframe containing the XLSForm survey sheet (used for identifying
  date and numeric columns).

- extra_date_cols:

  Optional character vector of additional date column names to convert
  (default is NULL). These are appended to the auto-detected "today" and
  "date" type columns from the survey.

- extra_datetime_cols:

  Optional character vector of additional datetime column names to
  convert (default is NULL). These are appended to the auto-detected
  "start", "end", and "datetime" columns and "\_submission_time".

- sheet:

  Sheet number or name to read from the Excel file (default is 1).

- skip_label_row:

  Logical. If `TRUE` (the default), the first data row is excluded from
  date and numeric type conversions. ONA exports include a
  label/description row immediately after the header that contains
  question text (e.g. "Please select...") rather than survey data. The
  label row is preserved in the returned dataframe but kept as text so
  it does not cause conversion errors.

## Value

A dataframe with dates and datetimes converted, and numeric columns cast
to numeric.
