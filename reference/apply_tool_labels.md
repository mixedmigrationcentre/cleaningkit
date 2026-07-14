# Apply Tool Labels

Renames the analysis output options columns using an XLSForm tool
choices dictionary before a user can save the analysis.

## Usage

``` r
apply_tool_labels(dataset, column_name, tool_choices)
```

## Arguments

- dataset:

  The dataset to modify

- column_name:

  The name of the column to relabel

- tool_choices:

  The XLSForm choices sheet dataframe

## Value

The updated dataset
