# Read and Prepare Filled Cleaning Log(s)

Reads one or more filled cleaning log Excel files from a directory (or a
single file path), filters to valid uuids and known questions,
deduplicates rows where the same `uuid + question` was reviewed more
than once, and returns a single clean dataframe ready for
[`evaluate_cleaning_log()`](evaluate_cleaning_log.md).

## Usage

``` r
read_cleaning_log(
  path,
  raw_dataset,
  raw_uuid_column = "_uuid",
  uuid_col = "Survey UUID",
  action_col = "Action taken",
  question_col = "Question number",
  old_value_col = "Old value",
  new_value_col = "New value",
  sheet = NULL,
  file_pattern = "_follow-ups_edited\\.xls[xm]$",
  extra_questions = NULL,
  default_blank_action = "no_action",
  skip_label_row = TRUE,
  verbose = TRUE
)
```

## Arguments

- path:

  Either a path to a directory containing one or more cleaning log Excel
  files, or a direct path to a single `.xlsx` file.

- raw_dataset:

  The original raw dataset. Used to filter rows to valid uuids and known
  question columns.

- raw_uuid_column:

  Name of the uuid column in `raw_dataset`. Default `"_uuid"`.

- uuid_col:

  Name of the uuid column in the cleaning log. Default `"Survey UUID"`.

- action_col:

  Name of the action column in the cleaning log. Default
  `"Action taken"`.

- question_col:

  Name of the question column in the cleaning log. Default
  `"Question number"`.

- old_value_col:

  Name of the old-value column. Default `"Old value"`.

- new_value_col:

  Name of the new-value column. Default `"New value"`.

- sheet:

  Sheet to read from each Excel file. Default `NULL` resolves it per
  file by name (`"cleaning_log"`, then the first sheet). Accepts a name
  or an integer to override, or a vector/list of the same length as the
  files.

- file_pattern:

  Regex pattern used to identify cleaning log files when `path` is a
  directory. Default `"_follow-ups_edited\\.xls[xm]$"`, which matches
  both plain and macro-enabled logs (see the `macro` argument of
  [`create_cleaning_log()`](create_cleaning_log.md)).

- extra_questions:

  Optional character vector of additional question values to allow
  through the question filter (e.g. computed columns that are not in the
  raw dataset but are valid targets). Default `NULL`.

- default_blank_action:

  Action written into rows whose `action_col` cell is blank. Default
  `"no_action"`: a flagged row the reviewer did not fill in is taken to
  mean the data point stays as it is. Set to `NULL` to leave blank cells
  blank.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of `raw_dataset` is
  removed before extracting valid uuids.

- verbose:

  Logical. If `TRUE` (the default), messages are printed summarising
  files read, rows filtered, and deduplication results.

## Value

A single deduplicated dataframe containing all cleaning log rows, ready
to pass to [`evaluate_cleaning_log()`](evaluate_cleaning_log.md).

## Details

**File discovery:** when `path` is a directory, all files matching
`file_pattern` are read and stacked. When `path` is a single `.xlsx`
file it is read directly. An error is raised if no matching files are
found.

**Column check:** before the files are stacked, their headers are
compared with [`check_log_files()`](check_log_files.md). Because the
files are combined with [`rbind()`](https://rdrr.io/r/base/cbind.html),
a single file with an extra, missing or renamed column would otherwise
fail with "numbers of columns of arguments do not match", which names no
file. Instead the function stops with the offending file name and the
exact columns that are missing or extra. Files that cannot be opened at
all are not treated as mismatches - they are warned about and skipped as
before. Run [`check_log_files()`](check_log_files.md) directly for the
full report.

**Sheet selection:** the default `NULL` finds the sheet by name, per
file - `"cleaning_log"`, falling back to the first sheet if no sheet
carries that name. Naming it rather than numbering it is what lets the
log live in a workbook that also holds the dataset, the readme and the
other responses without the reader having to know the tab order. Pass a
name or an integer index to override.

**Blank actions:** a reviewer only fills in the rows that need a change,
so a flagged row left with an empty **Action taken** means the data
point stays as it is. Those blanks are filled with
`default_blank_action` (`"no_action"` by default) as soon as the files
are stacked, before any filtering or deduplication, so every later step
sees an explicit action on every row. Pass `default_blank_action = NULL`
to leave blank cells untouched.

**Filtering:** rows whose `uuid` is not in the raw dataset and rows
whose `question` is not a column in the raw dataset are silently dropped
(with a summary message). Rows with `action == "no_action"` have their
`New value` set to the `Old value` (no change should be applied).

**Deduplication:** when the same `uuid + question` pair appears in more
than one row (e.g. the same cell was reviewed in two separate log files
or two reviewers completed the same row), the most decisive action is
kept using the following priority:

1.  `recoded` — a specific new value was chosen

2.  `addition` — a blank was filled in

3.  `other` — a change was made that doesn't fit a standard category

4.  `delete_data_point` — the cell was blanked

5.  `no_action` — reviewer confirmed no change needed

6.  `NA` or anything else — lowest priority

`discard` rows are handled separately: only one `discard` row is kept
per uuid.

**Duplicate check:** after deduplication, if any `uuid + question` pair
still appears more than once the function stops with a clear error
listing the offending pairs, because applying an ambiguous log would
corrupt the dataset.
