# Creates formatted workbook with openxlsx

Creates formatted workbook with openxlsx

## Usage

``` r
create_formated_wb(
  write_list,
  column_for_color = NULL,
  color_mode = "on",
  color_columns = NULL,
  color_palette = c("#003D58", "#00A2A5", "#AFDFE4", "#D5EEF0", "#FFE07C", "#B88AAB",
    "#BBD876", "#FBBC75", "#F8AB9E", "#5B9E62", "#009BD9", "#F15B5B", "#63193B"),
  header_front_size = 12,
  header_front_color = "#FFFFFF",
  header_fill_color = "#00A2A5",
  header_front = "Arial Narrow",
  body_front = "Arial Narrow",
  body_front_size = 11
)
```

## Arguments

- write_list:

  List of dataframe (one worksheet per element).

- column_for_color:

  Column name used to colourise rows. Rows sharing the same value get
  the same fill. Sheets that do not contain this column are left
  un-coloured. Default `NULL`.

- color_mode:

  Controls how much of each row is filled. One of:

  `"on"`

  :   (default) the whole row is filled, i.e. the original behaviour.

  `"partial"`

  :   only the columns named in `color_columns` are filled; every other
      cell keeps the plain body style.

  `"off"`

  :   no row fills at all.

  `TRUE`/`FALSE` are accepted as shorthand for `"on"`/`"off"`. Header
  formatting is unaffected by this argument in every mode.

- color_columns:

  Columns to fill when `color_mode = "partial"`. Character vector of
  column names (matching ignores case, spaces and underscores) or
  numeric column positions. Ignored in the other two modes. Default
  `NULL`.

- color_palette:

  Character vector of hex colours used to derive the row fills. Defaults
  to the MMC palette; light shade variations are generated from it so
  many groups stay distinct while remaining "in range" of the brand
  colours.

- header_front_size:

  Header font size (default is 12).

- header_front_color:

  Hexcode for header font color (default is white).

- header_fill_color:

  Hexcode for header fill color (default is MMC blue `"#00A2A5"`).

- header_front:

  Font name for header (default is Arial Narrow).

- body_front:

  Font name for body (default is Arial Narrow).

- body_front_size:

  Font size for body (default is 11).

## Value

A workbook
