# Get Other Labels

Retrieves text labels for questions in the XLSForm survey sheet that
correspond to "other" responses.

## Usage

``` r
get_other_labels(
  tool_survey,
  preferred_language = NULL,
  other_text_types = NULL
)
```

## Arguments

- tool_survey:

  A dataframe containing the XLSForm survey sheet.

- preferred_language:

  Optional label language to prefer for the question `full_label`. May
  be an exact label column name (e.g. `"label::Arabic (ar)"`) or a
  substring (e.g. `"Arabic"`). If `NULL` (the default), a bare `label`
  column is preferred, else the first label column found; other
  languages fill any gaps.

- other_text_types:

  Optional character vector of text question names whose text fields use
  a different suffix (e.g. `"_2"`, `"_3"`). Pass the full question names
  as they appear in the survey, for example `c("Q31_2", "Q45_3")`.
  Defaults to `NULL` (no extra text types).

## Value

A dataframe containing the corresponding other labels.
