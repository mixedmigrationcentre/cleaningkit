# Default flag columns added to the `dataset` sheet

The reviewer-facing `dataset` sheet of a cleaning log carries a small
block of helper columns - one per survey-level check - so a reviewer can
filter the raw data down to the surveys a check flagged and decide, in
place, whether to keep or discard them.

## Usage

``` r
ck_flag_column_defaults()
```

## Value

A named list: column header -\> either a character vector of
`check_binding` prefixes, or a list of `prefixes`, `value` and `label`.

## Details

Each entry maps a column header to the `check_binding` prefixes that
feed it. `check_binding` is written by every `validate_*` function in
the shape `"<check_id> ~/~ <uuid>"` (soft duplicates use
`"soft_duplicate ~/~ <uuid> ~/~ <uuid>"` and duplicated answers
`"dup_q ~/~ <question> ~/~ <enumerator> ~/~ <value>"`), so the text
before the first `~/~` identifies the check that raised the row.

An entry is either a bare character vector of prefixes, or a list with:

- `prefixes`:

  character vector of `check_binding` prefixes.

- `value`:

  which log column fills the cells - `"old_value"` (the default) or
  `"issue"`. Use `"issue"` where the raw value means nothing on its own.

- `label`:

  what the ONA label row says the column came from, written as
  `"Flagged by: <label>"`. Defaults to the prefixes.

The defaults cover the five survey-level checks a reviewer normally
weighs together when judging whether a whole interview is sound:

- `duration`:

  [`validate_duration`](validate_duration.md) - `"duration_check"`.
  Value: the survey duration in minutes.

- `completeness`:

  [`validate_completeness`](validate_completeness.md) -
  `"completeness_check"`. Value: the number of non-empty cells.

- `refused`:

  [`validate_refused`](validate_refused.md) - `"refused_check"`. Value:
  the number of refused responses.

- `back to back`:

  [`validate_back_to_back`](validate_back_to_back.md) -
  `"back_to_back_check"`. Value: the **issue**, not the raw value. The
  raw value there is the interview start time, which says nothing on its
  own - the gap to the previous interview, the enumerator and whether
  the two overlap are all in the issue text, and that is what a reviewer
  needs in order to judge the survey.

- `similarity`:

  [`validate_similar_surveys`](validate_similar_surveys.md) and
  [`validate_similar_questions`](validate_similar_questions.md) -
  `"soft_duplicate"` and `"dup_q"`. Value: the **issue**, not the raw
  value. The raw value is a count of similar columns or the duplicated
  answer, neither of which can be judged without the threshold, the
  enumerator and the other survey involved - all of which the issue
  names. Labelled with the two log names rather than the binding
  prefixes, which are not names a reviewer would recognise.

Pass your own list to `flag_columns` to rename a column, add one for a
check of your own, or drop one you do not want:


    my_flags <- ck_flag_column_defaults()
    my_flags[["outliers"]] <- "outlier_check"
    my_flags[["refused"]]  <- NULL

    # show the issue rather than the raw value
    my_flags[["duration"]] <- list(prefixes = "duration_check", value = "issue")

## See also

[`create_cleaning_log`](create_cleaning_log.md), which writes these
columns, and [`ck_flag_column_names`](ck_flag_column_names.md) for the
headers alone.

## Examples

``` r
ck_flag_column_defaults()
#> $duration
#> [1] "duration_check"
#> 
#> $completeness
#> [1] "completeness_check"
#> 
#> $refused
#> [1] "refused_check"
#> 
#> $`back to back`
#> $`back to back`$prefixes
#> [1] "back_to_back_check"
#> 
#> $`back to back`$value
#> [1] "issue"
#> 
#> 
#> $similarity
#> $similarity$prefixes
#> [1] "soft_duplicate" "dup_q"         
#> 
#> $similarity$value
#> [1] "issue"
#> 
#> $similarity$label
#> [1] "similar_surveys_log, similar_questions_log"
#> 
#> 
```
