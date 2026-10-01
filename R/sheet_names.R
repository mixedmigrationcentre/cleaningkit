# ---------------------------------------------------------------------------
# Sheet names for the review workbook
#
# create_cleaning_log(), create_cleaning_log_vba(), save_other_responses(),
# create_review_workbook(), read_cleaning_log() and read_other_responses() all
# have to agree on what the tabs are called. Holding the names in one place is
# what stops a writer and a reader drifting apart: renaming a sheet is a change
# to ck_sheet_names() alone.
# ---------------------------------------------------------------------------

#' Canonical sheet names of a review workbook
#'
#' \describe{
#'   \item{\code{cleaning_log}}{One row per flagged value, filled in by the reviewer.}
#'   \item{\code{dataset}}{The checked dataset, with the flag block prepended.}
#'   \item{\code{other_responses}}{The "other" text responses to review.}
#'   \item{\code{dropdown}}{Choice lists backing the other-responses drop-downs.}
#'   \item{\code{readme}}{Guide to the workbook.}
#'   \item{\code{validation}}{Hidden source of the \code{Action taken} drop-down.}
#'   \item{\code{config}}{Very hidden macro configuration (\code{.xlsm} only).}
#'   \item{\code{ledger}}{Very hidden per-cell edit ledger, created by the macro.}
#' }
#'
#' @return A named character vector of sheet names.
#' @noRd
ck_sheet_names <- function() {
  c(
    cleaning_log = "cleaning_log",
    dataset = "dataset",
    other_responses = "other_responses",
    dropdown = "Dropdown_values",
    readme = "readme",
    validation = "validation_rules",
    config = "_ck_config",
    ledger = "_ck_ledger"
  )
}

#' One canonical sheet name by key
#'
#' @param key One of the names of \code{ck_sheet_names()}.
#'
#' @return A single unnamed character string.
#' @noRd
ck_sheet_name <- function(key) {
  nms <- ck_sheet_names()
  if (!(key %in% names(nms))) {
    stop("Unknown sheet key: ", key, call. = FALSE)
  }
  unname(nms[[key]])
}

#' The tab order a reviewer should meet
#'
#' A reviewer opens the workbook on the raw data, decides what to do there, and
#' only then works through the log, so \code{dataset} leads and
#' \code{cleaning_log} follows it. \code{other_responses} comes next because it
#' is the second thing to fill in, \code{readme} after the three working sheets,
#' and \code{Dropdown_values} last of the visible tabs - it is a source list,
#' nothing to fill in.
#'
#' Sheets not named here (the hidden \code{validation_rules}, \code{_ck_config}
#' and \code{_ck_ledger}) keep their existing relative order behind the ones
#' that are, which is what keeps \code{_ck_config} at the end of the workbook.
#'
#' @param cleaning_log_name,other_sheet_name,dropdown_sheet The names those
#'   sheets were actually given, which the caller may have changed.
#'
#' @return Character vector of sheet names, in the order the tabs should appear.
#' @noRd
ck_tab_order <- function(
  cleaning_log_name = ck_sheet_name("cleaning_log"),
  other_sheet_name = ck_sheet_name("other_responses"),
  dropdown_sheet = ck_sheet_name("dropdown")
) {
  c(
    ck_sheet_name("dataset"),
    cleaning_log_name,
    other_sheet_name,
    ck_sheet_name("readme"),
    dropdown_sheet
  )
}

#' Put the worksheets of a workbook in a given tab order
#'
#' Only the display order changes. The sheets keep their creation order
#' internally, so anything that addresses a sheet by name - the macro, the
#' readers, \code{sheetVisibility()} - is untouched, and so are the worksheet
#' parts inside the saved file.
#'
#' Call this last, once every sheet has been added: \code{openxlsx} appends each
#' new worksheet to the order, so a sheet added afterwards would land at the end
#' regardless of where \code{preferred} wants it.
#'
#' @param wb An openxlsx \code{Workbook}.
#' @param preferred Sheet names in the order they should appear. Names that the
#'   workbook does not carry are ignored; sheets not named keep their relative
#'   order behind those that are.
#'
#' @return \code{wb}, invisibly. The workbook is modified in place.
#' @noRd
ck_order_worksheets <- function(wb, preferred) {
  present <- names(wb)
  if (length(present) < 2) {
    return(invisible(wb))
  }

  preferred <- as.character(preferred)
  preferred <- preferred[!is.na(preferred) & nzchar(preferred)]

  front <- match(preferred, present)
  front <- unique(front[!is.na(front)])
  back <- setdiff(seq_along(present), front)

  openxlsx::worksheetOrder(wb) <- c(front, back)
  invisible(wb)
}

