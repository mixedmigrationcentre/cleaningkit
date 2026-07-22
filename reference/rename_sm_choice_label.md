# Rename a Choice Label in a Select-Multiple Question

Renames a choice label across all four places where it appears in an ONA
export: the dummy sub-column *name*, the parent concat column *values*,
the dummy sub-column *values* (label-value convention), and the ONA
*label row* (row 1 of the dataset). Only the column whose name starts
with `<question_col><sm_separator>` and ends with `old_choice` is
renamed; all other column names in the dataset are left unchanged.

## Usage

``` r
rename_sm_choice_label(
  dataset,
  question_col,
  old_choice,
  new_choice,
  sm_separator = "/",
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe (ONA export, label row still present as row 1).

- question_col:

  Name of the select-multiple parent column whose choice is being
  renamed, e.g. `"Q100"`.

- old_choice:

  The current choice label as it appears in the dataset, e.g.
  `"Trafficking or exploitation"`. Must match exactly (case-sensitive).

- new_choice:

  The new choice label to use, e.g. `"Trafficking and exploitation"`.

- sm_separator:

  Separator between the parent column name and the choice label in dummy
  sub-column names. Default `"/"` (ONA export style).

- skip_label_row:

  Logical. If `TRUE` (the default), row 1 of the dataset is treated as
  the ONA label/description row and is also updated (any occurrence of
  `old_choice` in that row is replaced with `new_choice`). Set to
  `FALSE` if the label row has already been removed.

## Value

The dataset with the choice label renamed in all four locations. Column
order is preserved; the renamed dummy sub-column occupies the same
position as before.

## Details

The function handles the **label-value convention** used by ONA exports:
a dummy sub-column holds the choice label as its cell value when
selected and `NA`/blank when not selected. The parent concat column
stores selected choices as a space-separated string of labels; renaming
replaces every occurrence of `old_choice` in that string with
`new_choice`.

## Examples

``` r
if (FALSE) { # \dontrun{
dataset <- rename_sm_choice_label(
  dataset      = dataset,
  question_col = "Q100",
  old_choice   = "Trafficking or exploitation",
  new_choice   = "Trafficking and exploitation"
)
} # }
```
