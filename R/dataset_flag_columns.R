#' Default flag columns added to the `dataset` sheet
#'
#' The reviewer-facing \code{dataset} sheet of a cleaning log carries a small
#' block of helper columns - one per survey-level check - so a reviewer can
#' filter the raw data down to the surveys a check flagged and decide, in place,
#' whether to keep or discard them.
#'
#' Each entry maps a column header to the \code{check_binding} prefixes that
#' feed it. \code{check_binding} is written by every \code{validate_*} function
#' in the shape \code{"<check_id> ~/~ <uuid>"} (soft duplicates use
#' \code{"soft_duplicate ~/~ <uuid> ~/~ <uuid>"} and duplicated answers
#' \code{"dup_q ~/~ <question> ~/~ <enumerator> ~/~ <value>"}), so the text
#' before the first \code{~/~} identifies the check that raised the row.
#'
#' An entry is either a bare character vector of prefixes, or a list with:
#' \describe{
#'   \item{\code{prefixes}}{character vector of \code{check_binding} prefixes.}
#'   \item{\code{value}}{which log column fills the cells - \code{"old_value"}
#'     (the default) or \code{"issue"}. Use \code{"issue"} where the raw value
#'     means nothing on its own.}
#'   \item{\code{label}}{what the ONA label row says the column came from,
#'     written as \code{"Flagged by: <label>"}. Defaults to the prefixes.}
#' }
#'
#' The defaults cover the five survey-level checks a reviewer normally weighs
#' together when judging whether a whole interview is sound:
#'
#' \describe{
#'   \item{\code{duration}}{\code{\link{validate_duration}} -
#'     \code{"duration_check"}. Value: the survey duration in minutes.}
#'   \item{\code{completeness}}{\code{\link{validate_completeness}} -
#'     \code{"completeness_check"}. Value: the number of non-empty cells.}
#'   \item{\code{refused}}{\code{\link{validate_refused}} -
#'     \code{"refused_check"}. Value: the number of refused responses.}
#'   \item{\code{back to back}}{\code{\link{validate_back_to_back}} -
#'     \code{"back_to_back_check"}. Value: the \strong{issue}, not the raw
#'     value. The raw value there is the interview start time, which says
#'     nothing on its own - the gap to the previous interview, the enumerator
#'     and whether the two overlap are all in the issue text, and that is what
#'     a reviewer needs in order to judge the survey.}
#'   \item{\code{similarity}}{\code{\link{validate_similar_surveys}} and
#'     \code{\link{validate_similar_questions}} - \code{"soft_duplicate"} and
#'     \code{"dup_q"}. Value: the \strong{issue}, not the raw value. The raw
#'     value is a count of similar columns or the duplicated answer, neither of
#'     which can be judged without the threshold, the enumerator and the other
#'     survey involved - all of which the issue names. Labelled with the two
#'     log names rather than the binding prefixes, which are not names a
#'     reviewer would recognise.}
#' }
#'
#' Pass your own list to \code{flag_columns} to rename a column, add one for a
#' check of your own, or drop one you do not want:
#'
#' \preformatted{
#' my_flags <- ck_flag_column_defaults()
#' my_flags[["outliers"]] <- "outlier_check"
#' my_flags[["refused"]]  <- NULL
#'
#' # show the issue rather than the raw value
#' my_flags[["duration"]] <- list(prefixes = "duration_check", value = "issue")
#' }
#'
#' @return A named list: column header -> either a character vector of
#'   \code{check_binding} prefixes, or a list of \code{prefixes},
#'   \code{value} and \code{label}.
#' @export
#'
#' @seealso \code{\link{create_cleaning_log}}, which writes these columns, and
#'   \code{\link{ck_flag_column_names}} for the headers alone.
#'
#' @examples
#' ck_flag_column_defaults()
ck_flag_column_defaults <- function() {
  list(
    "duration" = "duration_check",
    "completeness" = "completeness_check",
    "refused" = "refused_check",
    # The start time alone tells a reviewer nothing; the issue carries the gap,
    # the enumerator and whether the interviews overlap.
    "back to back" = list(
      prefixes = "back_to_back_check",
      value = "issue"
    ),
    # A bare count of similar columns means nothing without the threshold it is
    # being judged against, or which enumerator and which other survey it came
    # from - all of which the issue carries.
    #
    # "soft_duplicate, dup_q" are internal binding ids; the log names are what a
    # reviewer would recognise from the pipeline.
    "similarity" = list(
      prefixes = c("soft_duplicate", "dup_q"),
      value = "issue",
      label = "similar_surveys_log, similar_questions_log"
    )
  )
}


