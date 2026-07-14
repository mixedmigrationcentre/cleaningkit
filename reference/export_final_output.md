# Export Final Data Cleaning Output Workbook

Writes a single Excel workbook containing four sheets:

1.  **readme** — project description and sheet guide, styled with MMC
    colours.

2.  **raw_data** — the original raw dataset (ONA label row preserved as
    row 1).

3.  **clean_data** — the cleaned dataset produced by
    [`apply_cleaning_log()`](apply_cleaning_log.md).

4.  **cleaning_log** — the combined cleaning log from
    [`combine_reviewed_logs()`](combine_reviewed_logs.md).

## Usage

``` r
export_final_output(
  raw_dataset,
  clean_dataset,
  combined_log,
  output_path = "path to output .xlsx",
  project_name = "Mixed Migration Centre Data Cleaning",
  project_description =
    paste0("This workbook contains the outputs of the data cleaning process. ",
    "The raw_data sheet holds the original survey export from ONA; ",
    "clean_data holds the dataset after all validated changes were applied; ",
    "cleaning_log holds the full record of every change made, including ",
    "other-response recoding. Update this description to reflect the specific ",
    "round, location, and scope of this data collection exercise."),
  data_collection_round = NULL,
  prepared_by = NULL,
  sheet_names = c(readme = "readme", raw = "raw_data", clean = "clean_data", log =
    "cleaning_log"),
  mmc_colors = c("#003D58", "#00A2A5", "#AFDFE4", "#D5EEF0", "#FFE07C", "#B88AAB",
    "#BBD876", "#FBBC75", "#F8AB9E", "#5B9E62", "#009BD9", "#F15B5B", "#63193B"),
  header_font = "Arial Narrow",
  body_font = "Arial Narrow",
  freeze_panes = TRUE,
  add_filters = TRUE,
  overwrite = TRUE
)
```

## Arguments

- raw_dataset:

  The original raw dataset (with ONA label row as row 1 if
  `skip_label_row = TRUE`).

- clean_dataset:

  The cleaned dataset produced by
  [`apply_cleaning_log()`](apply_cleaning_log.md).

- combined_log:

  The combined cleaning log produced by
  [`combine_reviewed_logs()`](combine_reviewed_logs.md), or any
  dataframe in the same shape.

- output_path:

  Full path (including filename) for the output `.xlsx` file. Default
  `"./output/final/cleaning_output.xlsx"`.

- project_name:

  Short project name shown in the readme header. Default
  `"Mixed Migration Centre Data Cleaning"`.

- project_description:

  Longer project description written into the readme. Default provides a
  generic placeholder the team can overwrite.

- data_collection_round:

  Optional string for the data collection round / wave (e.g.
  `"Round 12 — Q1 2025"`). Default `NULL` (omitted).

- prepared_by:

  Name of the person or team who prepared the output. Default `NULL`
  (omitted).

- sheet_names:

  Named character vector of length 4 giving the sheet tab names. Default
  `c(readme = "readme", raw = "raw_data", clean = "clean_data", log = "cleaning_log")`.

- mmc_colors:

  Character vector of hex colours used for readme styling. Defaults to
  the full MMC colour palette.

- header_font:

  Font name for column-header rows. Default `"Arial Narrow"`.

- body_font:

  Font name for data rows. Default `"Arial Narrow"`.

- freeze_panes:

  Logical. If `TRUE` (the default), the first row and first column are
  frozen on the data sheets.

- add_filters:

  Logical. If `TRUE` (the default), auto-filters are added to the header
  row of each data sheet.

- overwrite:

  Logical. If `TRUE` (the default), an existing file at `output_path` is
  overwritten.

## Value

Invisibly returns `output_path`. The workbook is saved to disk.

## Details

The readme sheet is the landing page for any reviewer: it explains what
each other sheet contains and provides a project description cell the
team can fill in. It is styled with the Mixed Migration Centre colour
palette.
