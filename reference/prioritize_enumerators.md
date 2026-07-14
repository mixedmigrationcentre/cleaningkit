# Prioritise Most Suspicious Enumerators

Aggregates the validation logs produced by the `validate_*` functions
and ranks enumerators by how suspicious their work looks. Because every
log shares the same `uuid` / `old_value` / `question` / `issue`
structure and the raw dataset holds both the uuid and the enumerator id,
each flag can be traced back to the enumerator who collected it and then
rolled up into a single priority table.

## Usage

``` r
prioritize_enumerators(
  dataset,
  uuid_column = "_uuid",
  enumerator_column = "username",
  logs = NULL,
  weights = NULL,
  diversity_bonus = 0.5,
  include_clean = FALSE,
  min_interviews = 1,
  output_name = "enumerator_priority",
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A list produced by the `validate_*` functions, containing
  `checked_dataset` and one or more log dataframes.

- uuid_column:

  The name of the unique-identifier column in `checked_dataset`. Default
  `"_uuid"`.

- enumerator_column:

  The name of the enumerator-id column in `checked_dataset`. Default
  `"username"`.

- logs:

  Optional character vector naming which log elements to include. If
  `NULL` (the default) all dataframes in the list that look like logs
  (i.e. contain a `uuid` column, excluding `checked_dataset`) are used.

- weights:

  Optional named numeric vector giving a weight per log name (e.g.
  `c(back_to_back_log = 2, duration_log = 1)`). Logs not named default
  to weight 1.

- diversity_bonus:

  Numeric \>= 0. How much each additional distinct check inflates the
  score. `0` ignores diversity; `0.5` (the default) adds 50% per extra
  check.

- include_clean:

  Logical. If `TRUE`, enumerators with no flags are also listed (with a
  score of 0). Default `FALSE`.

- min_interviews:

  Integer. Enumerators with fewer than this many interviews are dropped
  to reduce small-sample noise (the "(unknown)" group is always kept).
  Default `1`.

- output_name:

  The name under which to store the priority table in the list. Default
  `"enumerator_priority"`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of `checked_dataset`
  is dropped when building the uuid-to-enumerator lookup, matching the
  ONA label/description row handling of the other functions.

## Value

The input list with an added `output_name` dataframe: one row per
enumerator, ranked from most to least suspicious.

## Details

The function reflects the idea that no single check is conclusive: an
enumerator who trips several *different* checks (e.g. short duration
*and* back-to-back interviews *and* repeated logical issues) is more
suspicious than one who trips a single check many times. This is
captured by `diversity_bonus`, which increases the score for each
additional distinct check an enumerator triggers: \$\$priority\\score =
weighted\\flags \times (1 + diversity\\bonus \times
(n\\checks\\triggered - 1))\$\$ where `weighted_flags` is the sum, over
every included log, of the number of the enumerator's interviews flagged
by that log (optionally multiplied by a per-log weight).

The table also reports `flag_rate` (share of the enumerator's interviews
flagged at least once), so a productive enumerator with many interviews
is not penalised purely for volume. Rows are ranked by `priority_score`,
then by number of distinct checks, then by flag rate. The result is a
review queue, not an automatic rejection list.
