# Validate Duplicate Answers for Specific Questions Per Enumerator

For each question in `questions_to_check`, groups surveys by enumerator
and flags any answer value that appears in more than one of that
enumerator's surveys. Only questions where at least one duplicate is
found are reported. All surveys that share the same duplicated answer
for the same question get an identical `check_binding` so they are
coloured as a group in the review workbook.

## Usage

``` r
validate_duplicate_questions(
  dataset,
  questions_to_check,
  uuid_column = "_uuid",
  enumerator_column = "username",
  log_name = "duplicate_questions_log",
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- questions_to_check:

  A character vector of column names to check for duplicate answers
  within each enumerator's surveys.

- uuid_column:

  Name of the unique-identifier column. Default `"_uuid"`.

- enumerator_column:

  Name of the enumerator column used to group surveys. Default
  `"username"`.

- log_name:

  Name of the log element in the returned list. Default
  `"duplicate_questions_log"`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that must not be treated as a survey
  record.

## Value

A list containing:

- checked_dataset:

  The original dataset, unchanged.

- \<log_name\>:

  A dataframe with columns `uuid`, `old_value` (the duplicated answer),
  `question` (the column name), `issue`, and `check_binding`. One row
  per survey per flagged question. Empty (zero rows) if no duplicates
  are found.

## Details

This is complementary to
[`validate_duplicates()`](validate_duplicates.md): where that function
uses Gower distance to detect globally similar surveys, this function
pinpoints specific questions (e.g. a destination country, a landmark, a
journey start point) that should vary between respondents but are
suspiciously repeated within one enumerator's workload.

A common fraud pattern is an enumerator copying one answer across many
records. Passing `questions_to_check = c("Q41", "Q59", "Q13")` will
independently check each question; only those that are actually
duplicated produce log rows.

Blank and `NA` values are never treated as duplicates — only non-empty
answers are compared, so unanswered questions do not generate false
positives.
