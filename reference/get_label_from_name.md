# Get Choice Label from Choice Name

Looks up the label for a given choice name within a specific list in the
XLSForm choices sheet. Automatically looks up the choices sheet in the
environment if not explicitly provided.

## Usage

``` r
get_label_from_name(list.name, name, tool_choices = NULL, label_column = NULL)
```

## Arguments

- list.name:

  The `list_name` value to filter by.

- name:

  The choice `name` value to look up.

- tool_choices:

  Optional dataframe containing the XLSForm choices sheet. If `NULL`,
  looks for `tool_choices` in the environment.

- label_column:

  Optional. The label column to read the label from, as an exact column
  name (e.g. `"label::Arabic (ar)"`) or a case-insensitive substring of
  one (e.g. `"Arabic"`). When the column is not found, or the choice has
  no label in it, the `label` column is used instead. If `NULL` (the
  default), only `label` is read.

## Value

The label string for the matching choice, or `NA` if not found.
