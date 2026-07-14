# Save Other Responses

This function saves the other responses into an Excel workbook with
specific formatting and data validation. Target columns are identified
dynamically by name, allowing flexibility such as adding an
`enumerator_id`.

## Usage

``` r
save_other_responses(
  df,
  ref_date = "",
  enumerator_id = NULL,
  save_location = "output",
  other_db = NULL,
  apply_styles = TRUE,
  skip_label_row = TRUE
)
```

## Arguments

- df:

  Data frame containing the responses to write.

- ref_date:

  Reference date for the filename (default is "").

- enumerator_id:

  Optional string indicating the enumerator id column (default is NULL).

- save_location:

  Directory to save the output file (default is "output").

- other_db:

  Data frame containing dropdown mapping for existing choices (default
  is NULL).

- apply_styles:

  Logical. If TRUE (default) apply the coloured/bordered cell styling.
  Set to FALSE for very large exports where per-cell styling makes
  openxlsx slow or memory-hungry; the data and dropdowns are still
  written.

- skip_label_row:

  Logical. If `TRUE` (the default), guard against an ONA
  label/description row still sitting at the top of `df`. When `df`
  comes from [`prepare_other_responses()`](prepare_other_responses.md)
  the label row was already handled (tracked via the
  `"ona_label_row_skipped"` attribute) and nothing is dropped. Only when
  `df` has no such provenance is its first row dropped, with a message.
  Set to `FALSE` to always keep every row.

## Value

NULL. Saves an Excel file.
