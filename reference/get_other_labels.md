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

A dataframe with one row per "other" text question and the columns
`name`, `ref_question` and `full_label`.

## Details

The parent question (`ref_question`) is resolved from the question
*name* first - `Q32_1` belongs to `Q32`, `Q86_b_1` to `Q86_b` - and only
falls back to parsing the relevance expression when the name does not
resolve to a question that exists in the survey sheet. Reading the
relevance expression first is what used to produce wrong parents: a
compound expression such as
`${Q31} = 'kenya' and selected(${Q32}, 'other')` references `Q31` before
`Q32`, so `Q32_1` was attributed to `Q31`. See
[`.resolve_ref_question()`](dot-resolve_ref_question.md) for the full
resolution order.
