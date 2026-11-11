# Default question sets for validate_repeated_entries()

Returns the three looped question sets of the 4Mi XLSForm that
[`validate_repeated_entries`](validate_repeated_entries.md) checks by
default. Use it as a starting point when your tool numbers the questions
differently: change, add or drop sets and pass the result to the
`sections` argument.

## Usage

``` r
ck_repeated_entries_sections()
```

## Value

A named list of question sets.

## Details

Each set is a list with:

- `label`:

  Name used in the issue message, e.g. `"Main stops"`.

- `item`:

  What one entry is called in the issue message, e.g. `"stop"` gives
  "stop 2 (Q59/Q60)".

- `slots`:

  A list with one named character vector per entry, in the order they
  are asked. Every slot of a set must have the same length and its
  columns in the same order, so the columns of one entry can move into
  the entry above it.

- `scope`:

  `"adjacent"` (the default) compares each entry with the one straight
  before it. `"any"` compares it with every earlier entry, so the same
  location cannot appear twice anywhere in the loop.

- `country_lists`, `place_lists`:

  Optional. Names of the XLSForm choice lists the country and place
  questions use. With `tool_choices`, typed "Other" answers are matched
  against every label of these lists, in every language of the form.

- `place_filter`:

  Optional. The choices column that links a place to its country (the
  `choice_filter` column), `"cf"` in 4Mi.

The names inside a slot decide which columns are compared:

- `country`:

  Required. The country question. An entry whose country is blank or one
  of `stop_values` ends the list.

- `place`:

  Optional. When present, an entry only counts as a repeat if both
  country and place match.

- `country_other`, `place_other`:

  Optional. The "please specify" answer. It is compared too, so two
  "Other" answers only match when what was typed or picked matches.

Columns without a name (e.g. why_stop, risks, perpetrators and their
"please specify" texts) are not compared but move with their entry.
Select-multiple sub-columns (`Q58/1`, `Q58/2`, ...) are found
automatically and move with their parent column.

The defaults are:

- `countries_transited`:

  Q47 to Q54, compared on country, next to each other only.

- `main_stops`:

  Q56 to Q70 in five blocks of country, place and why_stop, compared on
  country + place, next to each other only.

- `dangerous_locations`:

  Q98 to Q117 in five blocks of country, place, risks and perpetrators,
  compared on country + place across the whole loop. Q98/Q99 is the
  first dangerous location.

A journey can pass through the same country or stop twice, so countries
and stops are only checked next to each other. A dangerous location
should only be listed once.

## Examples

``` r
sets <- ck_repeated_entries_sections()
names(sets)
#> [1] "countries_transited" "main_stops"          "dangerous_locations"

# run only the countries transited check
sets <- sets["countries_transited"]
```
