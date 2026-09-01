# Creates the final cleaning log workbook

Builds the reviewer-facing cleaning log from a combined log (see
`create_combined_log`) and the checked dataset, laying it out with the
standard MMC column headers, a `readme` sheet explaining the action
codes, and a drop-down on the **Action taken** column.

## Usage

``` r
create_cleaning_log(
  write_list,
  cleaning_log_name = "cleaning_log",
  dataset_name = "checked_dataset",
  uuid_column = "_uuid",
  enumerator_column = "username",
  date_column = "today",
  column_for_color = "check_binding",
  color_mode = "on",
  color_columns = NULL,
  include_dataset = TRUE,
  header_front_size = 12,
  header_front_color = "#FFFFFF",
  header_fill_color = "#00A2A5",
  header_front = "Arial Narrow",
  body_front = "Arial Narrow",
  body_front_size = 11,
  skip_label_row = TRUE,
  output_path = NULL
)
```

## Arguments

- write_list:

  A list containing the combined log and the checked dataset.

- cleaning_log_name:

  Name of the combined-log element in `write_list`. Default
  `"cleaning_log"`.

- dataset_name:

  Name of the checked-dataset element in `write_list`. Default
  `"checked_dataset"`.

- uuid_column:

  Name of the uuid column in the checked dataset. Default `"_uuid"`.

- enumerator_column:

  Name of the enumerator column in the checked dataset. Default
  `"username"`.

- date_column:

  Name of the survey-date column in the checked dataset. Default
  `"today"`.

- column_for_color:

  Column used to colourise rows. Default `"check_binding"`, so all log
  rows that share a binding (e.g. several questions flagged by one check
  for the same record) get the same colour. The column is written but
  kept hidden in the output. Set to `NULL` to disable colouring.

- color_mode:

  One of `"on"` (default, colour the full row), `"partial"` (colour only
  `color_columns`) or `"off"` (no colouring). `TRUE`/`FALSE` work as
  shorthand for `"on"`/`"off"`. Never affects the header formatting.

- color_columns:

  Columns to fill when `color_mode = "partial"`, e.g. `"old_value"` or
  `c("Old value", "Issue")`. Matching ignores case, spaces and
  underscores; numeric column positions are also accepted. Default
  `NULL`.

- include_dataset:

  Logical. If `TRUE` (the default), the checked dataset is written to a
  sheet named `"dataset"` so reviewers can refer back to the raw data.

- header_front_size:

  Header font size (default is 12).

- header_front_color:

  Hexcode for header font color (default is white).

- header_fill_color:

  Hexcode for header fill color (default is MMC blue `"#00A2A5"`).

- header_front:

  Font name for header (default is Arial Narrow).

- body_front:

  Font name for body (default is Arial Narrow).

- body_front_size:

  Font size for body (default is 11).

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the checked dataset
  is treated as the ONA label/description row: it supplies **Question
  text** and the actual records are taken from row 2 onward. If `FALSE`,
  every row is treated as a record and **Question text** is left blank
  (no label row to read from).

- output_path:

  Output path. Default `NULL` returns a workbook instead of writing a
  file.

## Value

A workbook object, or (when `output_path` is given) writes a `.xlsx`
file invisibly.

## Details

The checked dataset is expected to still carry the ONA label/description
row as its first row: column names supply **Question number** and that
first row supplies **Question text**. **Date** and **Enumerator** are
looked up per interview from `date_column` and `enumerator_column`. The
remaining reviewer columns (**New value**, **Identified by**, **Action
taken**, **Comments**, **PO feedback**, **Survey Registration Date**,
**Section**) are left blank to be completed during review.

The **Action taken** drop-down and the `readme` sheet share these five
codes: `recoded`, `delete_data_point`, `discard`, `addition`, `other`.

**Row colouring.** By default every log row that shares a
`check_binding` is filled with the same light MMC shade across the whole
row. `color_mode` changes that: `"on"` keeps the default, `"partial"`
fills only the columns listed in `color_columns`, and `"off"` writes the
log with no fills at all. Header formatting (MMC blue fill, white bold
Arial Narrow) is identical in all three modes. `color_columns` accepts
either the reviewer-facing headers (`"Old value"`) or the underlying log
names (`"old_value"`, `"uuid"`, `"question"`, `"issue"`).

## Examples

``` r
if (FALSE) { # \dontrun{
# default: full-row colouring by check_binding
create_cleaning_log(write_list, output_path = "cleaning_log.xlsx")

# colour only the "Old value" column
create_cleaning_log(
  write_list,
  color_mode = "partial",
  color_columns = "old_value",
  output_path = "cleaning_log.xlsx"
)

# no colouring at all
create_cleaning_log(write_list, color_mode = "off", output_path = "cleaning_log.xlsx")
} # }
```
