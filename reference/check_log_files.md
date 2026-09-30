# Check Column Consistency Across Log Files Before Reading Them

Scans a folder for log files matching a pattern and reports how many
columns each one has, so that a column mismatch can be spotted and fixed
*before* it surfaces as an error inside
[`read_cleaning_log()`](read_cleaning_log.md) or
[`read_other_responses()`](read_other_responses.md).

## Usage

``` r
check_log_files(
  path,
  file_pattern = "\\.(csv|xlsx|xlsm|xls)$",
  sheet = 1,
  recursive = TRUE,
  ignore_case = TRUE,
  verbose = TRUE
)
```

## Arguments

- path:

  A directory containing the log files, or a character vector of file
  paths to check directly.

- file_pattern:

  Regex used to select files when `path` is a directory. Default
  `"\\.(csv|xlsx|xlsm|xls)$"`. Pass the same pattern you give to
  [`read_cleaning_log()`](read_cleaning_log.md) or
  [`read_other_responses()`](read_other_responses.md) to check exactly
  the set of files those functions will read, e.g.
  `"_follow-ups_edited\\.xls[xm]$"`.

- sheet:

  Sheet to read from each Excel file. Accepts a name or an integer, or a
  vector/list of the same length as the files to use a different sheet
  per file. Default `1`. Prefer a name, e.g. `"cleaning_log"` or
  `"other_responses"`.

- recursive:

  Logical. If `TRUE` (the default), sub-folders of `path` are searched
  too - matching the behaviour of
  [`read_cleaning_log()`](read_cleaning_log.md) and
  [`read_other_responses()`](read_other_responses.md).

- ignore_case:

  Logical. If `TRUE` (the default), `file_pattern` is matched
  case-insensitively.

- verbose:

  Logical. If `TRUE` (the default), a summary is printed to the console:
  the column count per file, and, when the files disagree, the offending
  files with their missing and extra columns.

## Value

A dataframe, invisibly when `verbose = TRUE`, with one row per file and
the columns:

- `file`:

  File name (basename).

- `n_columns`:

  Number of columns, or `NA` if unreadable.

- `matches_reference`:

  `TRUE` when the file's column names match the reference set exactly
  (order ignored).

- `missing`:

  Reference columns absent from this file, comma separated.

- `extra`:

  Columns in this file that are not in the reference set, comma
  separated.

- `status`:

  `"ok"`, or the error message for an unreadable file.

- `path`:

  Full path to the file.

The reference column names are attached as the attribute
`"reference_columns"`.

## Details

Both [`read_cleaning_log()`](read_cleaning_log.md) and
[`read_other_responses()`](read_other_responses.md) stack the files they
find with `do.call(rbind, ...)`, which requires every file to have the
same columns in the same order. When one reviewer's workbook carries an
extra column - a renamed header, a leftover helper column, an older
template with three `EXISTING other` slots instead of one - the bind
fails with a "numbers of columns of arguments do not match" error that
names no file. This function answers the question that error does not:
*which* file is the odd one out, and *which* columns differ.

**What it reads:** only the header of each file, so it is fast even on
large logs. `.csv`/`.txt` files are read with
[`utils::read.csv()`](https://rdrr.io/r/utils/read.table.html); `.xlsx`,
`.xlsm` and `.xls` files with
[`readxl::read_excel()`](https://readxl.tidyverse.org/reference/read_excel.html).

**Reference column set:** the most common set of column names across the
readable files is taken as the reference. Each file is then compared
against it, and the `missing` and `extra` columns are listed per file.
When every file shares the same set the reference is simply that set.

**Sheet selection:** `sheet` is passed to
[`readxl::read_excel()`](https://readxl.tidyverse.org/reference/read_excel.html)
and accepts a name or an integer. Name the sheet rather than numbering
it - `sheet = "cleaning_log"` or `sheet = "other_responses"` - so the
check is unaffected by where the tab happens to sit in the workbook.
Pass a vector or list the same length as the files to use a different
sheet per file. Ignored for csv files.

**Unreadable files:** a file that cannot be opened (corrupt, locked by
Excel, missing the requested sheet) is reported with `n_columns = NA`
and the reason in `status`, rather than stopping the scan.

## Examples

``` r
if (FALSE) { # \dontrun{
# cleaning logs - same pattern and sheet as read_cleaning_log()
check_log_files(
  "output/follow_ups",
  file_pattern = "_follow-ups_edited\\.xls[xm]$",
  sheet = "cleaning_log"
)

# other responses - the same files, the other sheet
check_log_files(
  "output/follow_ups",
  file_pattern = "_follow-ups_edited\\.xls[xm]$",
  sheet = "other_responses"
)

# everything in a folder, whatever the format
check_log_files("output/follow_ups")
} # }
```
