# Candidate Parent Question Names for an "Other" Text Question

In the 4Mi tools an "other" text question is named after its parent
question with a numeric suffix appended, so the parent of `Q32_1` is
`Q32` and the parent of `Q86_b_1` is `Q86_b`. This strips trailing
`_<digits>` suffixes one at a time and returns the candidates from the
closest to the furthest (`Q45_3_1` -\> `Q45_3`, `Q45`).

## Usage

``` r
.parent_name_candidates(name, max_depth = 3)
```

## Arguments

- name:

  A single question name.

- max_depth:

  Maximum number of suffixes to strip. Default `3`.

## Value

A character vector of candidate parent names, possibly empty.
