# Detect whether a select_one column holds choice labels or choice codes

A label export writes the choice text into the column, a coded export
writes the XLSForm `name`. Recoding an "other" response must write back
whichever the column already contains, so this compares the column's
existing values against `tool_choices` — first within the recorded
`list_name`, then across every list, since that name may come from a
different version of the tool.

## Usage

``` r
.detect_so_convention(
  dataset,
  col,
  list_name = NULL,
  tool_choices = NULL,
  skip_label_row = TRUE,
  cache = NULL
)
```

## Value

`"label"` or `"code"`.
