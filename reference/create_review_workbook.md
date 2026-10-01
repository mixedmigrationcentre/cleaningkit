# Create One Review Workbook Holding Both Logs

Writes the cleaning log and the "other" text responses into a single
Excel workbook, so a reviewer opens one file instead of two and the
second stage reads one file instead of two.

## Usage

``` r
create_review_workbook(
  write_list,
  output_path,
  other_responses = NULL,
  other_db = NULL,
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
  group_by = "issue",
  other_sheet_name = ck_sheet_name("other_responses"),
  other_dropdown_sheet = ck_sheet_name("dropdown"),
  other_enumerator_id = NULL,
  other_apply_styles = TRUE,
  other_freeze_header = TRUE,
  other_add_filter = TRUE,
  other_body_font = "Calibri",
  other_body_font_size = 12,
  vba = FALSE,
  macro_issue_prefix = "manual_edit",
  vba_project = NULL
)
```

## Arguments

- write_list:

  The combined log list from
  [`create_combined_log()`](create_combined_log.md), carrying the
  cleaning log and the checked dataset.

- output_path:

  Path to write to. `.xlsm` (or `vba = TRUE`, which corrects the
  extension) produces the macro-enabled workbook.

- other_responses:

  Data frame from
  [`prepare_other_responses()`](prepare_other_responses.md). `NULL` (the
  default) writes the cleaning-log sheets only, which makes this
  function a drop-in for
  [`create_cleaning_log()`](create_cleaning_log.md) /
  [`create_cleaning_log_vba()`](create_cleaning_log_vba.md).

- other_db:

  Data frame from [`get_other_db()`](get_other_db.md), used for the
  per-question drop-downs on the other-responses sheet.

- cleaning_log_name, dataset_name, uuid_column, enumerator_column,
  date_column:

  Passed straight to [`create_cleaning_log()`](create_cleaning_log.md).

- column_for_color, color_mode, color_columns, include_dataset:

  Passed straight to [`create_cleaning_log()`](create_cleaning_log.md).

- flag_columns, flag_separator, flag_header_fill_color:

  Passed straight to [`create_cleaning_log()`](create_cleaning_log.md).

- header_front_size, header_front_color, header_fill_color,
  header_front:

  Passed straight to [`create_cleaning_log()`](create_cleaning_log.md).

- body_front, body_front_size, skip_label_row, group_by:

  Passed straight to [`create_cleaning_log()`](create_cleaning_log.md).

- other_sheet_name, other_dropdown_sheet:

  Names of the two other-responses sheets. Defaults `"other_responses"`
  and `"Dropdown_values"`. Change these only if you also tell
  [`read_other_responses()`](read_other_responses.md) the new name.

- other_enumerator_id:

  Column moved to sit just after `uuid` on the other-responses sheet, as
  `enumerator_id` does in
  [`save_other_responses()`](save_other_responses.md). Default `NULL`.

- other_apply_styles, other_freeze_header, other_add_filter:

  As documented on [`save_other_responses()`](save_other_responses.md).

- other_body_font, other_body_font_size:

  Font of the other-responses sheet. Defaults `"Calibri"` / `12`,
  matching the standalone file, and independent of the log's
  `body_front`.

- vba:

  Logical. Attach the change-capture macro and write `.xlsm`. Default
  `FALSE`. Forces `include_dataset = TRUE`: without the dataset sheet
  there is nothing for the macro to watch.

- macro_issue_prefix, vba_project:

  As documented on
  [`create_cleaning_log_vba()`](create_cleaning_log_vba.md). Ignored
  when `vba = FALSE`.

## Value

`output_path`, invisibly. The extension is corrected to `.xlsm` when
`vba = TRUE`.

## Details

**The sheets.** In the order a reviewer sees them:

- `dataset`:

  The checked dataset with the flag block in front. First, because it is
  where a keep-or-discard decision is actually made.

- `cleaning_log`:

  One row per flagged value. Exactly what
  [`create_cleaning_log()`](create_cleaning_log.md) produces.

- `other_responses`:

  The other text responses to review. Exactly what
  [`save_other_responses()`](save_other_responses.md) produces, on a
  named sheet rather than `Sheet1`.

- `readme`:

  The guide, extended to cover the other-responses sheet and its three
  review columns.

- `Dropdown_values`:

  Source of the other-responses drop-downs.

- `validation_rules`:

  Hidden. Source of the `Action taken` drop-down.

- `_ck_config`:

  Very hidden, `.xlsm` only. The macro's configuration, and the last
  sheet in the workbook.

The tabs are put in this order by `ck_order_worksheets()` once every
sheet has been written. Only the visible order changes - the sheets keep
their internal positions, and the macro and both readers address them by
name.

**Two styling regimes, deliberately.** The log and dataset sheets carry
the MMC header and Arial Narrow body styling; the other-responses sheet
keeps its own green / green / blue column blocks, which are what tell a
reviewer which block of columns does what. The other-responses sheets
are therefore written after the workbook comes back from
[`create_cleaning_log()`](create_cleaning_log.md), not through it, and
no workbook-wide base font is set - that would reach across every sheet.

**The macro.** With `vba = TRUE` the workbook is written as `.xlsm` with
the change-capture macro attached, exactly as
[`create_cleaning_log_vba()`](create_cleaning_log_vba.md) does it. The
macro watches the `dataset` sheet and nothing else: an edit there
appends a row to `cleaning_log`, and an edit on `other_responses`
appends nothing, because that sheet is read back column by column
instead. Extra sheets in the workbook change nothing for the macro,
which addresses sheets by name.

**Reading it back.** [`read_cleaning_log()`](read_cleaning_log.md) and
[`read_other_responses()`](read_other_responses.md) both default to the
`"_follow-ups_edited\.xls[xm]$"` pattern and find their sheet by name,
so both are pointed at the same folder and the same file.

## Examples

``` r
if (FALSE) { # \dontrun{
# one plain workbook holding both logs
create_review_workbook(
  write_list = combined_log,
  other_responses = df,
  other_db = other_db,
  other_enumerator_id = "username",
  output_path = paste0("output/follow_ups/", Sys.Date(), "_follow-ups.xlsx")
)

# the same, macro-enabled
create_review_workbook(
  write_list = combined_log,
  other_responses = df,
  other_db = other_db,
  other_enumerator_id = "username",
  vba = TRUE,
  output_path = paste0("output/follow_ups/", Sys.Date(), "_follow-ups.xlsm")
)
} # }
```
