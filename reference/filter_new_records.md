# Keep Only Newly Collected Records Before a Validation Round

Prepares the `data/` folder for a fresh validation round by reducing a
cumulative ONA export down to the records that have not been validated
yet. Data collection for a 4Mi round typically runs over several weeks
while validation runs twice a week, and every ONA download contains the
whole dataset collected so far. Running the `validate_*` functions on
the full download regenerates cleaning log entries for surveys that were
already reviewed in earlier rounds. This function removes that
duplication so each follow-up workbook only contains genuinely new
issues.

## Usage

``` r
filter_new_records(
  data_folder = "./data",
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  output_name = "data.xlsx",
  sheet = 1,
  use_ledger = TRUE,
  ledger_name = "processed_uuids.csv",
  archive = TRUE,
  archive_folder = "archive",
  verbose = TRUE
)
```

## Arguments

- data_folder:

  Path to the folder holding the raw exports. Default `"./data"`, the
  folder created by
  [`setup_project_folders()`](setup_project_folders.md).

- uuid_column:

  Name of the unique survey identifier column. Default `"_uuid"`, the
  standard ONA export column.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of each file is
  treated as the ONA label/description row rather than a survey. It is
  excluded from the record counts and from the uuid comparison, and the
  label row of the new export is written back as row one of the output.

- output_name:

  Name of the filtered file written to `data_folder`. Default
  `"data.xlsx"`, the file name used by the example pipeline.

- sheet:

  Sheet number or name to read from each Excel file. Default `1`.

- use_ledger:

  Logical. If `TRUE` (the default), previously processed uuids are also
  read from, and written back to, the ledger csv. Set to `FALSE` for a
  plain comparison of the two files in the folder.

- ledger_name:

  File name of the processed-uuid ledger inside `data_folder`. Default
  `"processed_uuids.csv"`.

- archive:

  Logical. If `TRUE` (the default), the input files are copied into
  `archive_folder` with a timestamp prefix before being removed from
  `data_folder`. If `FALSE` they are deleted outright.

- archive_folder:

  Name of the archive sub-folder inside `data_folder`. Default
  `"archive"`. Created if it does not exist.

- verbose:

  Logical. If `TRUE` (the default), progress messages are printed
  showing how many records were read, dropped and kept.

## Value

Invisibly, a list with:

- `data`:

  The filtered dataset as written, label row included.

- `output_path`:

  Path of the written file.

- `new_export`:

  File name treated as the new ONA export.

- `previous_file`:

  File name treated as the previous round, or `NA` if the ledger alone
  was used.

- `n_new_export`:

  Records in the new export, label row excluded.

- `n_previous`:

  Records in the previous file, label row excluded.

- `n_dropped`:

  Records removed as already validated.

- `n_kept`:

  Records written to the output.

- `archived_files`:

  Paths of the archived copies, empty when `archive = FALSE`.

- `ledger_path`:

  Path of the ledger, or `NA` when `use_ledger = FALSE`.

## Details

The function expects the `data/` folder to hold the freshly downloaded
ONA export plus the file left behind by the previous round (at most two
Excel files). The file with more records is treated as the new export,
the other as the previous round. Every uuid found in the previous file -
and in the processed-uuid ledger, see below - is removed from the new
export, and the remaining records are written to `data.xlsx`. The two
input files are then archived (or deleted).

**The ledger.** Because the file left behind is itself already filtered,
comparing two files alone would only ever exclude the most recent round.
From the third round onwards records from round one would silently
return. To prevent this, the function maintains `processed_uuids.csv` in
the same folder, listing every uuid that has already been through
validation. Each run filters against the ledger *and* the previous file,
then appends whatever it processed. The csv is ignored when the function
looks for input files, so it can live in `data/` without interfering. If
the ledger is deleted or unreadable the function falls back to the plain
two-file comparison and says so.

**Safety.** Nothing is removed until the filtered output has been built
successfully, and nothing is removed at all if the filtering leaves zero
new records - that usually means the same export was downloaded twice.
With `archive = TRUE` (the default) the inputs are moved to
`data/archive/` under a timestamped name rather than deleted, so a round
can be redone if something goes wrong.

The ONA label/description row of the new export is preserved as row one
of the output, so [`read_raw_data()`](read_raw_data.md) and the
`validate_*` functions can keep their default `skip_label_row = TRUE`.

## Examples

``` r
if (FALSE) { # \dontrun{
# Drop the new ONA download next to the previous round's file in ./data,
# then reduce it to the records collected since the last validation round
filter_new_records(
  data_folder = "./data",
  uuid_column = "_uuid",
  skip_label_row = TRUE
)

# ./data now holds data.xlsx (new records only), processed_uuids.csv
# and archive/ with the two inputs
raw_data <- read_raw_data(
  filename = "./data/data.xlsx",
  tool_survey = tool_survey
)
} # }
```
