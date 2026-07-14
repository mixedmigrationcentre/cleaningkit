# Validate Country of Interview

Flags interviews for investigation where the country in which the
interview was conducted matches the respondent's country of nationality,
or matches the country where the respondent started their journey. In a
mixed-migration survey the respondent is expected to be on the move, so
either of these matches is a possible eligibility or data-quality
problem worth reviewing (e.g. a respondent interviewed in their own
country, or who never crossed a border).

## Usage

``` r
validate_country_of_interview(
  dataset,
  uuid_column = "_uuid",
  country_interview_col = "Q13",
  nationality_col = "Q31",
  journey_start_col = "Q41",
  log_name = "country_of_interview_log",
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- uuid_column:

  The name of the column containing the unique identifier. Default is
  `"_uuid"`.

- country_interview_col:

  The name of the column for the country of interview. Default is
  `"Q13"`.

- nationality_col:

  The name of the column for the respondent's nationality. Default is
  `"Q31"`.

- journey_start_col:

  The name of the column for the country where the journey started.
  Default is `"Q41"`.

- log_name:

  The name of the log to create in the list. Default is
  `"country_of_interview_log"`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that should not be treated as survey
  data.

## Value

A list containing the original dataset and the new log dataframe.

## Details

By default the check compares:

- `Q13` - country where the interview is being conducted,

- `Q31` - country of nationality of the respondent,

- `Q41` - country where the respondent started their journey.

A record produces one log entry per matching field, so an interview can
be flagged for the nationality match, the journey-start match, or both.
Comparisons are case-insensitive and whitespace-trimmed; blank values
are treated as unanswered and never count as a match.
