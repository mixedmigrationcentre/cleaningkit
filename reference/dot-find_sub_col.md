# Locate the sub-column that actually exists for a choice

The dataset may name sub-columns with the choice label
(`Q83/Insufficient access to basic goods`) or the choice code (`Q83/2`),
and the casing/spacing may differ from `tool_choices`. This tries each
candidate token in turn, case- and whitespace-insensitively, and returns
the real column name.

## Usage

``` r
.find_sub_col(sub_cols, suffixes, tokens)
```

## Arguments

- sub_cols:

  Character vector of the parent's sub-column names.

- suffixes:

  The matching suffixes (see [`.sm_suffixes()`](dot-sm_suffixes.md)).

- tokens:

  Candidate tokens, in priority order.

## Value

The matching column name, or `NA_character_`.
