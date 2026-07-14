# Read XLSForm Survey Sheet.

Reads and processes the survey sheet from an XLSForm tool. Column names
are lowercased, rows without a name are removed, and `q_type` and
`list_name` columns are extracted from the `type` column.

## Usage

``` r
read_tool_survey(filepath, sheet_name = "survey")
```

## Arguments

- filepath:

  Path to the XLSForm XLS/XLSX tool file.

- sheet_name:

  Name of the survey sheet (default is "survey").

## Value

A dataframe containing the processed survey sheet with added `q_type`
and `list_name` columns.
