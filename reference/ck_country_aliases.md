# Other spellings of country names

Names an "Other" answer may be typed as that are not a label in the
XLSForm, mapped to the label (or choice name) they mean.
[`validate_repeated_entries`](validate_repeated_entries.md) uses them,
with `tool_choices`, to see that a typed "Turkey" is the same country as
a picked "Turkiye". Labels in every language of the form are already
used, as are small typos, so only add names that are really different.

## Usage

``` r
ck_country_aliases()
```

## Value

A named character vector: names are the typed spellings, values the
label they mean.

## Examples

``` r
aliases <- c(ck_country_aliases(), "Persia" = "Iran")
```
