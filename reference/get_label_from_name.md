# Get Choice Label from Choice Name

Looks up the label for a given choice name within a specific list in the
XLSForm choices sheet.

Looks up the label for a given choice name within a specific list in the
XLSForm choices sheet. Automatically looks up the choices sheet in the
environment if not explicitly provided.

## Usage

``` r
get_label_from_name(list.name, name, tool_choices = NULL)

get_label_from_name(list.name, name, tool_choices = NULL)
```

## Arguments

- list.name:

  The `list_name` value to filter by.

- name:

  The choice `name` value to look up.

- tool_choices:

  Optional dataframe containing the XLSForm choices sheet. If `NULL`,
  looks for `tool_choices` in the environment.

## Value

The label string for the matching choice.

The label string for the matching choice, or `NA` if not found.
