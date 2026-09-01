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
  header_front_size = 12,
  header_front_color = "#FFFFFF",
  header_fill_color = "#00A2A5",
  header_border_color = "#fafafa",
  header_front = "Arial Narrow",
  body_front = "Arial Narrow",
  body_front_size = 11,
  body_border_color = "#AFDFE4",
  reference_fill_color = NA,
  true_other_fill_color = "#E4EFC8",
  existing_other_fill_color = "#FFF1C4",
  invalid_other_fill_color = "#FCD9D3",
  follow_up_fill_color = "#E3D0DD",
  header_row_height = 45,
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

- header_front_size:

  Header font size (default is 12).

- header_front_color:

  Hexcode for header font color (default is white).

- header_fill_color:

  Hexcode for header fill color (default is MMC blue `"#00A2A5"`, the
  same header as the cleaning log).

- header_border_color:

  Hexcode for the header border (default `"#fafafa"`).

- header_front:

  Font name for the header (default is Arial Narrow).

- body_front:

  Font name for the body (default is Arial Narrow).

- body_front_size:

  Font size for the body (default is 11).

- body_border_color:

  Hexcode for the body cell borders (default is MMC light teal
  `"#AFDFE4"`).

- reference_fill_color:

  Fill for the reference columns (uuid, enumerator, question_name,
  list_name, full_label, selected_choices, response_en). Default `NA`,
  i.e. no fill - these columns are left the default Excel white so the
  eye goes to the columns the reviewer has to fill in. Pass a hexcode
  (e.g. MMC light teal `"#D5EEF0"`) to tint them.

- true_other_fill_color:

  Fill for the **TRUE other** column. Default is a light tint of MMC
  green `"#BBD876"`.

- existing_other_fill_color:

  Fill for the **EXISTING other** column. Default is a light tint of MMC
  yellow `"#FFE07C"`.

- invalid_other_fill_color:

  Fill for the **INVALID other** column. Default is a light tint of MMC
  salmon `"#F8AB9E"`.

- follow_up_fill_color:

  Fill for the **FOLLOW-UP message** / **Explanation** columns. Default
  is a light tint of MMC mauve `"#B88AAB"`.

- header_row_height:

  Height of the header row (default is 45, so the long instruction
  headers wrap and stay readable).

- freeze_header:

  Logical. Freeze the header row (default `TRUE`).

- add_filter:

  Logical. Add a column filter on the header row (default `TRUE`).

- file_name:

  Name of the output file. Default `NULL` keeps the standard name
  `paste0(Sys.Date(), "_other_responses.xlsx")`. A name passed without
  the `.xlsx` extension gets it appended. The name is written inside
  `save_location`.

## Value

NULL. Saves an Excel file.
