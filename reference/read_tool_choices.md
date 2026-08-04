# Read XLSForm Choices Sheet

Reads and processes the choices sheet from an XLSForm tool. Column names
are lowercased, rows without a `list_name` are removed, and duplicate
entries are dropped.

## Usage

``` r
read_tool_choices(filepath, sheet_name = "choices", label_column = "English")
```

## Arguments

- filepath:

  Path to the XLSForm XLS/XLSX tool file.

- sheet_name:

  Name of the choices sheet. Default `"choices"`.

- label_column:

  The label column to normalise as the primary `label` column. Accepts
  an exact column name (e.g. `"label::English (en)"`), a substring to
  match (e.g. `"English"`), or `NULL` to use a bare `label` column if
  present. Default `"English"`, which automatically picks up
  `label::English (en)`.

## Value

A dataframe containing the processed choices sheet. Always includes
`list_name`, `name`, and `label` (the resolved preferred language
label), plus any additional label columns present in the sheet.

## Details

A normalised `label` column is created from whichever label column
matches `label_column` (e.g. `label::English (en)`). This ensures
[`get_label_from_name()`](get_label_from_name.md),
[`get_name_from_label()`](get_name_from_label.md), and all other
downstream functions that reference `tool_choices$label` work
consistently regardless of form language setup.
