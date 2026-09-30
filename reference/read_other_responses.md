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
  sheet = NULL,
  file_pattern = "_follow-ups_edited\\.xls[xm]$",
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

- sheet:

  Sheet holding the other responses. Default `NULL` resolves it per file
  by name: `"other_responses"` as written by
  [`create_review_workbook()`](create_review_workbook.md) and
  [`save_other_responses()`](save_other_responses.md), falling back to
  `"Sheet1"` for a file produced before the two logs were merged, and to
  the first sheet if neither name is present. Pass a name or an integer
  to override. Resolving by name is what lets the same file carry the
  cleaning log on one sheet and the other responses on another.

- file_pattern:

  Regex pattern used when `path` is a directory. Default
  `"_follow-ups_edited\\.xls[xm]$"` - the merged review workbook, which
  holds both logs. Pass `"_other_responses_edited\\.xlsx$"` to read
  files produced by the older standalone
  [`save_other_responses()`](save_other_responses.md) route.

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
  text column with the value in
  `Input translation or improved text ...`. The parent question is not
  touched.

- `recode`:

  The response actually matches an existing choice. The
  `Correct to existing answer option ...` column is filled (older logs
  with several numbered `EXISTING other` columns are still read and
  merged). For `select_one`: blanks the `_other` text column, sets the
  parent to the matched choice code. For `select_multiple`: blanks the
  `_other` text column, removes the `other` option from the parent
  concatenation, and adds the matched choice(s).

- `remove`:

  The response is invalid (`Invalid other ... == "Yes"`). Blanks the
  `_other` text column and removes/blanks the parent question reference.

**Which sheet is read:** the sheet is found by name, not by position -
`"other_responses"` first, then `"Sheet1"` as written before the
cleaning log and the other responses were merged into one workbook, then
the first sheet. A merged review workbook and an older standalone
other-responses file therefore both read with no extra argument, even
when they sit side by side in the same folder.

**Header names:** the reviewer columns are matched by prefix, case
insensitively, against both the headers written by the current
[`prepare_other_responses()`](prepare_other_responses.md) and the
earlier `TRUE other` / `EXISTING other` / `INVALID other` /
`FOLLOW-UP message` headers, so a file reviewed before the rename is
read exactly as before. The patterns are defined once in
`.ck_other_review_patterns()`.

**Column check:** before the files are stacked, their headers are
compared with [`check_log_files()`](check_log_files.md). Because the
files are combined with [`rbind()`](https://rdrr.io/r/base/cbind.html),
a single file with an extra, missing or renamed column would otherwise
fail with "numbers of columns of arguments do not match", which names no
file. Instead the function stops with the offending file name and the
exact columns that are missing or extra - most often an older log still
carrying three numbered `EXISTING other` columns instead of one. Files
that cannot be opened at all are not treated as mismatches; they are
warned about and skipped as before.

**UUID matching:** the dataset uuid column (`uuid_column`) and the
other-responses file uuid column (`log_uuid_col`) are resolved
independently so they can have different names (e.g. `"_uuid"` in the
dataset and `"uuid"` in the log file). The ONA label/description row is
excluded from the dataset uuid list when `skip_label_row = TRUE`.

**Mutual exclusivity:** a row may have at most one of `true_other`,
`existing_other`, or `invalid_other` filled. Rows with more than one
filled are contradictory - the reviewer has asked for two different
things on one response - so they are excluded and their uuids named in a
warning.

**Rows left blank:** a row with all three action columns blank is not an
error. It is the normal way a reviewer records that the "other" text is
a valid answer as it stands and the record should not change. Such rows
produce no cleaning-log entry (there is no data point to change, so
logging one would only pad the log) and no warning; they are counted in
the `verbose` summary as *no change (kept as-is)*. A file in which every
row is blank therefore returns an empty log quietly rather than warning.

**Output shape:** the returned dataframe has columns `uuid`, `question`,
`action_taken`, `old_value`, `new_value` ready for
[`apply_other_responses()`](apply_other_responses.md).
