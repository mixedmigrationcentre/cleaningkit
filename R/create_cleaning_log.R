#' Normalise a column name for tolerant matching
#'
#' Lower-cases and strips every non-alphanumeric character so that
#' \code{"old_value"}, \code{"Old value"} and \code{"OLD-VALUE"} all resolve to the
#' same key.
#'
#' @param x Character vector of column names.
#'
#' @return Character vector of normalised keys.
#' @noRd
normalize_column_key <- function(x) {
  gsub("[^a-z0-9]", "", tolower(as.character(x)))
}

#' Resolve the requested colouring mode
#'
#' Accepts the three documented modes plus a few common synonyms (including
#' \code{TRUE}/\code{FALSE}) so the argument is forgiving in interactive use.
#'
#' @param color_mode One of \code{"on"}, \code{"partial"}, \code{"off"} (or a synonym /
#'   logical).
#'
#' @return One of \code{"on"}, \code{"partial"} or \code{"off"}.
#' @noRd
resolve_color_mode <- function(color_mode) {
  if (is.null(color_mode) || length(color_mode) == 0) {
    return("on")
  }
  if (is.logical(color_mode)) {
    return(if (isTRUE(color_mode[1])) "on" else "off")
  }

  mode_value <- tolower(trimws(as.character(color_mode[1])))

  on_words <- c("on", "all", "full", "default", "true", "t", "yes", "y")
  off_words <- c("off", "none", "no_color", "false", "f", "no", "n")
  partial_words <- c("partial", "part", "some", "column", "columns", "selected")

  if (mode_value %in% on_words) {
    return("on")
  }
  if (mode_value %in% off_words) {
    return("off")
  }
  if (mode_value %in% partial_words) {
    return("partial")
  }

  stop(
    "`color_mode` must be one of \"on\", \"partial\" or \"off\" (got \"",
    mode_value,
    "\")."
  )
}

#' Resolve requested colour columns to column positions
#'
#' Matching ignores case, spaces, underscores and punctuation, so both the raw log
#' names (\code{"old_value"}) and the reviewer-facing headers (\code{"Old value"})
#' are accepted. Numeric positions are also allowed.
#'
#' @param color_columns Character vector of column names or numeric positions.
#' @param dataset_names Character vector of the sheet's column names.
#' @param sheet_name Sheet name, used only in the warning message.
#'
#' @return Integer vector of column positions (possibly empty).
#' @noRd
resolve_color_columns <- function(
  color_columns,
  dataset_names,
  sheet_name = NULL
) {
  if (is.null(color_columns) || length(color_columns) == 0) {
    return(integer(0))
  }

  if (is.numeric(color_columns)) {
    positions <- as.integer(color_columns)
    positions <- positions[
      !is.na(positions) & positions >= 1 & positions <= length(dataset_names)
    ]
    return(unique(positions))
  }

  positions <- match(
    normalize_column_key(color_columns),
    normalize_column_key(dataset_names)
  )

  if (any(is.na(positions))) {
    warning(paste0(
      "Column(s) not found",
      if (is.null(sheet_name)) "" else paste0(" in sheet '", sheet_name, "'"),
      " and skipped for colouring: ",
      paste(as.character(color_columns)[is.na(positions)], collapse = ", "),
      "."
    ))
  }

  unique(positions[!is.na(positions)])
}

