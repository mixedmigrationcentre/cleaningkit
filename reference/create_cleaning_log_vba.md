# Creates the cleaning log workbook with the change-capture macro

A macro-enabled (`.xlsm`) version of
[`create_cleaning_log`](create_cleaning_log.md). The workbook is
identical, plus a VBA project that watches the `dataset` sheet: every
edit a reviewer makes there is appended automatically to the bottom of
the cleaning log, so a change never has to be copied across by hand.

## Usage

``` r
create_cleaning_log_vba(
  write_list,
  output_path,
  cleaning_log_name = "cleaning_log",
  dataset_name = "checked_dataset",
  uuid_column = "_uuid",
  enumerator_column = "username",
  date_column = "today",
  column_for_color = "check_binding",
  color_mode = "on",
  color_columns = NULL,
  header_front_size = 12,
  header_front_color = "#FFFFFF",
  header_fill_color = "#00A2A5",
  header_front = "Arial Narrow",
  body_front = "Arial Narrow",
  body_front_size = 11,
  skip_label_row = TRUE,
  group_by_uuid = TRUE,
  macro_issue_prefix = "manual_edit",
  vba_project = NULL
)
```

## Arguments

- write_list:

  A list containing the combined log and the checked dataset.

- output_path:

  Path for the macro-enabled workbook. Required - a VBA project cannot
  be attached to a workbook object, so unlike
  [`create_cleaning_log()`](create_cleaning_log.md) this function cannot
  return one. An `.xlsx` extension is corrected to `.xlsm` with a
  message.

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

- group_by_uuid:

  Logical. If `TRUE` (the default), the log rows are regrouped so all
  rows from the same **Survey UUID** form one contiguous block, surveys
  following one another. Blocks keep the order in which their uuid is
  first met in the combined log, and rows keep their original order
  inside a block. `FALSE` keeps the incoming check-by-check order.

- macro_issue_prefix:

  Prefix used to build the **Issue** value of macro-appended rows. The
  Nth edit of a given cell is written as `"<prefix>_00N"`. Default
  `"manual_edit"`.

- vba_project:

  Path to the compiled `vbaProject.bin` to inject. Default `NULL` uses
  [`ck_vba_project_path`](ck_vba_project_path.md).

## Value

The output path, invisibly.

## Details

This is a thin wrapper. It calls
[`create_cleaning_log`](create_cleaning_log.md) with
`output_path = NULL` to build the ordinary workbook, adds one
very-hidden configuration sheet, and injects the compiled VBA project
into the saved package.
[`create_cleaning_log()`](create_cleaning_log.md) itself is not modified
and does not know this function exists - so if anything about the macro
route breaks (a missing binary, a blocked macro, an Excel upgrade), the
plain `.xlsx` path is completely unaffected. Every argument below
behaves exactly as it does there.

**Two extra sheets.** `_ck_config` holds the sheet and column names the
macro reads, so one compiled binary serves every log the package
produces. `_ck_ledger` is created by the macro itself on the first edit
and remembers, per cell, the original raw value, the latest value and
the edit count. Both are `veryHidden`, so they do not appear in Excel's
Unhide dialog.

**What an edit produces.** A row carrying **Survey UUID**, **Date**,
**Enumerator**, **Question number**, **Question text**, **Old value**,
**New value**, **Identified by** and a mapped **Action taken** -
`addition` when the cell was empty, `delete_data_point` when it is
cleared, `recoded` otherwise.

**Repeat edits.** Editing the same cell again appends *another* row
rather than revising the first, so the log keeps the full history. Each
row's **Old value** is the value immediately before that edit, so
successive rows chain raw -\> A -\> B. To keep those rows distinct
through [`read_cleaning_log`](read_cleaning_log.md), whose deduplication
key is `uuid + question + issue`, the Nth edit is written with **Issue**
`"manual_edit_00N"`. The sequence numbers sort in edit order, so
[`apply_cleaning_log`](apply_cleaning_log.md) applies the most recent
value last.

**Formatting.** Appended rows have their formatting cleared before they
are written and `Application.ExtendList` is suspended during the write,
so none of the [`create_formated_wb`](create_formated_wb.md) row colours
carry down onto them. They are given the same **Action taken** drop-down
as the rest of the log.

**Protected cells.** The macro restores the header and label rows and
the uuid column if they are edited, because the log refers to them.

**Prerequisite.** The compiled VBA project is not generated by R. It is
built once from the sources in `inst/vba/` with `dev/build_vba_bin.R`
(or by hand - see `inst/vba/README.md`) and found by
[`ck_vba_project_path`](ck_vba_project_path.md). If it cannot be found,
this function stops with a message listing every location it searched;
use [`create_cleaning_log()`](create_cleaning_log.md) in the meantime.

**Reading the result back.** `readxl` reads `.xlsm` exactly like
`.xlsx`, but remember to widen `file_pattern` when scanning a directory
with [`read_cleaning_log`](read_cleaning_log.md).

## See also

[`create_cleaning_log`](create_cleaning_log.md) for the plain `.xlsx`
version, [`add_vba_project`](add_vba_project.md) for the injection step
and [`ck_vba_project_path`](ck_vba_project_path.md) for how the binary
is located.

## Examples

``` r
if (FALSE) { # \dontrun{
create_cleaning_log_vba(
  write_list,
  output_path = "cleaning_log.xlsm"
)

# point at a binary that is not on the default search path
create_cleaning_log_vba(
  write_list,
  output_path = "cleaning_log.xlsm",
  vba_project = "resources/cleaningkit_vba.bin"
)
} # }
```
