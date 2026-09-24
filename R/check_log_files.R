#' Check Column Consistency Across Log Files Before Reading Them
#'
#' Scans a folder for log files matching a pattern and reports how many columns
#' each one has, so that a column mismatch can be spotted and fixed \emph{before}
#' it surfaces as an error inside \code{read_cleaning_log()} or
#' \code{read_other_responses()}.
#'
#' @details
#' Both \code{read_cleaning_log()} and \code{read_other_responses()} stack the
#' files they find with \code{do.call(rbind, ...)}, which requires every file to
#' have the same columns in the same order. When one reviewer's workbook carries
#' an extra column - a renamed header, a leftover helper column, an older
#' template with three \code{EXISTING other} slots instead of one - the bind
#' fails with a "numbers of columns of arguments do not match" error that names
#' no file. This function answers the question that error does not: \emph{which}
#' file is the odd one out, and \emph{which} columns differ.
#'
#' \strong{What it reads:} only the header of each file, so it is fast even on
#' large logs. \code{.csv}/\code{.txt} files are read with
#' \code{utils::read.csv()}; \code{.xlsx}, \code{.xlsm} and \code{.xls} files
#' with \code{readxl::read_excel()}.
#'
#' \strong{Reference column set:} the most common set of column names across the
#' readable files is taken as the reference. Each file is then compared against
#' it, and the \code{missing} and \code{extra} columns are listed per file. When
#' every file shares the same set the reference is simply that set.
#'
#' \strong{Sheet selection:} \code{sheet} is passed to
#' \code{readxl::read_excel()} and accepts a name or an integer. Use
#' \code{sheet = 2} for cleaning logs produced by \code{create_cleaning_log()},
#' where sheet 1 is the dataset and sheet 2 is the log. Ignored for csv files.
#'
#' \strong{Unreadable files:} a file that cannot be opened (corrupt, locked by
#' Excel, missing the requested sheet) is reported with \code{n_columns = NA}
#' and the reason in \code{status}, rather than stopping the scan.
#'
#' @param path A directory containing the log files, or a character vector of
#'   file paths to check directly.
#' @param file_pattern Regex used to select files when \code{path} is a
#'   directory. Default \code{"\\\\.(csv|xlsx|xlsm|xls)$"}. Pass the same pattern
#'   you give to \code{read_cleaning_log()} or \code{read_other_responses()} to
#'   check exactly the set of files those functions will read, e.g.
#'   \code{"_follow-ups_edited\\\\.xls[xm]$"}.
#' @param sheet Sheet to read from each Excel file. Accepts a name or integer.
#'   Default \code{1}. Use \code{2} for \code{create_cleaning_log()} output.
#' @param recursive Logical. If \code{TRUE} (the default), sub-folders of
#'   \code{path} are searched too - matching the behaviour of
#'   \code{read_cleaning_log()} and \code{read_other_responses()}.
#' @param ignore_case Logical. If \code{TRUE} (the default), \code{file_pattern}
#'   is matched case-insensitively.
#' @param verbose Logical. If \code{TRUE} (the default), a summary is printed to
#'   the console: the column count per file, and, when the files disagree, the
#'   offending files with their missing and extra columns.
#'
#' @return A dataframe, invisibly when \code{verbose = TRUE}, with one row per
#'   file and the columns:
#'   \describe{
#'     \item{\code{file}}{File name (basename).}
#'     \item{\code{n_columns}}{Number of columns, or \code{NA} if unreadable.}
#'     \item{\code{matches_reference}}{\code{TRUE} when the file's column names
#'       match the reference set exactly (order ignored).}
#'     \item{\code{missing}}{Reference columns absent from this file, comma
#'       separated.}
#'     \item{\code{extra}}{Columns in this file that are not in the reference
#'       set, comma separated.}
#'     \item{\code{status}}{\code{"ok"}, or the error message for an unreadable
#'       file.}
#'     \item{\code{path}}{Full path to the file.}
#'   }
#'   The reference column names are attached as the attribute
#'   \code{"reference_columns"}.
#'
#' @examples
#' \dontrun{
#' # cleaning logs - same pattern and sheet as read_cleaning_log()
#' check_log_files(
#'   "output/follow_ups",
#'   file_pattern = "_follow-ups_edited\\.xls[xm]$",
#'   sheet = 2
#' )
#'
#' # other-responses logs - same pattern as read_other_responses()
#' check_log_files(
#'   "output/other_responses",
#'   file_pattern = "_other_responses_edited\\.xlsx$"
#' )
#'
#' # everything in a folder, whatever the format
#' check_log_files("output/follow_ups")
#' }
#'
#' @export
check_log_files <- function(
  path,
  file_pattern = "\\.(csv|xlsx|xlsm|xls)$",
  sheet = 1,
  recursive = TRUE,
  ignore_case = TRUE,
  verbose = TRUE
) {
  # ---- resolve files -------------------------------------------------------
  if (length(path) > 1) {
    files <- path
    missing_files <- files[!file.exists(files)]
    if (length(missing_files) > 0) {
      stop(paste0(
        "The following file(s) do not exist: ",
        paste(missing_files, collapse = ", ")
      ))
    }
  } else if (dir.exists(path)) {
    files <- list.files(
      path = path,
      pattern = file_pattern,
      recursive = recursive,
      full.names = TRUE,
      ignore.case = ignore_case
    )
    if (length(files) == 0) {
      stop(paste0(
        "No files matching pattern '",
        file_pattern,
        "' found in directory: ",
        path
      ))
    }
  } else if (file.exists(path)) {
    files <- path
  } else {
    stop(paste0("'path' does not exist: ", path))
  }

  # drop Excel lock files (~$name.xlsx) - they match the pattern but are not data
  files <- files[!grepl("^~\\$", basename(files))]
  if (length(files) == 0) {
    stop("Only Excel lock files (~$...) matched. No readable files to check.")
  }

  # ---- read the header of each file ---------------------------------------
  header_of <- function(f) {
    ext <- tolower(tools::file_ext(f))
    if (ext %in% c("csv", "txt")) {
      hdr <- tryCatch(
        utils::read.csv(
          f,
          nrows = 1,
          header = TRUE,
          check.names = FALSE,
          stringsAsFactors = FALSE,
          fileEncoding = "UTF-8"
        ),
        error = function(e) {
          # fall back to the session encoding when the file is not UTF-8
          utils::read.csv(
            f,
            nrows = 1,
            header = TRUE,
            check.names = FALSE,
            stringsAsFactors = FALSE
          )
        }
      )
      names(hdr)
    } else if (ext %in% c("xlsx", "xlsm", "xls")) {
      if (!requireNamespace("readxl", quietly = TRUE)) {
        stop(
          "The 'readxl' package is required. Install it with: install.packages('readxl')"
        )
      }
      hdr <- readxl::read_excel(
        f,
        sheet = sheet,
        n_max = 0,
        col_types = "text",
        .name_repair = "minimal"
      )
      names(hdr)
    } else {
      stop(paste0("Unsupported file extension: '", ext, "'"))
    }
  }

  col_names <- vector("list", length(files))
  statuses <- character(length(files))

  for (i in seq_along(files)) {
    statuses[i] <- "ok"
    col_names[[i]] <- suppressWarnings(
      tryCatch(
        header_of(files[i]),
        error = function(e) {
          statuses[i] <<- conditionMessage(e)
          NULL
        }
      )
    )
  }

  n_columns <- vapply(
    col_names,
    function(x) if (is.null(x)) NA_integer_ else length(x),
    integer(1)
  )

  # ---- reference column set: the most common one among readable files ------
  readable <- !vapply(col_names, is.null, logical(1))
  reference <- character(0)
  if (any(readable)) {
    signatures <- vapply(
      col_names[readable],
      function(x) paste(sort(trimws(x)), collapse = "\u001f"),
      character(1)
    )
    tally <- table(signatures)
    winner <- names(tally)[order(-as.integer(tally), names(tally))][1]
    reference <- col_names[readable][[which(signatures == winner)[1]]]
  }
  reference_trim <- trimws(reference)

  compare <- function(x, what) {
    if (is.null(x)) {
      return(NA_character_)
    }
    xt <- trimws(x)
    diff_cols <- if (identical(what, "missing")) {
      setdiff(reference_trim, xt)
    } else {
      setdiff(xt, reference_trim)
    }
    if (length(diff_cols) == 0) "" else paste(diff_cols, collapse = ", ")
  }

  missing_cols <- vapply(col_names, compare, character(1), what = "missing")
  extra_cols <- vapply(col_names, compare, character(1), what = "extra")

  matches_reference <- !is.na(missing_cols) &
    !is.na(extra_cols) &
    missing_cols == "" &
    extra_cols == ""

  out <- data.frame(
    file = basename(files),
    n_columns = n_columns,
    matches_reference = matches_reference,
    missing = missing_cols,
    extra = extra_cols,
    status = statuses,
    path = files,
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  attr(out, "reference_columns") <- reference

  # ---- console summary ----------------------------------------------------
  if (verbose) {
    n_bad <- sum(!out$matches_reference, na.rm = TRUE) +
      sum(is.na(out$matches_reference))
    n_unreadable <- sum(is.na(out$n_columns))

    message("")
    message(
      "check_log_files: ",
      nrow(out),
      " file(s) checked",
      if (!is.null(sheet) && any(grepl("xls", tolower(tools::file_ext(files))))) {
        paste0(" (Excel sheet: ", sheet, ")")
      } else {
        ""
      }
    )
    message(strrep("-", 70))

    width <- max(nchar(out$file), 4L)
    for (i in seq_len(nrow(out))) {
      flag <- if (is.na(out$n_columns[i])) {
        "UNREADABLE"
      } else if (out$matches_reference[i]) {
        "ok"
      } else {
        "MISMATCH"
      }
      message(
        formatC(out$file[i], width = -width),
        "  ",
        formatC(
          if (is.na(out$n_columns[i])) "NA" else out$n_columns[i],
          width = 4
        ),
        " cols  ",
        flag
      )
    }
    message(strrep("-", 70))

    if (n_bad == 0) {
      message(
        "All files share the same ",
        length(reference),
        " columns. rbind in read_cleaning_log() / read_other_responses() ",
        "will not fail on column mismatch."
      )
    } else {
      message(
        n_bad,
        " file(s) differ from the reference set of ",
        length(reference),
        " columns",
        if (n_unreadable > 0) {
          paste0(" (", n_unreadable, " of them unreadable)")
        } else {
          ""
        },
        ":"
      )
      bad <- out[!out$matches_reference | is.na(out$matches_reference), ,
        drop = FALSE
      ]
      for (i in seq_len(nrow(bad))) {
        message("")
        message("  ", bad$file[i])
        if (is.na(bad$n_columns[i])) {
          message("    could not be read: ", bad$status[i])
          next
        }
        if (nzchar(bad$missing[i])) {
          message("    missing : ", bad$missing[i])
        }
        if (nzchar(bad$extra[i])) {
          message("    extra   : ", bad$extra[i])
        }
      }
      message("")
      message(
        "Fix these files (or exclude them with a narrower `file_pattern`) ",
        "before calling read_cleaning_log() / read_other_responses()."
      )
    }
    message("")
    return(invisible(out))
  }

  out
}
