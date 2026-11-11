# Validate Repeated Entries in Looped Questions

Flags looped journey questions where an entry repeats an earlier one,
and writes the fix to the log: remove the repeat, move the later entries
up one place and close the list with None.

## Usage

``` r
validate_repeated_entries(
  dataset,
  uuid_column = "_uuid",
  sections = ck_repeated_entries_sections(),
  tool_choices = NULL,
  none_value = NULL,
  stop_values = c("996", "998", "999", "None", "Don't know", "Refused"),
  other_values = c("997", "9997", "Other", "Other country"),
  aliases = ck_country_aliases(),
  similarity = 0.85,
  sm_separator = "/",
  log_name = "repeated_entries_log",
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- uuid_column:

  Name of the uuid column. Default `"_uuid"`.

- sections:

  The question sets to check, in the shape returned by
  [`ck_repeated_entries_sections`](ck_repeated_entries_sections.md) (the
  default). Pass a subset to run fewer sets, or your own list for a tool
  with other question names.

- tool_choices:

  Optional. The XLSForm choices, as returned by
  [`read_tool_choices()`](read_tool_choices.md). Used to match typed
  "Other" answers to the form's countries and places. Default `NULL`.

- none_value:

  The value that means None, written into the freed slot when the list
  had no closing answer. `NULL` (the default) uses `"None"` for a
  labelled export and `"996"` for a coded one, judged from the country
  columns.

- stop_values:

  Values that end the list (None, Don't know, Refused), as codes or
  labels. They are never treated as repeats. `none_value` is always
  included. Default
  `c("996", "998", "999", "None", "Don't know", "Refused")`.

- other_values:

  Values of the country or place question that mean "Other", as codes or
  labels. Default `c("997", "9997", "Other", "Other country")`.

- aliases:

  Other spellings of country names, see
  [`ck_country_aliases`](ck_country_aliases.md). Only used with
  `tool_choices`.

- similarity:

  A number above 0 and up to 1. Two typed texts that are at least this
  similar (1 minus the edit distance over the longer length) count as a
  possible repeat. Default `0.85`. With `1`, only texts that differ in
  case, spacing or punctuation match.

- sm_separator:

  The separator between a select-multiple question and its choice in the
  sub-column names. Default `"/"`.

- log_name:

  Name of the log in the returned list. Default
  `"repeated_entries_log"`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that should not be treated as survey
  data.

## Value

A list containing:

- checked_dataset:

  The original dataset with one logical flag column per question set
  (`repeated_<set name>`, `TRUE` = flagged).

- \<log_name\>:

  The log, with columns `uuid`, `old_value`, `question`, `issue` and
  `check_binding`.

## Details

By default three question sets are checked (see
[`ck_repeated_entries_sections`](ck_repeated_entries_sections.md)):

- **Countries transited** (Q47 to Q54): the next country is the same as
  the one before.

- **Main stops** (Q56 to Q70): the next stop has the same country *and*
  place as the one before. Same country with a different place is kept.

- **Dangerous locations** (Q98 to Q117): any location with the same
  country and place as an earlier one, wherever it is in the loop.

For countries and stops only entries that follow each other count.
`Kenya, Kenya, Uganda` becomes `Kenya, Uganda, None`;
`Kenya, Uganda, Tanzania, Kenya` is left as it is. A run such as
`Kenya, Kenya, Kenya` collapses to one `Kenya`.

The form only opens the next entry when the one before is not None or
Refused, so blanking a repeat in the middle would leave the record
breaking the form's own skip logic. Every column of the later entries is
therefore moved up - the "please specify" texts, calculates and
select-multiple sub-columns included. If the list ended in a closing
answer (None, Refused) that answer moves up too; if every slot was
filled, the freed slot gets `none_value` and its other columns become
blank.

Blank values and `stop_values` are never treated as repeats. Both the
codes (`996`) and the labels (`None`) of the closing answers are
recognised, so the check works on coded and labelled exports.

**Certain and possible repeats.** A repeat is *certain* when the same
answer is given twice in a row. Its log rows start with "Back-to-back
repeat" and [`apply_cleaning_log()`](apply_cleaning_log.md) applies them
whatever the reviewer filled in. A repeat is only *possible* when

- the two entries are not next to each other (dangerous locations),
  because the removed entry's own answers, such as its risks, go with
  it; or

- they only match through a typed "Other" answer: the text names the
  same country or place as the other entry (in any language of the form,
  through `aliases`, or with a small typo), or two typed texts are
  nearly the same (`similarity`).

Possible repeats start with "Possible repeat" and are only applied when
the reviewer accepts them: set **Action taken** to `recoded` on any one
row of the record and copy its suggested value into **New value**;
[`apply_cleaning_log()`](apply_cleaning_log.md) then applies all of that
record's rows. Rows left as `no_action` keep the answers as they are.

Typed answers are only matched to the form's choices when `tool_choices`
is given; without it, two typed texts are still compared with each
other.

The function only writes a log - the data is not changed. Each log row
is one cell that has to change, and its issue says what was repeated and
the suggested new value. All rows from one record and question set share
a `check_binding`, so they get one colour on the cleaning log.

## Examples

``` r
if (FALSE) { # \dontrun{
repeated_entries_log <- cleaningkit::validate_repeated_entries(
  dataset = raw_data,
  uuid_column = "_uuid",
  tool_choices = tool_choices,
  log_name = "repeated_entries_log",
  skip_label_row = TRUE
)

# only the main stops
sets <- cleaningkit::ck_repeated_entries_sections()["main_stops"]
repeated_entries_log <- cleaningkit::validate_repeated_entries(
  dataset = raw_data,
  sections = sets
)
} # }
```
