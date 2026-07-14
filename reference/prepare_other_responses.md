# Prepare Other Responses Dataframe

Combines other responses from all sheets/loops into a single dataframe
ready for use with [`save_other_responses()`](save_other_responses.md).
The function dynamically includes extra columns (e.g., enumerator,
sample_area) if provided.

## Usage

``` r
prepare_other_responses(
  raw_data,
  other_db,
  tool_choices,
  raw_loops = NULL,
  extra_columns = NULL,
  uuid_column = "_uuid",
  questions = NULL,
  skip_label_row = TRUE,
  label_language_fallback = TRUE,
  fallback_to_code = TRUE,
  preferred_language = NULL
)
```

## Arguments

- raw_data:

  Main raw dataset dataframe (always required).

- other_db:

  Dataframe from [`get_other_db()`](get_other_db.md) with question
  metadata.

- tool_choices:

  Dataframe of XLSForm choices sheet.

- raw_loops:

  Optional list of loop/roster dataframes (default is NULL). Pass as a
  named or unnamed list, e.g.,
  `list(household_roster = df1, children = df2)` or `list(df1, df2)`.

- extra_columns:

  Optional character vector of additional column names to include from
  the raw data (e.g., `c("enumerator", "sample_area")`). Default is
  NULL.

- uuid_column:

  Name of the uuid column in raw_data (default is "\_uuid").

- questions:

  Optional character vector of question names (as they appear in the
  `name` column of `other_db`) to process. If `NULL` (the default), all
  questions in `other_db` are used. When provided, only the specified
  questions are prepared; an error is raised if any name is not found in
  `other_db`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of `raw_data` and of
  every loop/roster in `raw_loops` is dropped before processing. ONA
  exports place a label/description row immediately after the header; if
  it is kept it is mistaken for a respondent and produces one spurious
  "other" response (label text, bogus uuid) per question.

- label_language_fallback:

  Logical. If `TRUE` (the default), when the English label lookup for a
  selected `select_multiple` code returns nothing, the first non-empty
  label column in `tool_choices` (e.g. an Arabic `label::Arabic (ar)`
  column) is used instead, so responses in other languages are shown as
  they appear in the raw data rather than as `NA`.

- fallback_to_code:

  Logical. If `TRUE` (the default), a selected code with no label in any
  language is displayed as the raw code itself, so no `"NA"` is ever
  written into `selected_choices`.

- preferred_language:

  Optional. The label language to prefer when resolving
  `select_multiple` choice labels. May be an exact label column name
  (e.g. `"label::Arabic (ar)"`) or a substring (e.g. `"Arabic"`). Passed
  to [`get_label_from_name()`](get_label_from_name.md) and also used to
  order the fallback lookup. If `NULL` (the default), the existing
  preference order is used (a bare `label` column, else the first label
  column found).

## Value

A dataframe formatted for
[`save_other_responses()`](save_other_responses.md). It carries an
attribute `"ona_label_row_skipped"` recording whether the label row was
dropped, so [`save_other_responses()`](save_other_responses.md) does not
drop a row a second time.
