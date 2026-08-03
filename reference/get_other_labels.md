# Get Other Labels

Retrieves text labels for questions in the XLSForm survey sheet that
correspond to "other" responses.

## Usage

``` r
get_other_labels(
  tool_survey,
  preferred_language = "English",
  other_text_types = NULL
)
```

## Arguments

- tool_survey:

  A dataframe containing the XLSForm survey sheet.

- preferred_language:

  Label column to prefer for `full_label`. Accepts an exact column name
  (e.g. `"label::English (en)"`) or a substring to match (e.g.
  `"English"`, `"Arabic"`). Defaults to `"English"` so that
  `label::English (en)` is picked up automatically on bilingual forms.
  Set to `NULL` to fall back to a bare `label` column, then the first
  label column found.

- other_text_types:

  Optional character vector of additional text question names to include
  (e.g. `c("Q31_2", "Q45_3")`). Default `NULL`.

## Value

A dataframe containing the corresponding other labels.