#' Headers of the flag columns, as written to the `dataset` sheet
#'
#' A convenience wrapper over \code{\link{ck_flag_column_defaults}} for code
#' that only needs the column names - for instance to drop the helper columns
#' again after reading a reviewed \code{dataset} sheet back in.
#'
#' @param flag_columns A flag-column definition list. Default
#'   \code{ck_flag_column_defaults()}.
#'
#' @return Character vector of column headers.
#' @export
#'
#' @examples
#' ck_flag_column_names()
ck_flag_column_names <- function(flag_columns = ck_flag_column_defaults()) {
  if (is.null(flag_columns) || length(flag_columns) == 0) {
    return(character(0))
  }
  names(flag_columns)
}


#' The check id at the head of a `check_binding`
#'
#' Every \code{validate_*} function writes \code{check_binding} as
#' \code{"<check_id> ~/~ ..."}, so the text before the first separator names the
#' check. Returns \code{NA} for an empty or missing binding.
#'
#' @param x Character vector of \code{check_binding} values.
#'
#' @return Character vector of check ids.
#' @noRd
ck_binding_prefix <- function(x) {
  x <- as.character(x)
  out <- trimws(sub("[[:space:]]*~/~.*$", "", x))
  out[is.na(x) | !nzchar(trimws(x))] <- NA_character_
  out
}


#' Normalise one flag-column entry
#'
#' Both spellings - a bare character vector of prefixes and the full list -
#' become the same three-field structure, so everything downstream reads
#' \code{prefixes}, \code{value} and \code{label} without re-checking the shape.
#'
#' @param spec One element of \code{flag_columns}.
#' @param column_name Its name, used only in error messages.
#'
#' @return A list of \code{prefixes}, \code{value} and \code{label}.
#' @noRd
resolve_flag_column_spec <- function(spec, column_name) {
  if (is.character(spec) || is.factor(spec)) {
    spec <- list(prefixes = as.character(spec))
  }
  if (!is.list(spec)) {
    stop(
      "`flag_columns[[\"",
      column_name,
      "\"]]` must be a character vector of check_binding prefixes, or a list ",
      "of `prefixes`, `value` and `label` (see ck_flag_column_defaults()).",
      call. = FALSE
    )
  }

  prefixes <- trimws(as.character(spec[["prefixes"]]))
  prefixes <- prefixes[nzchar(prefixes)]

  value <- spec[["value"]]
  value <- if (is.null(value)) "old_value" else tolower(trimws(value[1]))
  if (!(value %in% c("old_value", "issue"))) {
    stop(
      "`flag_columns[[\"",
      column_name,
      "\"]]$value` must be \"old_value\" or \"issue\" (got \"",
      value,
      "\").",
      call. = FALSE
    )
  }

  label <- spec[["label"]]
  label <- if (is.null(label)) {
    paste(prefixes, collapse = ", ")
  } else {
    paste(as.character(label), collapse = ", ")
  }

  list(prefixes = prefixes, value = value, label = label)
}