#' Sheet names to look for when reading a reviewed file, best first
#'
#' The other-responses sheet was called \code{Sheet1} before the cleaning log
#' and the other responses were merged into one workbook, so a file produced by
#' the older two-file route is still found without the caller passing anything.
#'
#' @param key One of the names of \code{ck_sheet_names()}.
#'
#' @return Character vector of candidate sheet names, in preference order.
#' @noRd
ck_sheet_candidates <- function(key) {
  legacy <- list(
    other_responses = "Sheet1"
  )
  unique(c(ck_sheet_name(key), legacy[[key]]))
}

#' Resolve a sheet in a workbook file by name, with fallbacks
#'
#' Sheet names are matched case-insensitively, because Excel treats them that
#' way. The name actually present in the file is returned, so it can be handed
#' straight to \code{readxl::read_excel()}.
#'
#' @param file Path to an \code{.xlsx} / \code{.xlsm} file.
#' @param candidates Character vector of sheet names to look for, best first.
#' @param fallback Value returned when none of \code{candidates} is present.
#'   Default \code{1}, the first sheet.
#'
#' @return A sheet name (character) or \code{fallback}.
#' @noRd
ck_resolve_sheet <- function(file, candidates, fallback = 1) {
  present <- tryCatch(readxl::excel_sheets(file), error = function(e) NULL)
  if (is.null(present) || length(present) == 0) {
    return(fallback)
  }
  hit <- match(tolower(candidates), tolower(present))
  hit <- hit[!is.na(hit)]
  if (length(hit) == 0) {
    return(fallback)
  }
  present[hit[1]]
}

#' Reject sheet names Excel cannot carry, or that would collide
#'
#' Excel sheet names are limited to 31 characters, cannot contain
#' \code{[ ] : * ? / \\}, and are unique case-insensitively. openxlsx reports
#' none of this clearly, so it is checked before a workbook is built.
#'
#' @param sheet_names Character vector of the names a workbook will carry.
#' @param caller Name of the calling function, used in the error message.
#'
#' @return \code{TRUE}, invisibly.
#' @noRd
ck_assert_sheet_names <- function(sheet_names, caller = "create_review_workbook") {
  sheet_names <- as.character(sheet_names)

  blank <- !nzchar(trimws(sheet_names)) | is.na(sheet_names)
  if (any(blank)) {
    stop(caller, ": a sheet name cannot be blank.", call. = FALSE)
  }

  too_long <- nchar(sheet_names) > 31L
  if (any(too_long)) {
    stop(
      caller,
      ": Excel allows at most 31 characters in a sheet name. Too long: ",
      paste(sheet_names[too_long], collapse = ", "),
      call. = FALSE
    )
  }

  # Matched character by character rather than with a class: "[:" inside a
  # bracket expression opens a POSIX class name, which makes the obvious
  # pattern fail to compile.
  forbidden <- c("[", "]", ":", "*", "?", "/", "\\")
  bad_chars <- Reduce(
    `|`,
    lapply(forbidden, function(ch) grepl(ch, sheet_names, fixed = TRUE))
  )
  if (any(bad_chars)) {
    stop(
      caller,
      ": a sheet name cannot contain any of [ ] : * ? / \\ . Offending: ",
      paste(sheet_names[bad_chars], collapse = ", "),
      call. = FALSE
    )
  }

  dupes <- unique(sheet_names[duplicated(tolower(sheet_names))])
  if (length(dupes) > 0) {
    stop(
      caller,
      ": two sheets would be given the same name (Excel ignores case): ",
      paste(dupes, collapse = ", "),
      ". Rename one of them.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}
