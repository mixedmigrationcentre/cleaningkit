# Describe a round for the workbooks to remember

Builds the round memory that
[`create_review_workbook()`](create_review_workbook.md) and
[`export_final_output()`](export_final_output.md) write into their
hidden sheets: every survey ID checked so far (the previous rounds' plus
this one's), a fingerprint of each survey in this round, and optionally
the questionnaire, the logical checklist and any settings, so the next
round needs only the new ONA download and the last workbook.

## Usage

``` r
ck_round_info(
  dataset,
  round_name,
  previous = NULL,
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  tool_survey = NULL,
  tool_choices = NULL,
  logical_checklist = NULL,
  settings = NULL,
  checked_on = Sys.Date()
)
```

## Arguments

- dataset:

  The surveys checked in this round (after
  [`keep_new_records()`](keep_new_records.md)).

- round_name:

  Free text naming the round, e.g. `"R7"` or `"Nov week 2"`. Rounds are
  ordered by the date they were checked, never by name.

- previous:

  The memory of earlier rounds: a `ck_round_info` from
  [`read_round_info()`](read_round_info.md), a character vector of
  survey IDs, or `NULL` for the first round.

- uuid_column, skip_label_row:

  As in [`round_fingerprint()`](round_fingerprint.md).

- tool_survey, tool_choices:

  The XLSForm's survey and choices sheets. Default `NULL` carries over
  those from `previous`, if any.

- logical_checklist:

  The logical checklist used, if any. Default `NULL` carries over the
  one from `previous`.

- settings:

  A named list of single strings to keep with the round, for example an
  app's settings. Default `NULL` carries over those from `previous`.

- checked_on:

  Date of the round. Default today.

## Value

An object of class `ck_round_info`.

## Examples

``` r
df <- data.frame(`_uuid` = c("a", "b"), Q1 = c("1", "2"), check.names = FALSE)
info <- ck_round_info(df, "R1", skip_label_row = FALSE)
info
#> <ck_round_info>
#>   Round:        R1 (checked 2026-11-23)
#>   In this round: 2 survey(s)
#>   Checked so far: 2 survey(s)
#>   Questionnaire: no 
```
