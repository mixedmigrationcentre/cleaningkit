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
  color_mode = "partial",
  color_columns = c("old_value"),
  include_dataset = TRUE,
  flag_columns = ck_flag_column_defaults(),
  flag_separator = " | ",
  flag_header_fill_color = "#003D58",
  header_front_size = 12,
  header_front_color = "#FFFFFF",
  header_fill_color = "#00A2A5",
  header_front = "Arial Narrow",
  body_front = "Arial Narrow",
  body_front_size = 11,
  skip_label_row = TRUE,
  output_path = NULL,
  group_by = "issue",
  readme_include_other = FALSE
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

- flag_columns:

  Helper columns prepended to the `dataset` sheet, one per survey-level
  check, so a reviewer can filter the raw data down to the surveys a
  check flagged. A named list mapping a column header to the
  `check_binding` prefixes that feed it; default
  [`ck_flag_column_defaults()`](ck_flag_column_defaults.md) gives
  **duration**, **completeness**, **refused**, **back to back** and
  **similarity**. Use `NULL` to add no flag columns. Ignored when
  `include_dataset = FALSE`.

- flag_separator:

  String used to join several flagged values for the same record within
  one flag column. Default `" | "`.

- flag_header_fill_color:

  Hexcode for the header fill of the flag columns. Deliberately
  different from `header_fill_color` so the block reads as helper
  columns rather than part of the export. Default MMC dark blue
  `"#003D58"`. The cells below keep the ordinary body formatting.

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

- group_by:

  Column used to group the log rows, so that all rows sharing a value
  form one contiguous block. Default `"issue"`, which puts every row
  raising the same issue together. Blocks keep the order in which their
  value is first met in the combined log, and rows keep their original
  order inside a block. Accepts either the raw log names (`"issue"`,
  `"uuid"`, `"question"`, `"old_value"`, `"check_binding"`) or the
  reviewer-facing headers (`"Issue"`, `"Survey UUID"`, `"Enumerator"`,
  ...); matching ignores case, spaces and underscores, and a numeric
  column position also works. Use `"uuid"` for the previous
  survey-by-survey layout, or `NULL` / `FALSE` to keep the incoming
  check-by-check order. An unrecognised column name is an error rather
  than a silent fallback.

- readme_include_other:

  Logical. If `TRUE`, the readme also describes the `other_responses`
  and `Dropdown_values` sheets and the three other-responses review
  columns. Default `FALSE`, because those sheets are not part of this
  workbook. [`create_review_workbook()`](create_review_workbook.md),
  which adds them, sets this to `TRUE`.

## Value

A workbook object, or (when `output_path` is given) writes a `.xlsx`
file invisibly.

## Details

The checked dataset is expected to still carry the ONA label/description
row as its first row: column names supply **Question number** and that
first row supplies **Question text**. **Date** and **Enumerator** are
looked up per interview from `date_column` and `enumerator_column`. The
remaining reviewer columns (**New value**, **Identified by**, **Action
taken**, **Comments**, **PO feedback**) are left blank to be completed
during review.

The **Action taken** drop-down and the `readme` sheet share these six
codes: `recoded`, `delete_data_point`, `discard`, `addition`,
`no_action`, `other`. A reviewer only has to fill in the rows that need
a change: the `readme` sheet also carries a row explaining that a cell
left blank is read as `no_action` by
[`read_cleaning_log()`](read_cleaning_log.md),
[`evaluate_cleaning_log()`](evaluate_cleaning_log.md) and
[`apply_cleaning_log()`](apply_cleaning_log.md). The blank entry is
documentation only - it is not added to the drop-down, which still
offers the six codes above.

**Column layout.** **Survey UUID** is the first column (column A) and
**Date** the second. Column A and the header row are both frozen, so the
uuid and the headers stay visible while a reviewer scrolls right and
down.

**Tab order.** A reviewer meets the raw data first, so the tabs are
ordered `dataset`, `cleaning_log`, `readme` (and, in
[`create_review_workbook`](create_review_workbook.md), `other_responses`
between the log and the readme, with `Dropdown_values` last). Only the
visible order changes: the sheets keep their internal positions, and
everything that finds a sheet - the macro,
[`read_cleaning_log`](read_cleaning_log.md),
[`read_other_responses`](read_other_responses.md) - does so by name.