#' Validate and normalise a flag-column definition
#'
#' Accepts the documented named list, and also a plain character vector
#' (\code{c(duration = "duration_check")}) for convenience.
#'
#' @param flag_columns The user's \code{flag_columns} value.
#'
#' @return A named list of \code{prefixes} / \code{value} / \code{label} lists,
#'   possibly empty.
#' @noRd
resolve_flag_columns <- function(flag_columns) {
  if (is.null(flag_columns) || length(flag_columns) == 0) {
    return(list())
  }
  if (isTRUE(flag_columns)) {
    return(ck_flag_column_defaults())
  }
  if (is.logical(flag_columns)) {
    return(list())
  }
  if (is.character(flag_columns)) {
    flag_columns <- as.list(flag_columns)
  }
  if (!is.list(flag_columns)) {
    stop(
      "`flag_columns` must be a named list mapping a column header to one or ",
      "more check_binding prefixes (see ck_flag_column_defaults()), or NULL ",
      "to add no flag columns.",
      call. = FALSE
    )
  }

  nms <- names(flag_columns)
  if (is.null(nms) || any(!nzchar(trimws(nms)))) {
    stop(
      "Every element of `flag_columns` must be named; the name becomes the ",
      "column header on the `dataset` sheet.",
      call. = FALSE
    )
  }
  # The macro receives the ignore list as one comma-separated config value, so a
  # comma in a header would split it in the wrong place.
  if (any(grepl(",", nms, fixed = TRUE))) {
    stop(
      "Flag column headers cannot contain a comma: ",
      paste(nms[grepl(",", nms, fixed = TRUE)], collapse = "; "),
      ".",
      call. = FALSE
    )
  }
  if (anyDuplicated(trimws(nms)) > 0) {
    stop(
      "`flag_columns` has duplicated column headers: ",
      paste(unique(nms[duplicated(trimws(nms))]), collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  names(flag_columns) <- trimws(nms)
  stats::setNames(
    lapply(
      names(flag_columns),
      function(nm) resolve_flag_column_spec(flag_columns[[nm]], nm)
    ),
    names(flag_columns)
  )
}


#' The flag headers as they will actually be written
#'
#' A survey question could legitimately be called \code{duration}, so a flag
#' column whose header already exists in the dataset is renamed with a
#' \code{_flag} suffix rather than shadowing the real column. Both the writer
#' and \code{create_cleaning_log_vba()} - which has to hand the macro the exact
#' headers to ignore - resolve the names through this function, so the two can
#' never disagree.
#'
#' @param flag_columns A resolved flag-column list.
#' @param dataset_names Column names of the checked dataset.
#'
#' @return Character vector of headers, in flag-column order.
#' @noRd
ck_resolved_flag_headers <- function(flag_columns, dataset_names) {
  nms <- names(flag_columns)
  if (length(nms) == 0) {
    return(character(0))
  }
  clashes <- nms %in% dataset_names
  nms[clashes] <- paste0(nms[clashes], "_flag")
  nms
}

#' Mark the flag headers out from the raw-data headers
#'
#' The flag block sits in the same grid as the ONA answers, so without a visual
#' break a reviewer can mistake it for part of the export. The five headers are
#' given their own fill; the cells below keep the ordinary body formatting, so
#' nothing about how the raw data reads changes.
#'
#' Applied after \code{create_formated_wb()} rather than inside it, because the
#' colouring there is driven by a grouping column and knows nothing about which
#' columns are flags.
#'
#' @param workbook The workbook to style.
#' @param sheet Name of the dataset sheet.
#' @param dataset The dataset exactly as written to that sheet, flag columns
#'   included. Used only to locate the flag columns by name.
#' @param flag_headers Headers of the flag columns, as written.
#' @param header_fill Hex fill for the flag header cells.
#' @param header_font_size,header_font_color,header_font Header font settings,
#'   matched to the rest of the header row.
#'
#' @return The workbook, invisibly. Styling is applied by reference.
#' @noRd
ck_style_flag_columns <- function(
  workbook,
  sheet,
  dataset,
  flag_headers,
  header_fill = "#003D58",
  header_font_size = 12,
  header_font_color = "#FFFFFF",
  header_font = "Arial Narrow"
) {
  cols <- match(flag_headers, names(dataset))
  cols <- cols[!is.na(cols)]
  if (length(cols) == 0) {
    return(invisible(workbook))
  }

  openxlsx::addStyle(
    workbook,
    sheet = sheet,
    openxlsx::createStyle(
      fontSize = header_font_size,
      fontColour = header_font_color,
      fontName = header_font,
      textDecoration = "bold",
      fgFill = header_fill,
      halign = "center",
      valign = "center",
      border = "TopBottomLeftRight ",
      borderColour = "#fafafa",
      wrapText = TRUE
    ),
    rows = 1,
    cols = cols,
    gridExpand = TRUE
  )

  invisible(workbook)
}


#' Prepend the check-flag columns to the checked dataset
#'
#' Builds one column per entry of \code{flag_columns} and binds the block in
#' front of the dataset, so the flags sit in the first columns of the
#' \code{dataset} sheet and stay reachable however far right a reviewer
#' scrolls.
#'
#' A cell carries the \code{old_value} of every log row whose
#' \code{check_binding} prefix belongs to that column and whose \code{uuid}
#' matches the record; several hits for one record are joined with
#' \code{separator}. Records the check did not flag are left \code{NA}, so
#' Excel's filter offers a clean "(Blanks)" entry.
#'
#' @param raw The checked dataset, label row included when
#'   \code{skip_label_row = TRUE}.
#' @param cl The combined cleaning log, carrying \code{uuid}, \code{old_value}
#'   and \code{check_binding}.
#' @param uuid_column Name of the uuid column in \code{raw}.
#' @param flag_columns A resolved flag-column list (see
#'   \code{resolve_flag_columns}).
#' @param skip_label_row Logical. Whether row 1 of \code{raw} is the ONA
#'   label/description row.
#' @param separator String joining several flagged values for one record.
#'
#' @return \code{raw} with the flag columns prepended. Returned unchanged when
#'   \code{flag_columns} is empty.
#' @noRd
ck_attach_flag_columns <- function(
  raw,
  cl,
  uuid_column,
  flag_columns,
  skip_label_row = TRUE,
  separator = " | "
) {
  if (length(flag_columns) == 0 || nrow(raw) == 0) {
    return(raw)
  }
  if (!(uuid_column %in% names(raw))) {
    return(raw)
  }

  # The label row is not a record, so it gets a description rather than a value.
  has_label_row <- isTRUE(skip_label_row) && nrow(raw) >= 1
  record_rows <- if (has_label_row) seq.int(2L, nrow(raw)) else seq_len(nrow(raw))
  record_uuid <- as.character(raw[[uuid_column]])[record_rows]

  # `check_binding` is what ties a log row back to the check that raised it. A
  # log assembled without one (create_cleaning_log() falls back to a
  # question-based binding) simply matches nothing, and the columns come out
  # empty rather than wrong.
  cl_prefix <- if ("check_binding" %in% names(cl)) {
    ck_binding_prefix(cl$check_binding)
  } else {
    rep(NA_character_, nrow(cl))
  }
  cl_uuid <- as.character(cl$uuid)

  # A column draws on `old_value` or on `issue`, per its spec. Most checks put a
  # self-explanatory number in old_value; where they do not - the back-to-back
  # check writes the interview start time, which means nothing on its own - the
  # issue text is what a reviewer actually needs.
  cl_source <- list(
    old_value = as.character(cl$old_value),
    issue = if ("issue" %in% names(cl)) {
      as.character(cl$issue)
    } else {
      rep(NA_character_, nrow(cl))
    }
  )

  flag_block <- lapply(names(flag_columns), function(column_name) {
    spec <- flag_columns[[column_name]]
    hit <- !is.na(cl_prefix) & cl_prefix %in% spec$prefixes & !is.na(cl_uuid)

    values <- rep(NA_character_, length(record_uuid))

    if (any(hit)) {
      # One entry per flagged uuid; several rows for the same record (a survey
      # similar to two others, say) are joined rather than silently dropped.
      collapsed <- tapply(
        cl_source[[spec$value]][hit],
        cl_uuid[hit],
        function(v) paste(unique(v[!is.na(v)]), collapse = separator)
      )
      matched <- match(record_uuid, names(collapsed))
      values[!is.na(matched)] <- unname(collapsed[matched[!is.na(matched)]])
      values[!nzchar(as.character(values)) & !is.na(values)] <- NA_character_
    }

    if (has_label_row) {
      c(paste0("Flagged by: ", spec$label), values)
    } else {
      values
    }
  })

  names(flag_block) <- names(flag_columns)

  clashes <- names(flag_block) %in% names(raw)
  if (any(clashes)) {
    warning(paste0(
      "The checked dataset already has column(s) named ",
      paste(names(flag_block)[clashes], collapse = ", "),
      "; the flag column(s) were renamed with a '_flag' suffix. Use ",
      "`flag_columns` to choose different headers."
    ))
  }
  names(flag_block) <- ck_resolved_flag_headers(flag_columns, names(raw))

  flag_df <- as.data.frame(
    flag_block,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )

  cbind(flag_df, raw, stringsAsFactors = FALSE)
}
