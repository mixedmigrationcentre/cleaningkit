# Validate Survey Similarities (Soft Duplicates)

Detects suspiciously similar surveys by computing the Gower distance
between every pair of records and flagging any survey whose closest
neighbour differs in fewer than `threshold` columns. A low number of
differing columns suggests the enumerator may have duplicated or
fabricated a response rather than interviewing a distinct respondent.

## Usage

``` r
validate_duplicates(
  dataset,
  tool_survey,
  uuid_column = "_uuid",
  enumerator_column = "username",
  idnk_value = "Don't know",
  sm_separator = "/",
  log_name = "soft_duplicate_log",
  threshold = 7,
  return_all_results = FALSE,
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- tool_survey:

  XLSForm survey sheet dataframe. Must contain at least `name` and
  `type` columns.

- uuid_column:

  Name of the unique-identifier column. Default `"_uuid"`.

- enumerator_column:

  Name of the enumerator column. Used to annotate the log so reviewers
  can see which enumerator collected each flagged pair. Default
  `"username"`. Set to `NULL` to omit.

- idnk_value:

  The value used in the dataset for "I don't know" responses. The number
  of such responses per survey is reported in the log. Default `"idnk"`.

- sm_separator:

  Separator between a select-multiple parent column name and its binary
  sub-columns. Default `"/"` (ONA export style). Binary sub-columns are
  excluded from the comparison; only the concatenated parent is kept.

- log_name:

  Name of the log element in the returned list. Default
  `"soft_duplicate_log"`.

- threshold:

  Flag all surveys whose closest neighbour differs in at most this many
  columns. Default `7`.

- return_all_results:

  If `TRUE`, return a row for every survey (not only flagged ones).
  Useful for per-enumerator analysis. Default `FALSE`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that must not be treated as a survey
  record.

## Value

A list containing:

- checked_dataset:

  The original dataset, unchanged.

- \<log_name\>:

  A dataframe with columns `uuid`, `old_value` (number of differing
  columns), `question` (`"number_different_columns"`), `issue`, and
  `check_binding`.

## Details

The check works in five steps:

1.  Metadata columns (start, end, today, deviceid, geopoint, …) and
    select-multiple binary sub-columns are dropped, keeping only the
    concatenated parent column.

2.  All remaining columns are converted to lowercase character and then
    to factor so Gower distance can handle mixed types.

3.  Columns that are entirely `NA` are removed; remaining `NA`s are
    replaced with the string `"NA"` so they are treated as a valid
    (unknown) category rather than missing.

4.  Gower distance is computed across all retained columns. For each
    survey the closest *other* survey (second-smallest distance, since
    distance to itself is always 0) is identified and the raw distance
    is converted to an approximate count of differing columns.

5.  Records whose closest-neighbour difference is at or below
    `threshold` are flagged.

The log follows the same
`uuid / old_value / question / issue / check_binding` shape as all other
`validate_*` functions so it can be combined with
[`create_combined_log()`](create_combined_log.md) and coloured in
[`create_cleaning_log()`](create_cleaning_log.md). `check_binding` is
set to `"soft_duplicate ~/~ <uuid>"` for the flagged survey and the
matching pair survey so both rows share the same colour in the review
workbook.
