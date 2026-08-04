# Read XLSForm Survey Sheet

Reads and processes the survey sheet from an XLSForm tool. Column names
are lowercased, rows without a `name` are removed, and `q_type` and
`list_name` columns are extracted from the `type` column.

## Usage

``` r
read_tool_survey(filepath, sheet_name = "survey", label_column = "English")
```

## Arguments

- filepath:

  Path to the XLSForm XLS/XLSX tool file.

- sheet_name:

  Name of the survey sheet. Default `"survey"`.

- label_column:

  The label column to normalise as the primary `label` column. Accepts
  an exact column name (e.g. `"label::English (en)"`), a substring to
  match (e.g. `"English"`), or `NULL` to use a bare `label` column if
  present. Default `"English"`, which automatically picks up
  `label::English (en)`.

## Value

A dataframe containing the processed survey sheet. Always includes a
`label` column (the resolved preferred language label), `q_type`, and
`list_name`, plus all other original columns.

## Details

A normalised `label` column is created from whichever label column
matches `label_column` (e.g. `label::English (en)`). This ensures all
downstream functions that reference `tool_survey$label` work
consistently regardless of whether the form uses a bare `label` column
or a language-tagged one. All original label columns are preserved
alongside the normalised one.
