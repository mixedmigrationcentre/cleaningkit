#' Creates formatted workbook with openxlsx
#'
#' @param write_list List of dataframe (one worksheet per element).
#' @param column_for_color Column name used to colourise rows. Rows sharing the same value get
#'   the same fill. Sheets that do not contain this column are left un-coloured. Default \code{NULL}.
#' @param color_palette Character vector of hex colours used to derive the row fills. Defaults to
#'   the MMC palette; light shade variations are generated from it so many groups stay distinct
#'   while remaining "in range" of the brand colours.
#' @param header_front_size Header font size (default is 12).
#' @param header_front_color Hexcode for header font color (default is white).
#' @param header_fill_color Hexcode for header fill color (default is MMC blue \code{"#00A2A5"}).
#' @param header_front Font name for header (default is Arial Narrow).
#' @param body_front Font name for body (default is Arial Narrow).
#' @param body_front_size Font size for body (default is 11).
#'
#' @return A workbook
#' @export
create_formated_wb <- function(
  write_list,
  column_for_color = NULL,
  color_palette = c(
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
  header_front_size = 12,
  header_front_color = "#FFFFFF",
  header_fill_color = "#00A2A5",
  header_front = "Arial Narrow",
  body_front = "Arial Narrow",
  body_front_size = 11
) {
  # Generate n light shade-variations of the supplied palette. Base hues are cycled and
  # each is blended toward white by a random light fraction, so repeated hues still differ.
  generate_shades <- function(n, palette) {
    if (n <= 0) {
      return(character(0))
    }
    base_idx <- ((seq_len(n) - 1) %% length(palette)) + 1
    frac <- stats::runif(n, min = 0.35, max = 0.78)
    vapply(
      seq_len(n),
      function(k) {
        rgb <- grDevices::col2rgb(palette[base_idx[k]]) / 255
        out <- rgb + (1 - rgb) * frac[k] # move toward white
        grDevices::rgb(out[1], out[2], out[3])
      },
      character(1)
    )
  }

  headerStyle <- openxlsx::createStyle(
    fontSize = header_front_size,
    fontColour = header_front_color,
    halign = "center",
    valign = "center",
    fontName = header_front,
    textDecoration = "bold",
    fgFill = header_fill_color,
    border = "TopBottomLeftRight ",
    borderColour = "#fafafa",
    wrapText = T
  )

  bodyStyle <- openxlsx::createStyle(
    fontSize = body_front_size,
    fontName = body_front,
    border = "TopBottomLeftRight ",
    borderColour = "#4F81BD",
    valign = "center",
    halign = "left"
  )

  wb <- openxlsx::createWorkbook()

  number_of_sheet <- length(write_list)

  for (i in 1:number_of_sheet) {
    dataset_name <- names(write_list[i])
    dataset <- write_list[[dataset_name]] |> as.data.frame()

    openxlsx::addWorksheet(wb, dataset_name)
    openxlsx::writeData(wb, sheet = i, dataset, rowNames = F)
    openxlsx::addFilter(wb, sheet = i, row = 1, cols = 1:ncol(dataset))
    openxlsx::freezePane(wb, sheet = i, firstCol = TRUE, firstRow = T)
    openxlsx::addStyle(
      wb,
      sheet = i,
      headerStyle,
      rows = 1,
      cols = 1:ncol(dataset),
      gridExpand = TRUE
    )
    openxlsx::addStyle(
      wb,
      sheet = i,
      bodyStyle,
      rows = 1:nrow(dataset) + 1,
      cols = 1:ncol(dataset),
      gridExpand = TRUE
    )
    openxlsx::setColWidths(wb, i, cols = 1:ncol(dataset), widths = 25)
    openxlsx::setRowHeights(wb, i, 1, 20)

    if (!is.null(column_for_color) && column_for_color %in% names(dataset)) {
      u <- unique(dataset[[column_for_color]])
      shades <- generate_shades(length(u), color_palette)

      for (k in seq_along(u)) {
        x <- u[k]
        y <- which(dataset[[column_for_color]] == x)

        style <- openxlsx::createStyle(
          fgFill = shades[k],
          fontSize = body_front_size,
          fontName = body_front,
          border = "TopBottomLeftRight ",
          borderColour = "#4F81BD",
          valign = "center",
          halign = "left"
        )

        openxlsx::addStyle(
          wb,
          sheet = i,
          style,
          rows = y + 1,
          cols = 1:ncol(dataset),
          gridExpand = TRUE
        )
      }
    }
  }

  wb
}


#' Creates the final cleaning log workbook
#'
#' Builds the reviewer-facing cleaning log from a combined log (see \code{create_combined_log})
#' and the checked dataset, laying it out with the standard MMC column headers, a \code{readme}
#' sheet explaining the action codes, and a drop-down on the \strong{Action taken} column.
#'
#' @details
#' The checked dataset is expected to still carry the ONA label/description row as its first
#' row: column names supply \strong{Question number} and that first row supplies
#' \strong{Question text}. \strong{Date} and \strong{Enumerator} are looked up per interview
#' from \code{date_column} and \code{enumerator_column}. The remaining reviewer columns
#' (\strong{New value}, \strong{Identified by}, \strong{Action taken}, \strong{Comments},
#' \strong{PO feedback}, \strong{Survey Registration Date}, \strong{Section}) are left blank to
#' be completed during review.
#'
#' The \strong{Action taken} drop-down and the \code{readme} sheet share these five codes:
#' \code{change_response}, \code{delete_data_point}, \code{discard}, \code{addition},
#' \code{other}.
#'
#' @param write_list A list containing the combined log and the checked dataset.
#' @param cleaning_log_name Name of the combined-log element in \code{write_list}. Default \code{"cleaning_log"}.
#' @param dataset_name Name of the checked-dataset element in \code{write_list}. Default \code{"checked_dataset"}.
#' @param uuid_column Name of the uuid column in the checked dataset. Default \code{"_uuid"}.
#' @param enumerator_column Name of the enumerator column in the checked dataset. Default \code{"username"}.
#' @param date_column Name of the survey-date column in the checked dataset. Default \code{"today"}.
#' @param column_for_color Final-log column used to colourise rows. Default \code{"Survey UUID"}
#'   (all issues from one interview share a colour). Set to \code{NULL} to disable colouring.
#' @param include_dataset Logical. If \code{TRUE}, the checked dataset is also written as a sheet.
#'   Default \code{FALSE}.
#' @param header_front_size Header font size (default is 12).
#' @param header_front_color Hexcode for header font color (default is white).
#' @param header_fill_color Hexcode for header fill color (default is MMC blue \code{"#00A2A5"}).
#' @param header_front Font name for header (default is Arial Narrow).
#' @param body_front Font name for body (default is Arial Narrow).
#' @param body_front_size Font size for body (default is 11).
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of the checked
#'   dataset is treated as the ONA label/description row: it supplies \strong{Question text} and
#'   the actual records are taken from row 2 onward. If \code{FALSE}, every row is treated as a
#'   record and \strong{Question text} is left blank (no label row to read from).
#' @param output_path Output path. Default \code{NULL} returns a workbook instead of writing a file.
#'
#' @return A workbook object, or (when \code{output_path} is given) writes a \code{.xlsx} file invisibly.
#' @export
create_cleaning_log <- function(
  write_list,
  cleaning_log_name = "cleaning_log",
  dataset_name = "checked_dataset",
  uuid_column = "_uuid",
  enumerator_column = "username",
  date_column = "today",
  column_for_color = "Survey UUID",
  include_dataset = FALSE,
  header_front_size = 12,
  header_front_color = "#FFFFFF",
  header_fill_color = "#00A2A5",
  header_front = "Arial Narrow",
  body_front = "Arial Narrow",
  body_front_size = 11,
  skip_label_row = TRUE,
  output_path = NULL
) {
  # ---- action codes shared by the drop-down and the readme ----
  action_codes <- c(
    "change_response",
    "delete_data_point",
    "discard",
    "addition",
    "other"
  )
  action_descriptions <- c(
    "A change to a data point e.g. remove comma, correct typo, change age of participant",
    "Data point is deleted",
    "Delete an entire survey. Provide participant ID in Comments column of log",
    "Any addition to raw data e.g. filling in empty cell or adding a column",
    "Any change made to the raw data that cannot be classified using labels above"
  )

  # ---- validation ----
  if (!is.list(write_list) || is.data.frame(write_list)) {
    stop(
      "`write_list` must be a list containing the combined log and the checked dataset."
    )
  }
  if (!(cleaning_log_name %in% names(write_list))) {
    stop(paste0("'", cleaning_log_name, "' not found in the given list."))
  }
  if (!(dataset_name %in% names(write_list))) {
    stop(paste0("'", dataset_name, "' not found in the given list."))
  }
  if ("validation_rules" %in% names(write_list)) {
    stop(
      "The list already has an element named `validation_rules`. Please rename it."
    )
  }

  cl <- as.data.frame(write_list[[cleaning_log_name]], stringsAsFactors = FALSE)
  raw <- as.data.frame(write_list[[dataset_name]], stringsAsFactors = FALSE)

  for (nm in c("uuid", "old_value", "question", "issue")) {
    if (!(nm %in% names(cl))) {
      stop(paste0(
        "Column '",
        nm,
        "' is missing from '",
        cleaning_log_name,
        "'."
      ))
    }
  }
  if (!(uuid_column %in% names(raw))) {
    stop(paste0("Cannot find ", uuid_column, " in ", dataset_name, "."))
  }

  # ---- build lookups from the checked dataset ----
  # When skip_label_row = TRUE, the first row is the ONA label/description row: it supplies
  # Question text and the actual records are rows 2+. When FALSE, every row is a record and
  # there is no label row to read from, so Question text is left blank.
  if (skip_label_row && nrow(raw) >= 1) {
    label_lookup <- stats::setNames(
      as.character(unlist(raw[1, ], use.names = FALSE)),
      names(raw)
    )
    data_rows <- raw[-1, , drop = FALSE]
  } else {
    label_lookup <- stats::setNames(character(0), character(0))
    data_rows <- raw
  }

  uuid_key <- as.character(data_rows[[uuid_column]])

  enum_lookup <- if (enumerator_column %in% names(data_rows)) {
    stats::setNames(as.character(data_rows[[enumerator_column]]), uuid_key)
  } else {
    warning(paste0(
      "'",
      enumerator_column,
      "' not found; Enumerator left blank."
    ))
    NULL
  }

  # Reduce a timestamp to a clean YYYY-MM-DD date. Handles Date/POSIXct columns and
  # ISO-8601 character strings (e.g. "2023-05-12T09:34:21.000+03:00" -> "2023-05-12");
  # anything that isn't date-like is left untouched.
  clean_date <- function(x) {
    if (inherits(x, c("POSIXct", "POSIXt", "Date"))) {
      return(format(x, "%Y-%m-%d"))
    }
    x_chr <- as.character(x)
    is_iso <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", x_chr)
    x_chr[is_iso] <- substr(x_chr[is_iso], 1, 10)
    x_chr
  }

  date_lookup <- if (date_column %in% names(data_rows)) {
    stats::setNames(clean_date(data_rows[[date_column]]), uuid_key)
  } else {
    warning(paste0("'", date_column, "' not found; Date left blank."))
    NULL
  }

  cl_uuid <- as.character(cl$uuid)
  lookup <- function(tbl, key) {
    if (is.null(tbl)) NA_character_ else unname(tbl[key])
  }

  # ---- assemble the final reviewer log in the required column order ----
  final_log <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    "Date" = lookup(date_lookup, cl_uuid),
    "Survey UUID" = cl_uuid,
    "Survey Registration Date" = NA_character_,
    "Enumerator" = lookup(enum_lookup, cl_uuid),
    "Section" = NA_character_,
    "Question number" = as.character(cl$question),
    "Question text" = unname(label_lookup[as.character(cl$question)]),
    "Issue" = as.character(cl$issue),
    "Old value" = as.character(cl$old_value),
    "New value" = NA_character_,
    "Identified by" = NA_character_,
    "Action taken" = NA_character_,
    "Comments" = NA_character_,
    "PO feedback" = NA_character_
  )

  # ---- readme and (hidden) validation sheets ----
  readme_df <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    "Action taken" = action_codes,
    "Description" = action_descriptions
  )
  validation_df <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    change_type_validation = action_codes
  )

  # ---- order the sheets and build the workbook ----
  out_list <- list()
  out_list[[cleaning_log_name]] <- final_log
  if (include_dataset) {
    out_list[[dataset_name]] <- raw
  }
  out_list[["readme"]] <- readme_df
  out_list[["validation_rules"]] <- validation_df

  workbook <- out_list |>
    create_formated_wb(
      column_for_color = column_for_color,
      header_front_size = header_front_size,
      header_front_color = header_front_color,
      header_fill_color = header_fill_color,
      header_front = header_front,
      body_front = body_front,
      body_front_size = body_front_size
    )

  # hide the validation source sheet
  hide_sheet <- which(names(workbook) == "validation_rules")
  if (length(hide_sheet) == 1) {
    openxlsx::sheetVisibility(workbook)[hide_sheet] <- FALSE
  }

  # ---- Action taken drop-down, pointing at the validation_rules sheet ----
  if (nrow(final_log) > 0) {
    col_number <- which(names(final_log) == "Action taken")
    row_numbers <- 2:(nrow(final_log) + 1)
    val_range <- paste0("'validation_rules'!$A$2:$A$", length(action_codes) + 1)

    openxlsx::dataValidation(
      workbook,
      sheet = cleaning_log_name,
      cols = col_number,
      rows = row_numbers,
      type = "list",
      value = val_range
    ) |>
      suppressWarnings()
  }

  if (is.null(output_path)) {
    return(workbook)
  }
  openxlsx::saveWorkbook(workbook, output_path, overwrite = TRUE)
  invisible(output_path)
}
