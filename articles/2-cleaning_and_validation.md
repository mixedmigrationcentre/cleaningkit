# 2. Data Cleaning and Validation

## Initialize the package and all required packages

``` r

rm(list = ls())
library(cleaningkit)

cleaningkit::load_packages()
```

## Setup project folders (run once)

``` r

setup_project_folders(
  base_path = here::here(),
  extra_folders = NULL # any site-specific extras
)
```

## Read tool data

``` r

tool_survey <- cleaningkit::read_tool_survey("./resources/tool.xlsx")
tool_choices <- cleaningkit::read_tool_choices("./resources/tool.xlsx")
```

## Create other response db

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

## Read raw data

``` r

raw_data <- cleaningkit::read_raw_data(
  filename = "./data/data.xlsx",
  tool_survey = tool_survey
)
```

## Filter read raw data

Perform a filter on the raw dataset for multiple cleaning logs outputs.

## Prepare and save other responses

Add the other responses questions you want to be included in the output
in the question argument.

``` r

df <- cleaningkit::prepare_other_responses(
  uuid_column = "_uuid",
  raw_data = raw_data,
  other_db = other_db,
  tool_choices = tool_choices,
  extra_columns = c("username"),
  questions = c(
    "Q34_1",
    "Q35_1",
    "Q37_1",
    "Q38_1",
    "Q39_1",
    "Q41_1",
    "Q33_1"
  )
)

cleaningkit::save_other_responses(
  df = df,
  other_db = other_db,
  save_location = "./output/other_responses/",
  enumerator_id = "username"
)
```

## Validate duration

Flags anything below 15 mins and above 60 mins.

``` r

duration_log <- cleaningkit::validate_duration(
  dataset = raw_data,
  column_to_check = "_duration",
  uuid_column = "_uuid",
  log_name = "duration_log",
  lower_bound = 15,
  upper_bound = 60,
  skip_label_row = TRUE
)
```

## Validate completeness

`metadata_cols = c("start","end","today","deviceid","username","phonenumber","_uuid")`
has a list of all metadata columns that will be ingored during this
check.

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

Flags any interviews from the same enumerator if they are 10 mins apart
by default.

``` r

back_to_back_log <- cleaningkit::validate_back_to_back(
  dataset = raw_data,
  uuid_column = "_uuid",
  enumerator_column = "username",
  start_column = "start",
  end_column = "end",
  log_name = "back_to_back_log",
  threshold_hours = 0,
  threshold_mins = 10,
  gap_from = c("end", "start"),
  skip_label_row = TRUE
)
```

## Validate country of interview

Flags if the respondent is being interviewed in their country of
nationality.

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

## Validate duplicate surveys

Groups data by enumerator and checks surveys which are similar.

``` r

duplicate_log <- raw_data %>%
  cleaningkit::validate_duplicates(
    tool_survey = tool_survey,
    idnk_value = "Don't know",
    threshold = 30
  )
```

## Validate duplicate questions

Groups data by enumerator and checks questions passed for similarity.

``` r

duplicate_questions_log <- raw_data %>%
  cleaningkit::validate_duplicate_questions(
    questions_to_check = c("Q161_1", "Q162_1", "Q152_1", "P2P18_1")
  )
```

## Validate outliers

Outliers in all integer columns in the dataset or particular columns

``` r

outliers_log <- raw_data %>%
  cleaningkit::validate_outliers(
    columns_to_check = c("Q141_3"),
    strongness_factor = 3,
    min_unique_values = 5
  )
```

## Validate spatial distance

Spatial distance between two interviews per enumerator or for the entire
dataset

``` r

spatial_proximity_log <- raw_data %>%
  cleaningkit::validate_spatial_proximity(
    lat_column = "_location_latitude",
    lon_column = "_location_longitude",
    uuid_column = "_uuid",
    enumerator_column = "username",
    log_name = "spatial_proximity_log",
    distance_threshold_m = 50
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

``` r

interview_location_log <- cleaningkit::validate_interview_location(
  dataset = raw_data,
  uuid_column = "_uuid",
  lat_column = "_location_latitude",
  lon_column = "_location_longitude",
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
package. Copy it into the project’s `resources/` folder and edit it
there:

``` r

# where the template lives
template_path <- system.file(
  "extdata",
  "logical_checklist_example.xlsx",
  package = "cleaningkit"
)

# copy it into the project so it can be edited
file.copy(template_path, "./resources/logical_checks_mmc.xlsx")
```

It can also be browsed on GitHub under
[`inst/extdata/logical_checklist_example.xlsx`](https://github.com/mixedmigrationcentre/cleaningkit/blob/main/inst/extdata/logical_checklist_example.xlsx).

### Running the checks

``` r

logical_list <- openxlsx::read.xlsx(
  "./resources/logical_checks_mmc.xlsx",
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

``` r

list_of_log_all <- c(
  duration_log,
  completeness_log,
  refused_log,
  back_to_back_log,
  country_of_interview_log,
  interview_time_log,
  interview_location_log,
  logical_check_log,
  duplicate_log,
  duplicate_questions_log
)

combined_log <- cleaningkit::create_combined_log(
  list_of_log = list_of_log_all,
  dataset_name = "checked_dataset"
)
```

## Create cleaning log

[`create_cleaning_log()`](../reference/create_cleaning_log.md) turns the
combined log into the reviewer-facing Excel workbook: the log itself on
the first sheet, the checked dataset on a `dataset` sheet, a `readme`
sheet listing the action codes, and a drop-down on the **Action taken**
column.

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
| `"on"` | **Default.** The whole row is filled, one shade per `check_binding`. |
| `"partial"` | Only the columns listed in `color_columns` are filled; every other cell keeps the plain body style. |
| `"off"` | No fills at all. |

`color_mode` never touches the header. In all three modes the header row
keeps the MMC blue fill, the white bold Arial Narrow text, the borders,
the column filter and the frozen first row and column, and the body
keeps its borders and fonts — only the row fills change.

#### Colours on (the default)

Nothing needs to be passed; `color_mode = "on"` is shown here only to
make the option explicit.

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

#### Colours on selected columns only

Pass `color_mode = "partial"` together with the column or columns that
should carry the colour. This is useful when the colour is only needed
as a pointer to the value under review, and a fully coloured row makes
the sheet harder to read or to print.

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

| Log header                 | Also accepted as              |
|----------------------------|-------------------------------|
| `Date`                     | `date`                        |
| `Survey UUID`              | `uuid`, `survey_uuid`         |
| `Survey Registration Date` | `survey_registration_date`    |
| `Enumerator`               | `enumerator`                  |
| `Section`                  | `section`                     |
| `Question number`          | `question`, `question_number` |
| `Question text`            | `question_text`               |
| `Issue`                    | `issue`                       |
| `Old value`                | `old_value`                   |
| `Action taken`             | `action`, `action_taken`      |
| `New value`                | `new_value`                   |
| `Identified by`            | `identified_by`               |
| `Comments`                 | `comments`                    |
| `PO feedback`              | `po_feedback`                 |

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
