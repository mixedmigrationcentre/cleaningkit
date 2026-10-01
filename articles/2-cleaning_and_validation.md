# 2. Data Cleaning and Validation

## Initialize the package and all required packages

``` r

rm(list = ls())
library(cleaningkit)

cleaningkit::load_packages()
```

## Setup project folders (run once)

This call also copies `logical_checklist.xlsx` into `resources/`. Use
`copy_templates = FALSE` to skip it, or
`templates = c("logical_checklist.xlsx" = "resources/my_checks.xlsx")`
to copy it under a different name. An existing file is never overwritten
unless `overwrite_templates = TRUE`.

**Customise:** `base_path` is the project root —
[`here::here()`](https://here.r-lib.org/reference/here.html) keeps it
portable. `extra_folders` adds any site-specific folders, e.g.
`c("output/archive")`.

``` r

setup_project_folders(
  base_path = here::here(),
  extra_folders = NULL # any site-specific extras
)
```

## Read tool data

Both functions read the same file:
[`read_tool_survey()`](../reference/read_tool_survey.md) the `survey`
sheet, [`read_tool_choices()`](../reference/read_tool_choices.md) the
`choices` sheet.

**Customise:** the path to your XLSForm.

``` r

tool_survey <- cleaningkit::read_tool_survey("./resources/tool.xlsx")
tool_choices <- cleaningkit::read_tool_choices("./resources/tool.xlsx")
```

## Create other response db

In case an “other” label has not been picked up, pass
`other_text_types = c("Q31_2")` and add the “other” question that was
missed.

**Customise:** `other_text_types` on
[`get_other_labels()`](../reference/get_other_labels.md) — add any
“other” text question the tool did not detect automatically. Nothing
else here is survey-specific.

``` r

other_labels <- cleaningkit::get_other_labels(
  tool_survey = tool_survey,
  other_text_types = c("Q31_2")
)

other_db <- cleaningkit::get_other_db(
  other_labels = other_labels,
  tool_choices = tool_choices,
  tool_survey = tool_survey
)
```

## Keep only the newly collected records

A filter can also be run on the raw dataset itself when several cleaning
log outputs are wanted from one export.

Data collection for a round usually runs over several weeks while
validation is run twice a week, and every ONA download contains the
whole dataset collected so far. Running the `validate_*` functions on
the full download regenerates cleaning log entries for surveys that were
already reviewed, so each follow-up workbook repeats the previous
round’s issues.

[`filter_new_records()`](../reference/filter_new_records.md) removes
that duplication. Drop the new ONA download into `./data` next to the
file the previous round left behind. The larger of the two files is
treated as the new export, every `_uuid` found in the smaller one is
removed, the two inputs are archived to `./data/archive/`, and the
remaining records are written to `./data/data.xlsx`.

**Customise:** `data_folder` and `output_name` if your exports do not
live at `./data/data.xlsx`; `uuid_column` if the id column is not
`_uuid`; `use_ledger = FALSE` to compare only against the previous file
instead of the running ledger; `archive = FALSE` to leave the inputs
where they are; `rename_single_file = FALSE` to keep the original file
name on the first round.

``` r

cleaningkit::filter_new_records(
  data_folder = "./data",
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  output_name = "data.xlsx",
  sheet = 1,
  use_ledger = TRUE,
  ledger_name = "processed_uuids.csv",
  archive = TRUE,
  archive_folder = "archive",
  rename_single_file = TRUE,
  verbose = TRUE
)
```

The ONA label row of the new export is written back as row one of the
output, so [`read_raw_data()`](../reference/read_raw_data.md) and every
`validate_*` function can keep their default `skip_label_row = TRUE`.

### Why a ledger is kept

Because `data.xlsx` is itself already filtered, comparing the two files
alone would only ever exclude the most recent round. From the third
round onwards the records collected in the first round would quietly
come back into the cleaning log. To prevent this, the function maintains
`./data/processed_uuids.csv`, a running list of every uuid that has
already been through validation, and filters against that ledger as well
as against the previous file. The csv is ignored when the function looks
for input files, so it can live in `./data` without interfering.

If the ledger is deleted or unreadable the function falls back to the
plain two-file comparison and warns. If only the new export is in the
folder, the ledger is used on its own:

``` r

# only the new ONA download is in ./data - filter against the ledger alone
cleaningkit::filter_new_records(data_folder = "./data")
```

### What the function will not do

Nothing is removed until the filtered file has been built successfully,
and nothing is removed at all if the filtering leaves zero new records —
which usually means the same export was downloaded twice. With
`archive = TRUE` (the default) the inputs are moved to `./data/archive/`
under a timestamped name rather than deleted, so a round can be redone
if something goes wrong. Set `archive = FALSE` to delete them outright.

More than two Excel files in `./data` is an error rather than a guess,
and Excel’s `~$` lock files are ignored. The call returns, invisibly, a
summary of how many records were read, dropped and kept.

### The first round needs no filtering

With a single export and no ledger there is nothing to compare against,
so [`filter_new_records()`](../reference/filter_new_records.md) renames
that file to `data.xlsx`, reports that the step was skipped, and
returns. It no longer errors, so the call can safely be left in the
script from round one onwards — there is no need to comment it out for
the first run, or when the whole dataset is being validated in one go.

## Read raw data

This is the file
[`filter_new_records()`](../reference/filter_new_records.md) left in
`./data` — the new records on a later round, the renamed export on the
first one.

**Customise:** `filename`, if your export lives somewhere else or you
changed `output_name` above.

``` r

raw_data <- cleaningkit::read_raw_data(
  filename = "./data/data.xlsx",
  tool_survey = tool_survey
)
```

## Prepare other responses

Add the other responses questions you want to be included in the output
in the `questions` argument,
e.g. `questions = c("Q34_1", "Q35_1", "Q37_1")`. The usual route now
hands the resulting dataframe to
[`create_review_workbook()`](../reference/create_review_workbook.md)
further down, so the “other” responses and the cleaning log land in one
workbook — there is no separate file any more.
[`save_other_responses()`](../reference/save_other_responses.md) is
still there for when the two logs go to different reviewers.

**Customise:** `questions` to restrict the output to specific “other”
questions (leave it out for all of them), and `extra_columns` for the
columns the reviewer should see next to each response,
e.g. `c("username", "Q13")`.

``` r

other_responses_df <- cleaningkit::prepare_other_responses(
  uuid_column = "_uuid",
  raw_data = raw_data,
  other_db = other_db,
  tool_choices = tool_choices,
  extra_columns = c("username")
)
```

## Validate duration

Flags surveys shorter than `lower_bound`. Surveys longer than
`upper_bound` are **not** flagged by default — a long interview is
normally legitimate and only inflates the cleaning log — so set
`flag_above_upper = TRUE` to log those too.

**Customise:** `lower_bound` and `upper_bound` in minutes, to match how
long your interview actually takes; `flag_above_upper`;
`column_to_check` if your duration column is not `_duration`.

``` r

duration_log <- cleaningkit::validate_duration(
  dataset = raw_data,
  column_to_check = "_duration",
  uuid_column = "_uuid",
  log_name = "duration_log",
  lower_bound = 15,
  upper_bound = 60,
  flag_above_upper = FALSE,
  skip_label_row = TRUE
)
```

## Validate completeness

`metadata_cols` holds the metadata columns ignored when counting
answers. It defaults to:

``` r

c("start", "end", "today", "deviceid", "username", "simserial", "phonenumber",
  "uuid", "_uuid", "id", "_id", "submission_time", "_submission_time",
  "index", "_index", "df_name")
```

Pass your own `metadata_cols` to change that list.

**Customise:** `min_content_cells` — roughly the number of questions a
complete interview answers, so set it from your own tool;
`metadata_cols` to change which columns are ignored in the count.

``` r

completeness_log <- cleaningkit::validate_completeness(
  dataset = raw_data,
  uuid_column = "_uuid",
  log_name = "completeness_log",
  min_content_cells = 100,
  skip_label_row = TRUE
)
```

## Validate refused

Flags any surveys that have more than 6 “Refused” by default.

**Customise:** `max_refused` for how many refusals a survey may contain,
and `refused_value` if your tool labels the option something other than
`"Refused"`.

``` r

refused_log <- cleaningkit::validate_refused(
  dataset = raw_data,
  uuid_column = "_uuid",
  log_name = "refused_log",
  max_refused = 6,
  refused_value = "Refused",
  skip_label_row = TRUE
)
```

## Validate back to back interviews

Flags any two interviews by the same enumerator that are less than 3
minutes apart, which is the default gap.

**Customise:** `threshold_hours` and `threshold_mins` for the smallest
acceptable gap between two interviews by the same enumerator;
`enumerator_column`, `start_column` and `end_column` for your tool’s
column names; `gap_from` for which timestamps the gap is measured
between.

``` r

back_to_back_log <- cleaningkit::validate_back_to_back(
  dataset = raw_data,
  uuid_column = "_uuid",
  enumerator_column = "username",
  start_column = "start",
  end_column = "end",
  log_name = "back_to_back_log",
  threshold_hours = 0,
  threshold_mins = 3,
  gap_from = c("end", "start"),
  skip_label_row = TRUE
)
```

## Validate country of interview

Flags if the respondent is being interviewed in their country of
nationality.

**Customise:** the three question codes — `country_interview_col`,
`nationality_col` and `journey_start_col`. These are 4Mi codes and will
be different in any other tool.

``` r

country_of_interview_log <- cleaningkit::validate_country_of_interview(
  dataset = raw_data,
  uuid_column = "_uuid",
  country_interview_col = "Q13",
  nationality_col = "Q31",
  journey_start_col = "Q41",
  log_name = "country_of_interview_log",
  skip_label_row = TRUE
)
```

## Validate time of interview

Flags the earliest and latest times of interview. By default earliest
hour is 5am and latest hour is 10pm.

**Customise:** `earliest_hour` and `latest_hour` for the hours
interviewing is plausible in your context; `time_column` for your
timestamp column; `flag_missing = TRUE` to also log surveys with no time
recorded.

``` r

interview_time_log <- cleaningkit::validate_interview_time(
  dataset = raw_data,
  uuid_column = "_uuid",
  time_column = "start",
  log_name = "interview_time_log",
  earliest_hour = 5,
  latest_hour = 22,
  flag_missing = FALSE,
  skip_label_row = TRUE
)
```

## Validate similar surveys

Groups data by enumerator and checks surveys which are similar.

**Customise:** `threshold` — the lower the number, the stricter the
check; `idnk_value` to match your tool’s “Don’t know” label;
`enumerator_column` for your column name; `return_all_results = TRUE`
for a row per survey rather than only the flagged ones.

``` r

similar_surveys_log <- raw_data %>%
  cleaningkit::validate_similar_surveys(
    tool_survey = tool_survey,
    enumerator_column = "username",
    idnk_value = "Don't know",
    sm_separator = "/",
    # flags a survey whose closest neighbour differs in at most this many columns
    threshold = 7,
    # TRUE returns a row for every survey, which is useful for per-enumerator
    # analysis rather than for the cleaning log
    return_all_results = FALSE
  )
```

## Validate similar questions

Groups data by enumerator and checks questions passed for similarity.

``` r

similar_questions_log <- raw_data %>%
  cleaningkit::validate_similar_questions(
    questions_to_check = c("Q161_1", "Q162_1", "Q152_1", "P2P18_1")
  )
```

## Validate outliers

Looks through all integer questions and checks for any outliers, or
checks only the columns you name. Set `columns_to_check = c("QN7_a")`
with your own integer question to check that question only.

**Customise:** `columns_to_check` to check named integer questions only
(drop it to scan them all); `strongness_factor` to loosen or tighten
what counts as an outlier; `min_unique_values` to skip near-constant
questions; `columns_to_skip` to exclude questions you do not want
checked.

``` r

outliers_log <- raw_data %>%
  cleaningkit::validate_outliers(
    # leave columns_to_check = NULL to check every numeric column
    columns_to_check = NULL,
    # tool_survey lets the function pick the numeric questions from the tool
    tool_survey = tool_survey,
    strongness_factor = 2,
    min_unique_values = 5,
    remove_sm_binary = TRUE, # skip the 0/1 select_multiple columns
    sm_separator = "/",
    columns_to_skip = NULL
  )
```

## Validate interview location

Checks the GPS point recorded during each in-person interview against
the country and the city the respondent claims the interview took place
in. Three separate flags can be raised: a missing or invalid GPS point,
a GPS point that falls outside the claimed country, and a GPS point
further than `city_radius_km` from the centre of the claimed city.

The country check uses country polygons from `rnaturalearthdata`. The
city check geocodes each unique city + country pair **once** through the
OpenStreetMap Nominatim API, so an internet connection is needed and the
check takes a little longer the first time it runs on a new dataset.
City names in the data should be spelled in English and reasonably match
OpenStreetMap (e.g. “Kampala”, “Addis Ababa”); any city that cannot be
geocoded is skipped with a warning.

**Customise:** `country_question` and `city_question` for your tool;
`city_radius_km` for how far from the claimed city still counts as
acceptable; `check_country`, `check_city` and `flag_missing_gps` to
switch individual checks off; `lat_column`, `lon_column` and
`location_column` if your GPS columns are named differently.

``` r

interview_location_log <- cleaningkit::validate_interview_location(
  dataset = raw_data,
  uuid_column = "_uuid",
  lat_column = "_location_latitude",
  lon_column = "_location_longitude",
  # raw ONA geopoint column ("lat lon altitude precision"), used when the split
  # lat/lon pair is missing or invalid
  location_column = "location",
  country_question = "Q13",
  city_question = "Q14",
  log_name = "interview_location_log",
  city_radius_km = 75,
  check_country = TRUE,
  check_city = TRUE,
  flag_missing_gps = TRUE,
  nominatim_delay_s = 1,
  skip_label_row = TRUE
)
```

Either check can be switched off, which is useful when there is no
internet connection or when only one of the two is relevant:

``` r

# country check only - no internet needed
interview_location_log <- cleaningkit::validate_interview_location(
  dataset = raw_data,
  check_city = FALSE
)
```

## Validate logical

Logical checks are the consistency rules of the 4Mi questionnaire - the
“this answer cannot go together with that answer” rules. Rather than
being written in R, they are maintained in an Excel checklist so that
research staff can add, edit or retire a check without touching the
code.
[`validate_logical_with_list()`](../reference/validate_logical_with_list.md)
reads that checklist and runs every row of it against the dataset.

**Customise:** nothing in the call itself — the checks are what you
edit, and they live in `./resources/logical_checklist.xlsx`, one row per
check. Change the path below only if you renamed the checklist, and the
four `*_column` arguments only if you renamed its columns.

### The checklist file

Each row of the checklist is one check. Four columns are used by the
function (a fifth, `module`, is optional and only helps organise the
sheet):

| Column | What it holds |
|----|----|
| `check_id` | A unique id for the check, e.g. `check_01`. Must be unique - duplicates raise an error. It is written into the log and into `check_binding`. |
| `description` | A plain-language explanation of what is wrong. This is what the reviewer reads in the cleaning log. |
| `check_to_perform` | An R expression, written as text, that is `TRUE` for the records that should be flagged, e.g. `Q13 == Q31`. |
| `columns_to_clean` | A comma-separated list of the columns the reviewer should look at, e.g. `Q13, Q31`. One log row is produced per flagged record **per column**. Leave blank if there is no specific column to clean. |

Some worked examples of `check_to_perform`:

``` r

# a straightforward comparison of two questions
Q13 == Q31

# either of two conditions
(Q92 == Q31) | (Q92 == Q41)

# a select_multiple: use str_detect() with fixed() on the concatenated string
str_detect(Q78, fixed("Natural disaster or environmental factors")) & Q86_a == "No"
```

The expression is evaluated inside
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html),
so any `dplyr` or `stringr` verb can be used and column names are
written bare (no quotes, no `df$`). Because a select_multiple question
is exported as one space-separated string, always test it with
`str_detect(..., fixed("choice label"))` rather than `==`.