#' Creates formatted workbook with openxlsx
#'
#' @param write_list List of dataframe (one worksheet per element).
#' @param column_for_color Column name used to colourise rows. Rows sharing the same value get
#'   the same fill. Sheets that do not contain this column are left un-coloured. Default \code{NULL}.
#' @param color_mode Controls how much of each row is filled. One of:
#'   \describe{
#'     \item{\code{"on"}}{(default) the whole row is filled, i.e. the original behaviour.}
#'     \item{\code{"partial"}}{only the columns named in \code{color_columns} are filled; every
#'       other cell keeps the plain body style.}
#'     \item{\code{"off"}}{no row fills at all.}
#'   }
#'   \code{TRUE}/\code{FALSE} are accepted as shorthand for \code{"on"}/\code{"off"}.
#'   Header formatting is unaffected by this argument in every mode.
#' @param color_columns Columns to fill when \code{color_mode = "partial"}. Character vector of
#'   column names (matching ignores case, spaces and underscores) or numeric column positions.
#'   Ignored in the other two modes. Default \code{NULL}.
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
  color_mode = "on",
  color_columns = NULL,
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
  color_mode <- resolve_color_mode(color_mode)

  if (color_mode == "partial" && length(color_columns) == 0) {
    warning(
      "`color_mode = \"partial\"` was requested but `color_columns` is empty; no colouring will be applied."
    )
  }

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

    # Row colouring. "off" skips it entirely; "partial" limits the fill to the requested
    # columns; "on" fills the whole row (original behaviour). The header style above is
    # never touched by any of the three modes.
    color_this_sheet <- color_mode != "off" &&
      !is.null(column_for_color) &&
      column_for_color %in% names(dataset) &&
      nrow(dataset) > 0

    if (color_this_sheet) {
      if (color_mode == "partial") {
        fill_cols <- resolve_color_columns(
          color_columns,
          names(dataset),
          dataset_name
        )
      } else {
        fill_cols <- 1:ncol(dataset)
      }

      if (length(fill_cols) > 0) {
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
            cols = fill_cols,
            gridExpand = TRUE
          )
        }
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
#' \code{recoded}, \code{delete_data_point}, \code{discard}, \code{addition}, \code{other}.
#'
#' \strong{Column layout.} \strong{Survey UUID} is the first column (column A) and
#' \strong{Date} the second. Column A and the header row are both frozen, so the uuid and the
#' headers stay visible while a reviewer scrolls right and down.
#'
#' \strong{Row order.} The combined log arrives stacked check by check, so the rows for one
#' interview are scattered down the sheet. By default the reviewer log is regrouped so that
#' every row belonging to one \strong{Survey UUID} sits together in a single block, one survey
#' after another. Blocks appear in the order the uuids are first met in the combined log, and
#' the original order is kept inside each block, so the rows themselves are untouched - only
#' their arrangement changes. Set \code{group_by_uuid = FALSE} to keep the old check-by-check
#' order.
#'
#' \strong{Row colouring.} By default every log row that shares a \code{check_binding} is filled
#' with the same light MMC shade across the whole row. \code{color_mode} changes that:
#' \code{"on"} keeps the default, \code{"partial"} fills only the columns listed in
#' \code{color_columns}, and \code{"off"} writes the log with no fills at all. Header
#' formatting (MMC blue fill, white bold Arial Narrow) is identical in all three modes.
#' \code{color_columns} accepts either the reviewer-facing headers (\code{"Old value"}) or the
#' underlying log names (\code{"old_value"}, \code{"uuid"}, \code{"question"}, \code{"issue"}).
#'
#' @param write_list A list containing the combined log and the checked dataset.
#' @param cleaning_log_name Name of the combined-log element in \code{write_list}. Default \code{"cleaning_log"}.
#' @param dataset_name Name of the checked-dataset element in \code{write_list}. Default \code{"checked_dataset"}.
#' @param uuid_column Name of the uuid column in the checked dataset. Default \code{"_uuid"}.
#' @param enumerator_column Name of the enumerator column in the checked dataset. Default \code{"username"}.
#' @param date_column Name of the survey-date column in the checked dataset. Default \code{"today"}.
#' @param column_for_color Column used to colourise rows. Default \code{"check_binding"}, so all
#'   log rows that share a binding (e.g. several questions flagged by one check for the same
#'   record) get the same colour. The column is written but kept hidden in the output. Set to
#'   \code{NULL} to disable colouring.
#' @param color_mode One of \code{"on"} (default, colour the full row), \code{"partial"} (colour
#'   only \code{color_columns}) or \code{"off"} (no colouring). \code{TRUE}/\code{FALSE} work as
#'   shorthand for \code{"on"}/\code{"off"}. Never affects the header formatting.
#' @param color_columns Columns to fill when \code{color_mode = "partial"}, e.g.
#'   \code{"old_value"} or \code{c("Old value", "Issue")}. Matching ignores case, spaces and
#'   underscores; numeric column positions are also accepted. Default \code{NULL}.
#' @param include_dataset Logical. If \code{TRUE} (the default), the checked dataset is written to
#'   a sheet named \code{"dataset"} so reviewers can refer back to the raw data.
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
#' @param group_by_uuid Logical. If \code{TRUE} (the default), the log rows are regrouped so all
#'   rows from the same \strong{Survey UUID} form one contiguous block, surveys following one
#'   another. Blocks keep the order in which their uuid is first met in the combined log, and
#'   rows keep their original order inside a block. \code{FALSE} keeps the incoming
#'   check-by-check order.
#'
#' @return A workbook object, or (when \code{output_path} is given) writes a \code{.xlsx} file invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' # default: full-row colouring by check_binding
#' create_cleaning_log(write_list, output_path = "cleaning_log.xlsx")
#'
#' # colour only the "Old value" column
#' create_cleaning_log(
#'   write_list,
#'   color_mode = "partial",
#'   color_columns = "old_value",
#'   output_path = "cleaning_log.xlsx"
#' )
#'
#' # no colouring at all
#' create_cleaning_log(write_list, color_mode = "off", output_path = "cleaning_log.xlsx")
#'
#' # keep the old check-by-check row order instead of grouping by survey
#' create_cleaning_log(
#'   write_list,
#'   group_by_uuid = FALSE,
#'   output_path = "cleaning_log.xlsx"
#' )
#' }
create_cleaning_log <- function(
  write_list,
  cleaning_log_name = "cleaning_log",
  dataset_name = "checked_dataset",
  uuid_column = "_uuid",
  enumerator_column = "username",
  date_column = "today",
  column_for_color = "check_binding",
  color_mode = "on",
  color_columns = NULL,
  include_dataset = TRUE,
  header_front_size = 12,
  header_front_color = "#FFFFFF",
  header_fill_color = "#00A2A5",
  header_front = "Arial Narrow",
  body_front = "Arial Narrow",
  body_front_size = 11,
  skip_label_row = TRUE,
  output_path = NULL,
  group_by_uuid = TRUE
) {
  # ---- action codes shared by the drop-down and the readme ----
  action_codes <- c(
    "recoded",
    "delete_data_point",
    "discard",
    "addition",
    "no_action",
    "other"
  )
  action_descriptions <- c(
    "A change to a data point e.g. remove comma, correct typo, change age of participant",
    "Data point is deleted",
    "Delete an entire survey. Provide participant ID in Comments column of log",
    "Any addition to raw data e.g. filling in empty cell or adding a column",
    "No action taken, data point stays the same",
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

  color_mode <- resolve_color_mode(color_mode)

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

  # fall back to a per-question/record binding if the log doesn't carry one
  if (!("check_binding" %in% names(cl))) {
    cl$check_binding <- paste(cl$question, cl$uuid, sep = " ~/~ ")
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
    # Survey UUID first so it lands in column A, which is the frozen column
    "Survey UUID" = cl_uuid,
    "Date" = lookup(date_lookup, cl_uuid),
    "Survey Registration Date" = NA_character_,
    "Enumerator" = lookup(enum_lookup, cl_uuid),
    "Section" = NA_character_,
    "Question number" = as.character(cl$question),
    "Question text" = unname(label_lookup[as.character(cl$question)]),
    "Issue" = as.character(cl$issue),
    "Old value" = as.character(cl$old_value),
    "Action taken" = NA_character_,
    "New value" = NA_character_,
    "Identified by" = NA_character_,
    "Comments" = NA_character_,
    "PO feedback" = NA_character_,
    # trailing helper column used only to colour related rows; hidden in the output
    "check_binding" = as.character(cl$check_binding)
  )

  # ---- group the log by survey ----
  # The combined log arrives stacked check by check, which scatters the rows of one
  # interview down the sheet. Ordering by the first appearance of each uuid puts every
  # row of a survey in one block while keeping the original order inside the block, so
  # the rows are exactly the same rows - only their arrangement changes. Rows sharing a
  # check_binding stay adjacent, so the colour blocks still read correctly.
  if (isTRUE(group_by_uuid) && nrow(final_log) > 1) {
    uuid_values <- final_log[["Survey UUID"]]
    block_rank <- match(uuid_values, unique(uuid_values))
    final_log <- final_log[
      order(block_rank, seq_along(block_rank)), ,
      drop = FALSE
    ]
    rownames(final_log) <- NULL
  }

  # ---- translate colour columns given with the raw log names ----
  # A user may ask for "old_value" (log name) or "Old value" (reviewer header); both must
  # resolve to the header actually written to the sheet.
  if (color_mode == "partial" && length(color_columns) > 0) {
    if (!is.numeric(color_columns)) {
      log_aliases <- c(
        "uuid" = "Survey UUID",
        "surveyuuid" = "Survey UUID",
        "question" = "Question number",
        "questionnumber" = "Question number",
        "questiontext" = "Question text",
        "issue" = "Issue",
        "oldvalue" = "Old value",
        "newvalue" = "New value",
        "action" = "Action taken",
        "actiontaken" = "Action taken",
        "date" = "Date",
        "enumerator" = "Enumerator",
        "section" = "Section",
        "identifiedby" = "Identified by",
        "comments" = "Comments",
        "pofeedback" = "PO feedback",
        "surveyregistrationdate" = "Survey Registration Date",
        "checkbinding" = "check_binding"
      )

      requested <- as.character(color_columns)
      keys <- normalize_column_key(requested)
      matched <- keys %in% names(log_aliases)
      requested[matched] <- unname(log_aliases[keys[matched]])
      color_columns <- unique(requested)
    }
  }

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
    out_list[["dataset"]] <- raw
  }
  out_list[["readme"]] <- readme_df
  out_list[["validation_rules"]] <- validation_df

  workbook <- out_list |>
    create_formated_wb(
      column_for_color = column_for_color,
      color_mode = color_mode,
      color_columns = color_columns,
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

  # hide the helper check_binding column (kept only to drive row colouring)
  cb_col <- which(names(final_log) == "check_binding")
  if (length(cb_col) == 1) {
    openxlsx::setColWidths(
      workbook,
      sheet = cleaning_log_name,
      cols = cb_col,
      widths = 25,
      hidden = TRUE
    )
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
