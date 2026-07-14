#' Export Final Data Cleaning Output Workbook
#'
#' Writes a single Excel workbook containing four sheets:
#' \enumerate{
#'   \item \strong{readme} — project description and sheet guide, styled with MMC colours.
#'   \item \strong{raw_data} — the original raw dataset (ONA label row preserved as row 1).
#'   \item \strong{clean_data} — the cleaned dataset produced by \code{apply_cleaning_log()}.
#'   \item \strong{cleaning_log} — the combined cleaning log from \code{combine_reviewed_logs()}.
#' }
#'
#' The readme sheet is the landing page for any reviewer: it explains what each
#' other sheet contains and provides a project description cell the team can fill
#' in. It is styled with the Mixed Migration Centre colour palette.
#'
#' @param raw_dataset The original raw dataset (with ONA label row as row 1 if
#'   \code{skip_label_row = TRUE}).
#' @param clean_dataset The cleaned dataset produced by \code{apply_cleaning_log()}.
#' @param combined_log The combined cleaning log produced by
#'   \code{combine_reviewed_logs()}, or any dataframe in the same shape.
#' @param output_path Full path (including filename) for the output \code{.xlsx}
#'   file. Default \code{"./output/final/cleaning_output.xlsx"}.
#' @param project_name Short project name shown in the readme header. Default
#'   \code{"Mixed Migration Centre Data Cleaning"}.
#' @param project_description Longer project description written into the readme.
#'   Default provides a generic placeholder the team can overwrite.
#' @param data_collection_round Optional string for the data collection round /
#'   wave (e.g. \code{"Round 12 — Q1 2025"}). Default \code{NULL} (omitted).
#' @param prepared_by Name of the person or team who prepared the output.
#'   Default \code{NULL} (omitted).
#' @param sheet_names Named character vector of length 4 giving the sheet tab
#'   names. Default \code{c(readme = "readme", raw = "raw_data", clean = "clean_data", log = "cleaning_log")}.
#' @param mmc_colors Character vector of hex colours used for readme styling.
#'   Defaults to the full MMC colour palette.
#' @param header_font Font name for column-header rows. Default \code{"Arial Narrow"}.
#' @param body_font Font name for data rows. Default \code{"Arial Narrow"}.
#' @param freeze_panes Logical. If \code{TRUE} (the default), the first row and
#'   first column are frozen on the data sheets.
#' @param add_filters Logical. If \code{TRUE} (the default), auto-filters are
#'   added to the header row of each data sheet.
#' @param overwrite Logical. If \code{TRUE} (the default), an existing file at
#'   \code{output_path} is overwritten.
#'
#' @return Invisibly returns \code{output_path}. The workbook is saved to disk.
#' @export
export_final_output <- function(
  raw_dataset,
  clean_dataset,
  combined_log,
  output_path = "path to output .xlsx",
  project_name = "Mixed Migration Centre Data Cleaning",
  project_description = paste0(
    "This workbook contains the outputs of the data cleaning process. ",
    "The raw_data sheet holds the original survey export from ONA; ",
    "clean_data holds the dataset after all validated changes were applied; ",
    "cleaning_log holds the full record of every change made, including ",
    "other-response recoding. Update this description to reflect the specific ",
    "round, location, and scope of this data collection exercise."
  ),
  data_collection_round = NULL,
  prepared_by = NULL,
  sheet_names = c(
    readme = "readme",
    raw = "raw_data",
    clean = "clean_data",
    log = "cleaning_log"
  ),
  mmc_colors = c(
    "#003D58",
    "#00A2A5",
    "#AFDFE4",
    "#D5EEF0",
    "#FFE07C",
    "#B88AAB",
    "#BBD876",
    "#FBBC75",
    "#F8AB9E",
    "#5B9E62",
    "#009BD9",
    "#F15B5B",
    "#63193B"
  ),
  header_font = "Arial Narrow",
  body_font = "Arial Narrow",
  freeze_panes = TRUE,
  add_filters = TRUE,
  overwrite = TRUE
) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop(
      "The 'openxlsx' package is required. Install with: install.packages('openxlsx')"
    )
  }

  for (arg in list(
    list(raw_dataset, "raw_dataset"),
    list(clean_dataset, "clean_dataset"),
    list(combined_log, "combined_log")
  )) {
    if (!is.data.frame(arg[[1]])) {
      stop(paste0("`", arg[[2]], "` must be a dataframe."))
    }
  }

  # create output directory if needed
  out_dir <- dirname(output_path)
  if (!dir.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE)
  }

  # ---- colour helpers ----
  # MMC dark blue as the primary header colour
  mmc_dark_blue <- "#003D58"
  mmc_teal <- "#00A2A5"
  mmc_light_blue <- "#AFDFE4"
  mmc_faint_blue <- "#D5EEF0"
  mmc_yellow <- "#FFE07C"
  mmc_dark_red <- "#63193B"

  # ---- shared styles ----
  style_data_header <- openxlsx::createStyle(
    fontName = header_font,
    fontSize = 11,
    fontColour = "#FFFFFF",
    textDecoration = "bold",
    fgFill = mmc_dark_blue,
    halign = "center",
    valign = "center",
    border = "TopBottomLeftRight",
    borderColour = "#fafafa",
    wrapText = TRUE
  )
  style_data_body <- openxlsx::createStyle(
    fontName = body_font,
    fontSize = 10,
    border = "TopBottomLeftRight",
    borderColour = "#AFDFE4",
    valign = "center",
    halign = "left"
  )

  # ---- write each data sheet ----
  write_data_sheet <- function(wb, sheet_name, df, tab_colour = NULL) {
    openxlsx::addWorksheet(wb, sheet_name, tabColour = tab_colour)
    openxlsx::writeData(wb, sheet = sheet_name, df, rowNames = FALSE)

    n_cols <- ncol(df)
    n_rows <- nrow(df)

    if (add_filters) {
      openxlsx::addFilter(wb, sheet_name, row = 1, cols = seq_len(n_cols))
    }
    if (freeze_panes) {
      openxlsx::freezePane(wb, sheet_name, firstRow = TRUE, firstCol = TRUE)
    }

    openxlsx::addStyle(
      wb,
      sheet_name,
      style_data_header,
      rows = 1,
      cols = seq_len(n_cols),
      gridExpand = TRUE
    )
    if (n_rows > 0) {
      openxlsx::addStyle(
        wb,
        sheet_name,
        style_data_body,
        rows = seq_len(n_rows) + 1,
        cols = seq_len(n_cols),
        gridExpand = TRUE
      )
    }
    openxlsx::setColWidths(wb, sheet_name, cols = seq_len(n_cols), widths = 22)
    openxlsx::setRowHeights(wb, sheet_name, rows = 1, heights = 28)
  }

  # ---- build workbook ----
  wb <- openxlsx::createWorkbook()
  openxlsx::modifyBaseFont(wb, fontSize = 10, fontName = body_font)

  # ---- sheet 1: readme ----
  openxlsx::addWorksheet(wb, sheet_names[["readme"]], tabColour = mmc_teal)

  # helper: write one formatted block to the readme
  readme_row <- 1L

  push <- function(
    wb,
    sn,
    value,
    fill,
    font_colour = "#FFFFFF",
    bold = FALSE,
    font_size = 11,
    row_height = 20,
    wrap = TRUE,
    halign = "left"
  ) {
    st <- openxlsx::createStyle(
      fontName = header_font,
      fontSize = font_size,
      fontColour = font_colour,
      textDecoration = if (bold) "bold" else NULL,
      fgFill = fill,
      halign = halign,
      valign = "center",
      wrapText = wrap,
      border = "TopBottomLeftRight",
      borderColour = "#FFFFFF"
    )
    openxlsx::writeData(
      wb,
      sheet = sn,
      x = value,
      startRow = readme_row,
      startCol = 1,
      colNames = FALSE
    )
    openxlsx::mergeCells(wb, sheet = sn, rows = readme_row, cols = 1:6)
    openxlsx::addStyle(
      wb,
      sheet = sn,
      st,
      rows = readme_row,
      cols = 1:6,
      gridExpand = TRUE
    )
    openxlsx::setRowHeights(
      wb,
      sheet = sn,
      rows = readme_row,
      heights = row_height
    )
    readme_row <<- readme_row + 1L
  }

  push_table_row <- function(
    wb,
    sn,
    label,
    content,
    label_fill,
    content_fill,
    label_colour = "#FFFFFF",
    content_colour = "#003D58"
  ) {
    label_style <- openxlsx::createStyle(
      fontName = header_font,
      fontSize = 10,
      fontColour = label_colour,
      textDecoration = "bold",
      fgFill = label_fill,
      halign = "left",
      valign = "center",
      wrapText = TRUE,
      border = "TopBottomLeftRight",
      borderColour = "#FFFFFF"
    )
    content_style <- openxlsx::createStyle(
      fontName = body_font,
      fontSize = 10,
      fontColour = content_colour,
      fgFill = content_fill,
      halign = "left",
      valign = "center",
      wrapText = TRUE,
      border = "TopBottomLeftRight",
      borderColour = "#AFDFE4"
    )
    openxlsx::writeData(
      wb,
      sheet = sn,
      x = label,
      startRow = readme_row,
      startCol = 1,
      colNames = FALSE
    )
    openxlsx::writeData(
      wb,
      sheet = sn,
      x = content,
      startRow = readme_row,
      startCol = 2,
      colNames = FALSE
    )
    openxlsx::mergeCells(wb, sheet = sn, rows = readme_row, cols = 2:6)
    openxlsx::addStyle(wb, sheet = sn, label_style, rows = readme_row, cols = 1)
    openxlsx::addStyle(
      wb,
      sheet = sn,
      content_style,
      rows = readme_row,
      cols = 2:6,
      gridExpand = TRUE
    )
    openxlsx::setRowHeights(wb, sheet = sn, rows = readme_row, heights = 28)
    readme_row <<- readme_row + 1L
  }

  sn <- sheet_names[["readme"]]

  # ---- TITLE BANNER ----
  push(
    wb,
    sn,
    project_name,
    fill = mmc_dark_blue,
    bold = TRUE,
    font_size = 16,
    row_height = 40,
    halign = "center"
  )

  push(wb, sn, "", fill = mmc_teal, row_height = 6) # thin colour band

  # ---- PROJECT INFO BLOCK ----
  push(
    wb,
    sn,
    "PROJECT INFORMATION",
    fill = mmc_teal,
    bold = TRUE,
    font_size = 11,
    row_height = 22
  )

  if (!is.null(data_collection_round)) {
    push_table_row(
      wb,
      sn,
      "Data Collection Round",
      data_collection_round,
      label_fill = mmc_dark_blue,
      content_fill = mmc_faint_blue,
      content_colour = mmc_dark_blue
    )
  }
  if (!is.null(prepared_by)) {
    push_table_row(
      wb,
      sn,
      "Prepared by",
      prepared_by,
      label_fill = mmc_dark_blue,
      content_fill = mmc_faint_blue,
      content_colour = mmc_dark_blue
    )
  }
  push_table_row(
    wb,
    sn,
    "Date produced",
    format(Sys.Date(), "%d %B %Y"),
    label_fill = mmc_dark_blue,
    content_fill = mmc_faint_blue,
    content_colour = mmc_dark_blue
  )

  push(wb, sn, "", fill = "#FFFFFF", row_height = 8) # spacer

  # ---- DESCRIPTION ----
  push(
    wb,
    sn,
    "DESCRIPTION",
    fill = mmc_teal,
    bold = TRUE,
    font_size = 11,
    row_height = 22
  )
  push(
    wb,
    sn,
    project_description,
    fill = mmc_faint_blue,
    font_colour = mmc_dark_blue,
    bold = FALSE,
    font_size = 10,
    row_height = 60,
    wrap = TRUE,
    halign = "left"
  )

  push(wb, sn, "", fill = "#FFFFFF", row_height = 8)

  # ---- SHEET GUIDE ----
  push(
    wb,
    sn,
    "SHEET GUIDE",
    fill = mmc_teal,
    bold = TRUE,
    font_size = 11,
    row_height = 22
  )

  sheet_guide <- list(
    list(
      name = sheet_names[["readme"]],
      fill = mmc_teal,
      desc = "This sheet. Provides an overview of the workbook, project description, and explanation of each sheet. Update the project description and round information to reflect the specific data collection exercise."
    ),
    list(
      name = sheet_names[["raw"]],
      fill = mmc_dark_blue,
      desc = paste0(
        "The original raw dataset as exported from ONA (or equivalent XLSForm platform). ",
        "Row 1 contains the column variable names; row 2 contains the ONA label/description row. ",
        "Actual survey records begin at row 3. This sheet is read-only — no changes should be made here. ",
        "Contains ",
        nrow(raw_dataset),
        " rows (including label row) and ",
        ncol(raw_dataset),
        " columns."
      )
    ),
    list(
      name = sheet_names[["clean"]],
      fill = "#5B9E62",
      desc = paste0(
        "The cleaned dataset after all validated changes from the cleaning log have been applied. ",
        "Surveys marked 'discard' have been removed. Row 1 is the ONA label row. ",
        "Contains ",
        nrow(clean_dataset),
        " rows (including label row) and ",
        ncol(clean_dataset),
        " columns."
      )
    ),
    list(
      name = sheet_names[["log"]],
      fill = "#B88AAB",
      desc = paste0(
        "The combined cleaning log documenting every change made to the dataset. ",
        "Includes both the standard validation checks and the other-response recoding. ",
        "Key columns: 'Survey UUID' identifies the record; 'Question number' identifies ",
        "the column changed; 'Action taken' describes the type of change; ",
        "'Old value' and 'New value' show what changed. ",
        "Contains ",
        nrow(combined_log),
        " log rows."
      )
    )
  )

  alt_fills <- c(mmc_faint_blue, "#FFFFFF")
  for (i in seq_along(sheet_guide)) {
    s <- sheet_guide[[i]]
    push_table_row(
      wb,
      sn,
      label = s$name,
      content = s$desc,
      label_fill = s$fill,
      content_fill = alt_fills[((i - 1) %% 2) + 1],
      label_colour = "#FFFFFF",
      content_colour = mmc_dark_blue
    )
  }

  push(wb, sn, "", fill = "#FFFFFF", row_height = 8)

  # ---- CHANGE TYPE LEGEND ----
  push(
    wb,
    sn,
    "CLEANING LOG: ACTION TYPES",
    fill = mmc_teal,
    bold = TRUE,
    font_size = 11,
    row_height = 22
  )

  action_guide <- list(
    list(
      "recoded",
      "A data point was corrected (e.g. remove comma, fix typo, correct age). New value contains the corrected entry."
    ),
    list(
      "delete_data_point",
      "A single data point was deleted and set to blank. The cell is empty in the clean dataset."
    ),
    list(
      "discard",
      "The entire survey record was removed from the clean dataset. Provide participant ID in Comments if relevant."
    ),
    list(
      "addition",
      "A previously empty cell was filled in. New value contains the added entry."
    ),
    list(
      "other",
      "A change was made that does not fit the standard categories above. New value contains the result."
    ),
    list(
      "no_action",
      "The flag was reviewed and no change was required. Old value and New value match."
    ),
    list(
      "true_other",
      "A genuine 'other' free-text response — New value contains the translation or corrected wording."
    ),
    list(
      "recode",
      "An 'other' free-text response was matched to an existing choice option. Parent question updated accordingly."
    ),
    list(
      "remove",
      "An invalid 'other' free-text response was removed. The _other text column and parent question were blanked."
    )
  )

  action_fills <- c(mmc_faint_blue, "#FFFFFF")
  for (i in seq_along(action_guide)) {
    a <- action_guide[[i]]
    push_table_row(
      wb,
      sn,
      label = a[[1]],
      content = a[[2]],
      label_fill = mmc_dark_blue,
      content_fill = action_fills[((i - 1) %% 2) + 1],
      label_colour = "#FFFFFF",
      content_colour = mmc_dark_blue
    )
  }

  push(wb, sn, "", fill = "#FFFFFF", row_height = 8)

  # ---- MMC FOOTER STRIPE ----
  # draw the palette as a colour stripe at the bottom
  stripe_style <- function(col) {
    openxlsx::createStyle(
      fgFill = col,
      border = "TopBottomLeftRight",
      borderColour = "#FFFFFF"
    )
  }
  for (col_i in seq_along(mmc_colors)) {
    openxlsx::writeData(
      wb,
      sheet = sn,
      x = "",
      startRow = readme_row,
      startCol = col_i,
      colNames = FALSE
    )
    openxlsx::addStyle(
      wb,
      sheet = sn,
      stripe_style(mmc_colors[col_i]),
      rows = readme_row,
      cols = col_i
    )
  }
  openxlsx::setRowHeights(wb, sheet = sn, rows = readme_row, heights = 10)

  # set column widths on readme
  openxlsx::setColWidths(
    wb,
    sheet = sn,
    cols = 1:6,
    widths = c(28, 20, 20, 20, 20, 20)
  )

  # ---- sheets 2-4: data ----
  write_data_sheet(
    wb,
    sheet_names[["raw"]],
    as.data.frame(raw_dataset),
    tab_colour = mmc_dark_blue
  )
  write_data_sheet(
    wb,
    sheet_names[["clean"]],
    as.data.frame(clean_dataset),
    tab_colour = "#5B9E62"
  )

  # drop the check_binding helper column before writing — it is used internally
  # for row colouring only and is not meaningful to the end reviewer
  log_for_output <- as.data.frame(combined_log)
  log_for_output[["check_binding"]] <- NULL

  write_data_sheet(
    wb,
    sheet_names[["log"]],
    log_for_output,
    tab_colour = "#B88AAB"
  )

  # colour the tab backgrounds on data sheets
  openxlsx::worksheetOrder(wb) # ensure order: readme first

  # ---- save ----
  openxlsx::saveWorkbook(wb, output_path, overwrite = overwrite)

  message(
    "export_final_output: workbook saved to '",
    output_path,
    "' (",
    length(sheet_names),
    " sheets, ",
    nrow(raw_dataset),
    " raw rows, ",
    nrow(clean_dataset),
    " clean rows, ",
    nrow(combined_log),
    " log rows)."
  )
  invisible(output_path)
}
