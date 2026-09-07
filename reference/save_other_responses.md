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
  skip_label_row = TRUE,
  freeze_header = TRUE,
  add_filter = TRUE,
  file_name = NULL
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

- freeze_header:

  Logical. Freeze the header row so it stays visible while scrolling
  (default `TRUE`). Navigation only - it does not change the cell
  styling.

- add_filter:

  Logical. Add a column filter on the header row (default `TRUE`).
  Navigation only - it does not change the cell styling.

- file_name:

  Name of the output file. Default `NULL` keeps the standard name
  `paste0(Sys.Date(), "_other_responses.xlsx")`. A name passed without
  the `.xlsx` extension gets it appended. The name is written inside
  `save_location`.

## Value

NULL. Saves an Excel file.
