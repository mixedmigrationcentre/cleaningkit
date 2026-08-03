# Get Other DB

Processes `other_labels` alongside the survey and choices sheets to map
out the available choices for recoding "other" responses.

## Usage

``` r
get_other_db(
  tool_survey,
  tool_choices,
  other_labels,
  preferred_language = "English"
)
```

## Arguments

- tool_survey:

  A dataframe representing the XLSForm survey sheet.

- tool_choices:

  A dataframe representing the XLSForm choices sheet.

- other_labels:

  A dataframe retrieved from
  [`get_other_labels()`](get_other_labels.md).

- preferred_language:

  Label column to prefer for the choice labels used to build the
  recoding dropdowns. Should match the value passed to
  [`get_other_labels()`](get_other_labels.md) so question labels and
  choice labels are in the same language. Accepts an exact column name
  or a substring. Defaults to `"English"` so that `label::English (en)`
  is used automatically. Set to `NULL` to fall back to a bare `label`
  column.

## Value

A dataframe representing the mapping required for the other-responses
database.