**Row order.** The combined log arrives stacked check by check, so rows
that belong together are scattered down the sheet. By default the
reviewer log is regrouped by **Issue**, so every row raising the same
issue sits in one contiguous block and a reviewer can work through one
kind of problem at a time. Blocks appear in the order each value is
first met in the combined log, and the original order is kept inside
each block, so the rows themselves are untouched - only their
arrangement changes. `group_by` chooses the column: `"uuid"` restores
the previous survey-by-survey layout, any other log column or reviewer
header works too, and `NULL` or `FALSE` keeps the incoming
check-by-check order.

**Row colouring.** By default every log row that shares a
`check_binding` is filled with the same light MMC shade across the whole
row. `color_mode` changes that: `"on"` keeps the default, `"partial"`
fills only the columns listed in `color_columns`, and `"off"` writes the
log with no fills at all. Header formatting (MMC blue fill, white bold
Arial Narrow) is identical in all three modes. `color_columns` accepts
either the reviewer-facing headers (`"Old value"`) or the underlying log
names (`"old_value"`, `"uuid"`, `"question"`, `"issue"`).

**Flag columns on the dataset sheet.** Deciding whether to keep or
discard a whole interview usually means weighing several survey-level
checks at once - a short interview that is also nearly empty, or a
back-to-back interview that is also a soft duplicate. To make that
judgement without leaving the raw data, the `dataset` sheet is written
with a block of helper columns in front of the ONA columns:
**duration**, **completeness**, **refused**, **back to back** and
**similarity**. Each one carries, for that record's uuid, what every
cleaning-log row raised by the matching check says, and is left blank
when the check did not flag the survey. A reviewer can therefore filter
on one column, or on several at once, and cross-check the flagged
surveys directly against their raw answers.

**duration**, **completeness** and **refused** show the log's
`old_value`, which is a figure that speaks for itself: the duration in
minutes, the count of non-empty cells, the count of refused responses.
**back to back** and **similarity** show the `issue` instead, because
their raw values cannot be judged on their own - a bare interview start
time, or a bare count of similar columns, says nothing without the gap,
the threshold, the enumerator and the other survey involved, all of
which the issue names. Any column can be switched either way with
`list(prefixes = ..., value = "issue")` or `value = "old_value"`.

Rows are matched through `check_binding`, whose leading segment names
the check that Rows are matched through `check_binding`, whose leading
segment names the check that raised them, so a log assembled from any
combination of `validate_*` functions works without further
configuration. `flag_columns` changes which columns are written and
which checks feed them; see
[`ck_flag_column_defaults`](ck_flag_column_defaults.md). In the
macro-enabled workbook produced by
[`create_cleaning_log_vba`](create_cleaning_log_vba.md) these columns
are exempt from change capture: editing one never appends a cleaning-log
row.

The five headers carry an MMC dark-blue fill (`flag_header_fill_color`)
rather than the teal used for the ONA headers, so the block is not
mistaken for exported data. Everything below the header row keeps the
ordinary body formatting.

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

# group the rows survey by survey instead of issue by issue
create_cleaning_log(
  write_list,
  group_by = "uuid",
  output_path = "cleaning_log.xlsx"
)

# group by enumerator, using the reviewer-facing header
create_cleaning_log(
  write_list,
  group_by = "Enumerator",
  output_path = "cleaning_log.xlsx"
)

# keep the incoming check-by-check row order, no grouping at all
create_cleaning_log(
  write_list,
  group_by = NULL,
  output_path = "cleaning_log.xlsx"
)

# add a flag column for a check of your own, and drop one you do not use
my_flags <- ck_flag_column_defaults()
my_flags[["outliers"]] <- "outlier_check"
my_flags[["refused"]] <- NULL
create_cleaning_log(
  write_list,
  flag_columns = my_flags,
  output_path = "cleaning_log.xlsx"
)

# plain dataset sheet, no flag columns at all
create_cleaning_log(
  write_list,
  flag_columns = NULL,
  output_path = "cleaning_log.xlsx"
)
} # }
```
