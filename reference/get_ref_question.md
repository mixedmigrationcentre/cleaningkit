# Extract Referenced Question Name from Relevance Expression

Parses a relevance expression string to extract the **first** referenced
question name enclosed in curly braces (e.g., `${question_name}`). This
function is fully vectorized.

## Usage

``` r
get_ref_question(x)
```

## Arguments

- x:

  A character vector containing relevance expressions.

## Value

A character vector of the extracted question names, or `NA` if not
found.

## Details

Note that a compound relevance expression references more than one
question, e.g. `${Q31} = 'kenya' and selected(${Q32}, 'other')` returns
`"Q31"` because that is the first reference. To list every reference use
[`.relevant_refs()`](dot-relevant_refs.md), and to work out which
reference is the parent of an "other" text question use
[`.resolve_ref_question()`](dot-resolve_ref_question.md).
