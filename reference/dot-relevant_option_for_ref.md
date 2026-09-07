# Option a Parent Question Is Compared Against in a Relevance Expression

Returns the choice name that `ref` is compared against inside
`relevant` - i.e. the "other" option that should be dropped from the
recoding dropdown. Anchoring on `ref` avoids the greedy
`str_extract(relevant, "'.*'")` behaviour, which over-captures on
compound expressions (returning `kenya' and selected(${Q32}, 'other`
instead of `other`).

## Usage

``` r
.relevant_option_for_ref(relevant, ref)
```

## Arguments

- relevant:

  Character vector of relevance expressions.

- ref:

  Character vector of parent question names, recycled to the length of
  `relevant`.

## Value

A character vector of option names, `NA` where none is found.
