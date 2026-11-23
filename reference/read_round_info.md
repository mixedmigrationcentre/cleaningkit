# Read what earlier rounds checked

Reads the round memory from one or more files and combines it. Accepted:

- a review or final workbook made with `round_info`, edited or not:
  everything (survey IDs, fingerprints, questionnaire, settings);

- the `processed_uuids.csv` ledger of
  [`filter_new_records()`](filter_new_records.md): survey IDs;

- an earlier export or `data.xlsx` (any workbook whose first sheet has
  the survey ID column): survey IDs.

Every survey ID from every file counts as checked, so uploading more
files than needed is always safe. The newest workbook (by the date its
round was checked) supplies the round details, questionnaire and
settings.

## Usage

``` r
read_round_info(
  paths,
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  names = basename(paths)
)
```

## Arguments

- paths:

  Paths to the files.

- uuid_column:

  Survey ID column of an earlier export. Default `"_uuid"`.

- skip_label_row:

  Whether an earlier export has the ONA label row. Default `TRUE`.

- names:

  Display names for the files, e.g. the names of uploaded files whose
  `paths` are temporary. Default `basename(paths)`.

## Value

A `ck_round_info`. Its `sources` element lists each file with what was
found in it.
