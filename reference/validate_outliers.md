# Validate Outliers in Integer and Numeric Columns

Detects statistical outliers across all integer/numeric columns in the
dataset (or a user-specified subset), using two complementary methods:

1.  **Normal distribution** — flags any value more than
    `strongness_factor` standard deviations from the column mean.

2.  **Log distribution** — applies `log(x + 1)` first, then applies the
    same z-score test. This catches outliers in right-skewed variables
    (e.g. income, journey duration, number of children) that would be
    missed by the normal check.

A record is flagged once per method per column. Both flags for the same
record share a `check_binding` so they are coloured as one group in the
review workbook.

## Usage

``` r
validate_outliers(
  dataset,
  uuid_column = "_uuid",
  log_name = "outlier_log",
  columns_to_check = NULL,
  tool_survey = NULL,
  strongness_factor = 2,
  min_unique_values = 5,
  remove_sm_binary = TRUE,
  sm_separator = "/",
  columns_to_skip = NULL,
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- uuid_column:

  Name of the uuid column. Default `"_uuid"`.

- log_name:

  Name of the log element in the returned list. Default `"outlier_log"`.

- columns_to_check:

  Optional character vector of specific column names to check. When
  supplied, only these columns are checked and `tool_survey`
  auto-detection is ignored. Default `NULL` (auto-detect).

- tool_survey:

  Optional XLSForm survey sheet dataframe. When provided, integer-type
  columns are identified from it rather than by R class alone, which is
  more reliable when the dataset was read as all-character (e.g. via
  `readxl::read_excel(..., col_types = "text")`). Must contain `name`
  and `type` columns. Default `NULL`.

- strongness_factor:

  Numeric. Number of standard deviations from the mean beyond which a
  value is considered an outlier. Higher = stricter. Default `3`.

- min_unique_values:

  Integer. Columns with fewer distinct non-missing values than this
  threshold are skipped (avoids false positives on binary or small
  ordinal scales). Default `5`.

- remove_sm_binary:

  Logical. If `TRUE` (the default), select-multiple binary sub-columns
  (detected by `sm_separator`) are excluded from checking — they only
  ever contain 0/1 and are not meaningful for outlier detection.

- sm_separator:

  Separator between a select-multiple parent column name and its binary
  sub-columns. Default `"/"` (ONA export style).

- columns_to_skip:

  Optional character vector of column names to always exclude, even when
  auto-detecting. Useful for computed or metadata columns that happen to
  be numeric. Default `NULL`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  removed before validation. ONA exports include a label/description row
  immediately after the header that must not be treated as survey data
  (it would otherwise corrupt the mean and SD).

## Value

A list containing:

- checked_dataset:

  The original dataset, unchanged.

- \<log_name\>:

  A dataframe with columns `uuid`, `old_value`, `question`, `issue`, and
  `check_binding`. One row per (record × column × method) flagged.
  `issue` is either `"outlier (normal distribution)"` or
  `"outlier (log distribution)"`.

## Details

**Column selection** (in order of priority):

1.  If `columns_to_check` is supplied, only those columns are tested.

2.  If `tool_survey` is supplied, the `integer`-type columns found there
    (excluding common metadata columns) are used.

3.  Otherwise all columns that are `integer` or `numeric` after
    [`type.convert()`](https://rdrr.io/r/utils/type.convert.html) are
    used.

**Columns automatically excluded:**

- The uuid column.

- Select-multiple binary sub-columns (detected by `sm_separator`).

- Any column in `columns_to_skip`.

- Columns starting with `"_"` or `"X"` (ONA system columns).

- Columns with fewer than `min_unique_values` distinct non-missing
  values (avoids flagging binary or ordinal scales).