### Where to find the checklist template

A ready-made checklist with the standard MMC core checks ships with the
package, and
[`setup_project_folders()`](../reference/setup_project_folders.md) has
already copied it to `./resources/logical_checklist.xlsx` — edit it
there. To fetch it again, or to copy it under a different name:

``` r

# where the template lives
template_path <- system.file(
  "extdata",
  "logical_checklist.xlsx",
  package = "cleaningkit"
)

# copy it into the project so it can be edited
file.copy(template_path, "./resources/logical_checks_mmc.xlsx")
```

It can also be browsed on GitHub under
[`inst/extdata/logical_checklist.xlsx`](https://github.com/mixedmigrationcentre/cleaningkit/blob/main/inst/extdata/logical_checklist.xlsx).

### Running the checks

``` r

logical_list <- openxlsx::read.xlsx(
  "./resources/logical_checklist.xlsx",
  sheet = 1
)

logical_check_log <- raw_data %>%
  cleaningkit::validate_logical_with_list(
    list_of_check = logical_list,
    check_id_column = "check_id",
    check_to_perform_column = "check_to_perform",
    columns_to_clean_column = "columns_to_clean",
    description_column = "description"
  )
```

By default every check is stacked into a single `logical_log`. Setting
`bind_checks = FALSE` stores each check in its own log named after its
`check_id`, which is handy when one check needs to be inspected on its
own:

``` r

logical_check_log <- raw_data %>%
  cleaningkit::validate_logical_with_list(
    list_of_check = logical_list,
    check_id_column = "check_id",
    check_to_perform_column = "check_to_perform",
    columns_to_clean_column = "columns_to_clean",
    description_column = "description",
    bind_checks = FALSE
  )

# inspect one check on its own
logical_check_log$check_01
```

A logical flag column is also added to `checked_dataset` for every check
(named after the `check_id`, `TRUE` = flagged), so the number of records
each check caught can be reviewed before the log is exported:

``` r

table(logical_check_log$checked_dataset$check_01)
```

If a check is written badly the function stops and prints both the
`check_id` and the offending expression, so the row in the Excel sheet
can be corrected and the checklist re-read.

## Combine logs

**Customise:** the list below — drop any log you did not run, and add
any you did. The names must match the objects created above.

``` r

list_of_log_all <- c(
  duration_log,
  completeness_log,
  refused_log,
  back_to_back_log,
  country_of_interview_log,
  interview_time_log,
  interview_location_log,
  similar_surveys_log,
  similar_questions_log,
  outliers_log,
  logical_check_log
)

combined_log <- cleaningkit::create_combined_log(
  list_of_log = list_of_log_all,
  dataset_name = "checked_dataset"
)
```

## Create the review workbook

[`create_review_workbook()`](../reference/create_review_workbook.md) is
the usual route: it writes the cleaning log and the “other” text
responses into a **single** file, so a reviewer opens one workbook and
the second stage reads one file.

The tabs appear in the order a reviewer works through them — the raw
data first, then the log, then the other responses:

| Sheet | What it is |
|----|----|
| `dataset` | The checked dataset, with the check-flag columns in front. |
| `cleaning_log` | One row per flagged value. The reviewer fills in **Action taken** and **New value**. |
| `other_responses` | Every “other” text response to review. |
| `readme` | What each sheet is for, and the **Action taken** codes. |
| `Dropdown_values` | Backs the other-responses drop-downs. |
| `validation_rules` | Hidden. Backs the **Action taken** drop-down. |
| `_ck_config` | Very hidden, `.xlsm` only. The macro’s configuration. |

`vba = FALSE` (the default) writes a plain `.xlsx`. `vba = TRUE` writes
a macro-enabled `.xlsm`, where an edit made on the `dataset` sheet is
appended to the bottom of the `cleaning_log` sheet automatically — give
the path an `.xlsm` extension — an `.xlsx` one still works, and is
corrected to `.xlsm` with a message. Leave out `other_responses` and
`other_db` and the output is exactly what
[`create_cleaning_log()`](../reference/create_cleaning_log.md) produces.

`flag_columns` puts the check flags at the front of the `dataset` sheet
so a reviewer can filter on them, and `group_by = "issue"` sets the
column the log is sorted and coloured by.

**Customise:** `vba` for the file type, `color_mode` and `color_columns`
for the highlighting, `group_by` for how the log is sorted,
`output_path` for the file name, and `other_enumerator_id` for the
enumerator column on the other-responses sheet. Drop `other_responses`
and `other_db` to produce the cleaning log on its own.

``` r

cleaningkit::create_review_workbook(
  write_list = combined_log,
  other_responses = other_responses_df,
  other_db = other_db,
  other_enumerator_id = "username",
  vba = TRUE,
  color_mode = "partial",
  color_columns = c("old_value"),
  group_by = "issue",
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsx"
  )
)
```

The `dataset` sheet leads with the check-flag columns, so a reviewer can
filter on them and decide keep-or-delete against the raw data. Editing
one of those flag columns never appends a row to the cleaning log.
`include_dataset` is forced to `TRUE` when `vba = TRUE`, since without
that sheet there is nothing for the macro to watch.

## Create cleaning log

[`create_cleaning_log()`](../reference/create_cleaning_log.md) is the
cleaning-log-only writer, unchanged and still available when the two
logs go to different people. It turns the combined log into the
reviewer-facing Excel workbook: the checked dataset on the first tab,
the log itself on the second, a `readme` sheet listing the action codes,
and a drop-down on the **Action taken** column.

``` r

cleaningkit::create_cleaning_log(
  write_list = combined_log,
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsx"
  )
)
```

### Controlling the row colours

The log is colour-coded so that a reviewer can see which flagged
questions belong together. The colouring is driven by
`column_for_color`, which defaults to `check_binding`: all the rows
produced by one check for one record share a `check_binding`, and
therefore share a light MMC shade. The shades are generated from the MMC
palette, so a log with many bindings still stays in range of the brand
colours.

How much of each row is filled is controlled by `color_mode`:

| `color_mode` | What it does |
|----|----|
| `"on"` | The whole row is filled, one shade per `check_binding`. |
| `"partial"` | **Default**, with `color_columns = c("old_value")`. Only the columns listed in `color_columns` are filled; every other cell keeps the plain body style. |
| `"off"` | No fills at all. |

`color_mode` never touches the header. In all three modes the header row
keeps the MMC blue fill, the white bold Arial Narrow text, the borders,
the column filter and the frozen first row and column, and the body
keeps its borders and fonts — only the row fills change.

#### Colours on the whole row

Pass `color_mode = "on"` to fill every cell of the row instead of only
the columns named in `color_columns`.

``` r

cleaningkit::create_cleaning_log(
  write_list = combined_log,
  color_mode = "on",
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsx"
  )
)
```

#### Colours on selected columns only (the default)

This is what you get without passing anything. `color_mode = "partial"`
is shown here together with the column or columns that should carry the
colour. This is useful when the colour is only needed as a pointer to
the value under review, and a fully coloured row makes the sheet harder
to read or to print.

``` r

# colour only the "Old value" column
cleaningkit::create_cleaning_log(
  write_list = combined_log,
  color_mode = "partial",
  color_columns = "old_value",
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsx"
  )
)

# colour several columns
cleaningkit::create_cleaning_log(
  write_list = combined_log,
  color_mode = "partial",
  color_columns = c("old_value", "issue", "question"),
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsx"
  )
)
```

Column names can be written either the way they appear in the log header
or the way they appear in the raw log, because matching ignores case,
spaces, underscores and punctuation. Column positions
(e.g. `color_columns = c(8, 9)`) are accepted too. These are the columns
of the log and the names that resolve to each one:

| Log header        | Also accepted as              |
|-------------------|-------------------------------|
| `Date`            | `date`                        |
| `Survey UUID`     | `uuid`, `survey_uuid`         |
| `Enumerator`      | `enumerator`                  |
| `Question number` | `question`, `question_number` |
| `Question text`   | `question_text`               |
| `Issue`           | `issue`                       |
| `Old value`       | `old_value`                   |
| `Action taken`    | `action`, `action_taken`      |
| `New value`       | `new_value`                   |
| `Identified by`   | `identified_by`               |
| `Comments`        | `comments`                    |
| `PO feedback`     | `po_feedback`                 |

If `color_mode = "partial"` is used without any valid `color_columns`,
the workbook is still written but with no colouring, and a warning names
the columns that could not be found.

#### Colours off

``` r

cleaningkit::create_cleaning_log(
  write_list = combined_log,
  color_mode = "off",
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsx"
  )
)
```

`TRUE` and `FALSE` work as shorthand for `"on"` and `"off"`:

``` r

cleaningkit::create_cleaning_log(
  write_list = combined_log,
  color_mode = FALSE,
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsx"
  )
)
```

Setting `column_for_color = NULL` also switches the colouring off, since
there is then no column left to group the rows by.

#### Colouring by something other than `check_binding`

`column_for_color` can point at any column of the log, which is
occasionally useful for review workflows that are organised differently
— for example one shade per interview rather than one shade per check:

``` r

cleaningkit::create_cleaning_log(
  write_list = combined_log,
  column_for_color = "Survey UUID",
  color_mode = "partial",
  color_columns = "old_value",
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsx"
  )
)
```

## Create a cleaning log that records edits (macro-enabled)

[`create_cleaning_log_vba()`](../reference/create_cleaning_log_vba.md)
writes the same workbook as
[`create_cleaning_log()`](../reference/create_cleaning_log.md), as a
macro-enabled `.xlsm` with a small VBA project attached. A reviewer can
then change a value directly on the `dataset` sheet, and the edit is
appended to the bottom of the cleaning log automatically. The point is
that a correction never has to be copied across by hand: the reviewer
stays in one workbook.

``` r

cleaningkit::create_cleaning_log_vba(
  write_list = combined_log,
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsm"
  )
)
```

The two functions are deliberately kept apart.
[`create_cleaning_log()`](../reference/create_cleaning_log.md) carries
none of the macro machinery and does not know this one exists, so if the
macro route is unavailable on a given machine - the binary is missing,
macros are blocked, Excel behaves unexpectedly - the plain `.xlsx` log
is completely unaffected.

Every argument of
[`create_cleaning_log()`](../reference/create_cleaning_log.md) works
here too (`color_mode`, `color_columns`, `column_for_color`, `group_by`,
`flag_columns`, `skip_label_row`, the fonts, and so on), with one
exception: `include_dataset` is forced to `TRUE`, because without the
`dataset` sheet there is nothing for the macro to watch. An `.xlsx`
extension is corrected to `.xlsm` with a message.

### What an edit produces

Changing a cell on the `dataset` sheet appends one row to the cleaning
log, filled in from the row and column the edit happened in:

| Column | Where it comes from |
|----|----|
| **Survey UUID** | the uuid column of the edited row |
| **Date**, **Enumerator** | the date and enumerator columns of that row |
| **Question number** | the column name, from row 1 of the `dataset` sheet |
| **Question text** | the ONA label, from row 2 |
| **Old value** | the value immediately before the edit |
| **New value** | what the reviewer typed |
| **Action taken** | `addition` if the cell was empty, `delete_data_point` if it is cleared, `recoded` otherwise |
| **Identified by** | the Excel user name |
| **Issue** | `manual_edit_001`, `manual_edit_002`, … (see below) |

Appended rows have their formatting cleared before they are written, so
none of the `check_binding` row colours carry down onto them, and they
are given the same **Action taken** drop-down as the rest of the log.
The header and label rows and the uuid column are put back if a reviewer
edits them, because the log refers to them.

### Repeat edits are appended, not overwritten

Editing the same cell a second time adds **another** row rather than
revising the first, so the log keeps the full history of what was done.
Each row’s **Old value** is the value immediately before that particular
edit, so successive rows chain raw -\> A -\> B.

The **Issue** column carries a per-cell sequence number for this reason.
The deduplication key in
[`read_cleaning_log()`](../reference/read_cleaning_log.md) is
`uuid + question + issue`, and for rows sharing an action it keeps the
*first* occurrence - so without a distinct issue per edit, a second edit
of the same cell would be silently dropped and the reviewer’s final
value lost. `manual_edit_001`, `manual_edit_002` and so on keep the key
unique and sort in edit order, so every row survives and
[`apply_cleaning_log()`](../reference/apply_cleaning_log.md) writes the
most recent value.

Use `macro_issue_prefix` to change the prefix if `manual_edit` clashes
with an issue name one of your checks already produces.

``` r

cleaningkit::create_cleaning_log_vba(
  write_list = combined_log,
  macro_issue_prefix = "reviewer_edit",
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsm"
  )
)
```

### One-time setup: building the VBA project

The compiled VBA project is not generated by R. `vbaProject.bin` is an
OLE compound file holding compressed VBA source plus a p-code cache, so
it is built once in Excel from the sources in `inst/vba/` and shipped as
`inst/extdata/cleaningkit_vba.bin`. On Windows with Excel installed:

``` r

# installs the COM toolchain (the MMC fork of RDCOMClient)
cleaningkit::load_packages(vba = TRUE)

source("dev/build_vba_bin.R")
build_vba_bin()
```

This needs **Excel \> File \> Options \> Trust Center \> Trust Center
Settings \> Macro Settings \> “Trust access to the VBA project object
model”** ticked, which is off by default. If it is locked down
centrally, `inst/vba/README.md` has a manual procedure that takes about
five minutes and produces an identical file.

Rebuild only when the VBA sources change; the binary is otherwise static
and serves every log the package produces.

### Finding the compiled project

[`create_cleaning_log_vba()`](../reference/create_cleaning_log_vba.md)
looks for the binary in this order: the `cleaningkit.vba_project`
option, the `CLEANINGKIT_VBA_PROJECT` environment variable, the
installed package, then `inst/extdata/`, `resources/`, `functions/`,
`dev/` and the working directory. If none of them has it, the function
stops with a message listing every path it tried.

The last few matter when the functions are sourced into an analysis
project rather than used from the installed package - and note that
[`system.file()`](https://rdrr.io/r/base/system.file.html) also comes up
empty when the package *is* installed but was installed before the
binary was built. Either point at it directly:

``` r

cleaningkit::create_cleaning_log_vba(
  write_list = combined_log,
  vba_project = "resources/cleaningkit_vba.bin",
  output_path = paste0(
    "output/follow_ups/",
    Sys.Date(),
    "_follow-ups.xlsm"
  )
)
```

or set it once in a setup script:

``` r

options(
  cleaningkit.vba_project = "C:/path/to/cleaningkit/inst/extdata/cleaningkit_vba.bin"
)
```

### Before you roll it out

Check that macros actually run for your reviewers, on a real file, the
way they normally receive it. Office blocks macros by default in files
carrying the Mark of the Web, and the current banner is a red **SECURITY
RISK** bar with no *Enable content* button:

- opened from SharePoint through *Open in Desktop App*, or reached
  through the OneDrive sync client - no Mark of the Web, macros run;
- downloaded through a browser, or received by email - blocked.

If they are blocked, the fixes are central rather than per-file: a
Trusted Location, adding the SharePoint/OneDrive domains to the Trusted
Sites zone by policy, or signing the VBA project. `inst/vba/README.md`
covers this, along with the smoke test to run after every rebuild.

Reading the result back works exactly as for an `.xlsx` - `readxl`
handles `.xlsm` the same way - but remember to widen `file_pattern` when
scanning a directory with
[`read_cleaning_log()`](../reference/read_cleaning_log.md), since the
default only matches `_follow-ups_edited.xlsx` and
`_follow-ups_edited.xlsm`.
