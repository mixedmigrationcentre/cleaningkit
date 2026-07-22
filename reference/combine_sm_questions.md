# Combine multiple ONA select-multiple questions into a single consolidated column

Takes several source select-multiple questions (e.g. QO100, Q100, Q104,
Q108, Q112, Q116) — each with its own parent concat column and
label-value dummy sub-columns — and collapses them into a single target
select-multiple column (e.g. Q118a) and its dummy sub-columns.

## Usage

``` r
combine_sm_questions(
  dataset,
  source_questions,
  target_question,
  target_choices,
  choice_map = NULL,
  sm_separator = "/"
)
```

## Arguments

- dataset:

  A dataframe (ONA export). The ONA label row should already have been
  removed before calling this function.

- source_questions:

  Character vector of source parent column names, e.g.
  `c("QO100", "Q100", "Q104", "Q108", "Q112", "Q116")`.

- target_question:

  Name of the target parent column, e.g. `"Q118a"`.

- target_choices:

  Character vector of valid target choice labels exactly as they appear
  as suffixes in the target dummy column names (after the
  `sm_separator`). Determines which choices are kept and their order in
  the parent concat.

- choice_map:

  Named character vector remapping source choice labels to target choice
  labels. Names are source labels, values are target labels. E.g.
  `c("Trafficking or exploitation" = "Trafficking and exploitation")`.
  Default `NULL` (no remapping).

- sm_separator:

  Separator between a select-multiple parent column name and its dummy
  sub-columns. Default `"/"` (ONA export style).

## Value

The dataset with the target parent column and all target dummy
sub-columns added (or overwritten if they already exist). Target dummy
sub-columns use label-value convention: the choice label when selected,
`NA` when not selected.

## Details

This function handles the **label-value convention** used by ONA
exports: a dummy sub-column contains the choice label (i.e. the column
suffix) when that choice is selected, and `NA`/blank when it is not.

The target parent concat is the union of all unique choices selected
across the source questions (de-duplicated, space-separated, ordered by
`target_choices`). Each target dummy sub-column contains the choice
label when selected across ANY source, and `NA` when not selected.

Choice labels in the source and target may differ (e.g. "Trafficking or
exploitation" vs "Trafficking and exploitation"). Use `choice_map` to
remap source labels to target labels. Any source choice not present in
`target_choices` after remapping is silently dropped.
