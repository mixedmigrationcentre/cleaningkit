# Detect the select-multiple conventions used by a parent question

Two independent things have to be detected, and getting either wrong
writes values the export never uses:

1.  **Header tokens** — are sub-columns named with the choice *label*
    (`Q83/Insufficient access to basic goods`) or the choice *code*
    (`Q83/2`)?

2.  **Selected marker** — what does a selected cell contain? Either
    `"1"` (binary export) or the choice text itself (label export, where
    an unselected cell is simply blank).

Detection looks at every sub-column of the question (not a 5-column
sample), then at the parent concat column, then at the rest of the
dataset. If nothing in the data indicates a binary export, the
choice-text convention wins: a label export must never have `0`/`1`
introduced into it.

## Usage

``` r
.detect_sm_convention(
  dataset,
  parent_col,
  sm_separator,
  list_name = NULL,
  tool_choices = NULL,
  skip_label_row = TRUE,
  cache = NULL
)
```

## Arguments

- dataset:

  The dataset.

- parent_col:

  The parent select-multiple column name.

- sm_separator:

  Sub-column separator.

- list_name:

  The `list_name` of the question's choices.

- tool_choices:

  The XLSForm choices sheet.

- skip_label_row:

  Whether the first row is the ONA label row.

- cache:

  Optional environment used to memoise detection per question.

## Value

A list with `use_label` (logical, headers carry labels), `value_kind`
(`"binary"`, `"suffix"` or `"label"`), `sel_fn` (`f(suffix, label)`
giving the value to write when marking a choice selected), `sub_cols`
and `suffixes`.
