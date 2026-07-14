# Read and Prepare Filled Other-Responses Files

Reads one or more filled other-responses Excel files from a directory
(or a single file path), renames the verbose column headers to short
working names, filters to valid uuids and joins the question metadata
from `other_db`, classifies each row into one of three action types, and
returns a single cleaning-log dataframe ready for
[`apply_other_responses()`](apply_other_responses.md).

## Usage

``` r
read_other_responses(
  path,
  dataset,
  other_db,
  tool_choices,
  uuid_column = "_uuid",
  log_uuid_col = "uuid",
  sm_separator = "/",
  file_pattern = "_other_responses_edited\\.xlsx$",
  skip_questions = NULL,
  skip_label_row = TRUE,
  verbose = TRUE
)
```

## Arguments

- path:

  Either a path to a directory containing one or more other-responses
  Excel files, or a direct path to a single `.xlsx` file.

- dataset:

  The current working dataset (after any prior cleaning). Used to filter
  to valid uuids and to look up current values of parent columns for
  `select_multiple` recoding.

- other_db:

  The `other_db` dataframe produced by
  [`get_other_db()`](get_other_db.md), containing at least `name`,
  `ref_question`, `q_type`, and `option_other`.

- tool_choices:

  The XLSForm choices sheet dataframe (works with Kobo, ONA, or any
  other XLSForm-based tool), used to resolve choice labels to codes for
  recode actions. Passed to
  [`get_name_from_label()`](get_name_from_label.md).

- uuid_column:

  Name of the uuid column in `dataset`. Default `"_uuid"`.

- log_uuid_col:

  Name of the uuid column in the other-responses log files. Default
  `"uuid"` (as produced by
  [`prepare_other_responses()`](prepare_other_responses.md)). Set to
  `"_uuid"` if your files use the raw ONA column name.

- sm_separator:

  Separator between a select-multiple parent column name and its binary
  sub-columns in `dataset`. Default `"/"` (ONA export style).

- file_pattern:

  Regex pattern used when `path` is a directory. Default
  `"_other_responses_edited\\.xlsx$"`.

- skip_questions:

  Character vector of question names to exclude from processing (e.g.
  free-text comments columns). Default `NULL`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of `dataset` is
  treated as the ONA label/description row and excluded from the
  valid-uuid list so it cannot match against log file uuids.

- verbose:

  Logical. If `TRUE` (the default), progress messages are printed.

## Value

A dataframe with columns `uuid`, `question`, `action_taken`,
`old_value`, `new_value`.

## Details

**The three action types and what they produce:**

- `true_other`:

  A genuine new answer (e.g. a translation). Overwrites the `_other`
  text column with the value in `TRUE other ...`. The parent question is
  not touched.

- `recode`:

  The response actually matches an existing choice. One or more of the
  `EXISTING other ...` columns is filled. For `select_one`: blanks the
  `_other` text column, sets the parent to the matched choice code. For
  `select_multiple`: blanks the `_other` text column, removes the
  `other` option from the parent concatenation, and adds the matched
  choice(s).

- `remove`:

  The response is invalid (`INVALID other == "Yes"`). Blanks the
  `_other` text column and removes/blanks the parent question reference.

**UUID matching:** the dataset uuid column (`uuid_column`) and the
other-responses file uuid column (`log_uuid_col`) are resolved
independently so they can have different names (e.g. `"_uuid"` in the
dataset and `"uuid"` in the log file). The ONA label/description row is
excluded from the dataset uuid list when `skip_label_row = TRUE`.

**Mutual exclusivity:** each row must have exactly one of `true_other`,
`existing_other`, or `invalid_other` filled. Rows with zero or more than
one filled are flagged with a warning and excluded.

**Output shape:** the returned dataframe has columns `uuid`, `question`,
`action_taken`, `old_value`, `new_value` ready for
[`apply_other_responses()`](apply_other_responses.md).
