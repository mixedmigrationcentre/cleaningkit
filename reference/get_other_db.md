# Get Other DB

Processes the 'other_labels' alongside the survey inputs to map out the
available choices for recoding.

## Usage

``` r
get_other_db(
  tool_survey,
  tool_choices,
  other_labels,
  preferred_language = NULL
)
```

## Arguments

- tool_survey:

  A dataframe representing the XLSForm survey sheet.

- tool_choices:

  A dataframe representing the XLSForm choices sheet.

- other_labels:

  A dataframe retrieved from `get_other_labels`.

- preferred_language:

  Optional label language to prefer for the available choice labels used
  to build the recoding dropdowns. May be an exact label column name or
  a substring (e.g. `"Arabic"`). Should match the value passed to
  [`get_other_labels()`](get_other_labels.md) so question labels and
  choice labels are in the same language. If `NULL` (the default), a
  bare `label` column is preferred, else the first label column found.

## Value

A dataframe representing the mapping required for other responses
database.
