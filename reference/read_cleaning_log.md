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
  sheet = 2,
  file_pattern = "_follow-ups_edited\\.xlsx$",
  extra_questions = NULL,
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

  Sheet to read from each Excel file. Accepts a name or integer. Default
  `2`.

- file_pattern:

  Regex pattern used to identify cleaning log files when `path` is a
  directory. Default `"_follow-ups_edited\\.xlsx$"`.

- extra_questions:

  Optional character vector of additional question values to allow
  through the question filter (e.g. computed columns that are not in the
  raw dataset but are valid targets). Default `NULL`.

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

**Sheet selection:** `sheet` accepts either a sheet name or an integer
index. The default `2` matches the output of
[`create_cleaning_log()`](create_cleaning_log.md) where sheet 1 is the
dataset and sheet 2 is the cleaning log.

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
