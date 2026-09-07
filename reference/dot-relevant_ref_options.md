# Pair Each Question Reference in a Relevance Expression With Its Option

Splits a relevance expression into `(question, option)` pairs by
matching each `${question}` reference with the value it is compared
against. Handles the common XLSForm shapes: `selected(${Q32}, 'other')`,
`${Q32} = 'other'` and `${Q32} = 96`. Compound expressions joined with
`and`/`or` return one row per clause, which is what makes it possible to
pick the clause that belongs to a given parent question instead of
blindly taking the first quoted string in the expression.

## Usage

``` r
.relevant_ref_options(x)
```

## Arguments

- x:

  A single relevance expression (length-1 character vector).

## Value

A dataframe with columns `ref` and `option` (0 rows when nothing
matches).
