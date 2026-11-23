# Round memory: which surveys were already checked, kept inside the workbooks
# the round produces instead of in a folder.
#
# A 4Mi round is checked from a cumulative ONA download: every download holds
# everything collected so far. filter_new_records() remembers what was already
# checked through files in the data/ folder. The functions here keep the same
# memory in very hidden sheets of the review workbook and the final workbook,
# so the next round only needs the new download and the last workbook:
#
#   info <- ck_round_info(new_data, "R7", previous = read_round_info(last_wb))
#   create_review_workbook(..., round_info = info)
#
# Sheets written (all veryHidden, all text):
#   _ck_round     key / value: format, round name and id, date, settings of
#                 the round, and the columns the fingerprints cover
#   _ck_checked   uuid / round_name / round_id / checked_on / fingerprint
#   _ck_settings  key / part / value: free settings, e.g. an app profile
#   _ck_survey, _ck_choices, _ck_checklist: the questionnaire and checklist

.round_format_version <- "1"

.round_sheets <- c(
  round = "_ck_round",
  checked = "_ck_checked",
  settings = "_ck_settings",
  survey = "_ck_survey",
  choices = "_ck_choices",
  checklist = "_ck_checklist"
)

# Excel holds at most 32,767 characters in a cell.
.round_cell_limit <- 30000L

#' Fingerprint each survey in a dataset
#'
#' A hash of each survey's answers, used to notice when a survey changed on
#' ONA between being checked and being cleaned. ONA metadata columns (names
#' starting with an underscore, such as \code{_submission_time} or
#' \code{_status}) are left out by default because they change without the
#' answers changing.
#'
#' Compare fingerprints only between datasets read the same way (for example
#' both with \code{read_raw_data()}), since the hash is taken over the values
#' as text.
#'
#' @param dataset A data frame of surveys.
#' @param uuid_column Name of the survey ID column. Default \code{"_uuid"}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), row one is the
#'   ONA label row and is left out.
#' @param columns Columns to hash. Default \code{NULL}: every column whose name
#'   does not start with an underscore. Columns missing from \code{dataset}
#'   count as empty, so a later download with extra columns still matches.
#'
#' @return A data frame with \code{uuid} and \code{fingerprint}, and the
#'   columns used in the attribute \code{"columns"}.
#' @export
#' @examples
#' df <- data.frame(`_uuid` = c("a", "b"), Q1 = c("1", "2"), check.names = FALSE)
#' round_fingerprint(df, skip_label_row = FALSE)
round_fingerprint <- function(
  dataset,
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  columns = NULL
) {
  dataset <- .round_body(dataset, uuid_column, skip_label_row)
  if (is.null(columns)) {
    columns <- names(dataset)[!startsWith(names(dataset), "_")]
  }
  columns <- as.character(columns)
  values <- lapply(columns, function(col) {
    if (col %in% names(dataset)) {
      v <- as.character(dataset[[col]])
      v[is.na(v)] <- ""
      trimws(v)
    } else {
      rep("", nrow(dataset))
    }
  })
  fingerprint <- if (nrow(dataset) == 0) {
    character(0)
  } else {
    mat <- do.call(cbind, c(values, list(character(nrow(dataset)))))
    apply(mat, 1, function(row) rlang::hash(unname(row)))
  }
  out <- data.frame(
    uuid = trimws(as.character(dataset[[uuid_column]])),
    fingerprint = fingerprint,
    stringsAsFactors = FALSE
  )
  attr(out, "columns") <- columns
  out
}

#' Describe a round for the workbooks to remember
#'
#' Builds the round memory that \code{create_review_workbook()} and
#' \code{export_final_output()} write into their hidden sheets: every survey ID
#' checked so far (the previous rounds' plus this one's), a fingerprint of each
#' survey in this round, and optionally the questionnaire, the logical
#' checklist and any settings, so the next round needs only the new ONA
#' download and the last workbook.
#'
#' @param dataset The surveys checked in this round (after
#'   \code{keep_new_records()}).
#' @param round_name Free text naming the round, e.g. \code{"R7"} or
#'   \code{"Nov week 2"}. Rounds are ordered by the date they were checked,
#'   never by name.
#' @param previous The memory of earlier rounds: a \code{ck_round_info} from
#'   \code{read_round_info()}, a character vector of survey IDs, or \code{NULL}
#'   for the first round.
#' @param uuid_column,skip_label_row As in \code{round_fingerprint()}.
#' @param tool_survey,tool_choices The XLSForm's survey and choices sheets.
#'   Default \code{NULL} carries over those from \code{previous}, if any.
#' @param logical_checklist The logical checklist used, if any. Default
#'   \code{NULL} carries over the one from \code{previous}.
#' @param settings A named list of single strings to keep with the round,
#'   for example an app's settings. Default \code{NULL} carries over those
#'   from \code{previous}.
#' @param checked_on Date of the round. Default today.
#'
#' @return An object of class \code{ck_round_info}.
#' @export
#' @examples
#' df <- data.frame(`_uuid` = c("a", "b"), Q1 = c("1", "2"), check.names = FALSE)
#' info <- ck_round_info(df, "R1", skip_label_row = FALSE)
#' info
ck_round_info <- function(
  dataset,
  round_name,
  previous = NULL,
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  tool_survey = NULL,
  tool_choices = NULL,
  logical_checklist = NULL,
  settings = NULL,
  checked_on = Sys.Date()
) {
  if (missing(round_name) || length(round_name) != 1 || is.na(round_name)) {
    stop("`round_name` must be a single string.", call. = FALSE)
  }
  round_name <- trimws(as.character(round_name))
  if (!nzchar(round_name)) {
    stop("`round_name` must not be empty.", call. = FALSE)
  }
  previous <- .as_round_info(previous)
  checked_on <- format(as.Date(checked_on), "%Y-%m-%d")
  round_id <- paste0(
    format(Sys.time(), "%Y%m%d%H%M%S"),
    "-",
    # tempfile() names are random without touching the user's RNG seed
    substr(sub("^file", "", basename(tempfile())), 1, 8)
  )

  fp <- round_fingerprint(dataset, uuid_column, skip_label_row)
  fp <- fp[nzchar(fp$uuid) & !is.na(fp$uuid), , drop = FALSE]
  fp <- fp[!duplicated(fp$uuid), , drop = FALSE]
  this_round <- data.frame(
    uuid = fp$uuid,
    round_name = rep(round_name, nrow(fp)),
    round_id = rep(round_id, nrow(fp)),
    checked_on = rep(checked_on, nrow(fp)),
    fingerprint = fp$fingerprint,
    stringsAsFactors = FALSE
  )
  earlier <- previous$checked
  earlier <- earlier[!earlier$uuid %in% this_round$uuid, , drop = FALSE]

  .new_round_info(
    meta = list(
      format_version = .round_format_version,
      round_name = round_name,
      round_id = round_id,
      checked_on = checked_on,
      created = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6"),
      cleaningkit_version = as.character(utils::packageVersion("cleaningkit")),
      uuid_column = uuid_column,
      skip_label_row = as.character(isTRUE(skip_label_row))
    ),
    checked = rbind(earlier, this_round),
    fingerprint_columns = attr(fp, "columns"),
    settings = settings %or% previous$settings,
    tool_survey = tool_survey %or% previous$tool_survey,
    tool_choices = tool_choices %or% previous$tool_choices,
    logical_checklist = logical_checklist %or% previous$logical_checklist,
    sources = previous$sources
  )
}

#' Read what earlier rounds checked
#'
#' Reads the round memory from one or more files and combines it. Accepted:
#' \itemize{
#'   \item a review or final workbook made with \code{round_info}, edited or
#'     not: everything (survey IDs, fingerprints, questionnaire, settings);
#'   \item the \code{processed_uuids.csv} ledger of
#'     \code{filter_new_records()}: survey IDs;
#'   \item an earlier export or \code{data.xlsx} (any workbook whose first
#'     sheet has the survey ID column): survey IDs.
#' }
#' Every survey ID from every file counts as checked, so uploading more files
#' than needed is always safe. The newest workbook (by the date its round was
#' checked) supplies the round details, questionnaire and settings.
#'
#' @param paths Paths to the files.
#' @param uuid_column Survey ID column of an earlier export. Default
#'   \code{"_uuid"}.
#' @param skip_label_row Whether an earlier export has the ONA label row.
#'   Default \code{TRUE}.
#' @param names Display names for the files, e.g. the names of uploaded files
#'   whose \code{paths} are temporary. Default \code{basename(paths)}.
#'
#' @return A \code{ck_round_info}. Its \code{sources} element lists each file
#'   with what was found in it.
#' @export
read_round_info <- function(
  paths,
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  names = basename(paths)
) {
  if (length(paths) == 0) {
    stop("No files given.", call. = FALSE)
  }
  infos <- lapply(seq_along(paths), function(i) {
    .read_one_round_file(paths[i], names[i], uuid_column, skip_label_row)
  })
  .merge_round_infos(infos)
}

#' Keep only the surveys not checked in earlier rounds
#'
#' The in-memory counterpart of \code{filter_new_records()}: no folder, no
#' files moved. Give it the new ONA download and what earlier rounds checked.
#'
#' @param dataset The new ONA download.
#' @param previous A \code{ck_round_info} (from \code{read_round_info()}), a
#'   character vector of survey IDs, or \code{NULL} for the first round.
#' @param uuid_column,skip_label_row As in \code{round_fingerprint()}.
#'
#' @return A list with \code{data} (the new surveys, ONA label row kept as row
#'   one), \code{n_total}, \code{n_checked_before} and \code{n_new}.
#' @export
#' @examples
#' df <- data.frame(`_uuid` = c("a", "b", "c"), check.names = FALSE)
#' keep_new_records(df, previous = "a", skip_label_row = FALSE)$n_new
keep_new_records <- function(
  dataset,
  previous = NULL,
  uuid_column = "_uuid",
  skip_label_row = TRUE
) {
  dataset <- as.data.frame(
    dataset,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  if (!uuid_column %in% names(dataset)) {
    stop(
      "The dataset has no `",
      uuid_column,
      "` column, so its surveys can't be told apart.",
      call. = FALSE
    )
  }
  checked <- .as_round_info(previous)$checked$uuid
  has_label <- isTRUE(skip_label_row) && nrow(dataset) > 0
  body_rows <- if (has_label) {
    seq_len(nrow(dataset))[-1]
  } else {
    seq_len(nrow(dataset))
  }
  ids <- trimws(as.character(dataset[[uuid_column]][body_rows]))
  keep <- !(ids %in% checked)
  rows <- c(if (has_label) 1L, body_rows[keep])
  list(
    data = dataset[rows, , drop = FALSE],
    n_total = length(body_rows),
    n_checked_before = sum(!keep),
    n_new = sum(keep)
  )
}

#' The surveys of the last round, from any later download
#'
#' For applying corrections: picks the surveys of the round a workbook was
#' made for out of an ONA download (the one that was checked, or any later
#' one, since each holds everything collected so far), and compares their
#' fingerprints with those taken when the round was checked.
#'
#' @param dataset An ONA download.
#' @param round_info A \code{ck_round_info} from \code{read_round_info()}.
#' @param uuid_column,skip_label_row As in \code{round_fingerprint()}.
#'
#' @return A list with \code{data} (the round's surveys, label row kept),
#'   \code{missing} (survey IDs of the round not in \code{dataset}),
#'   \code{changed} (survey IDs whose answers differ from when they were
#'   checked) and \code{n_round}.
#' @export
round_records <- function(
  dataset,
  round_info,
  uuid_column = "_uuid",
  skip_label_row = TRUE
) {
  info <- .as_round_info(round_info)
  round_id <- info$meta$round_id
  if (is.null(round_id)) {
    stop(
      "These files don't say which surveys were in the round: they hold ",
      "survey IDs only. Upload the review or final workbook of the round.",
      call. = FALSE
    )
  }
  ours <- info$checked[info$checked$round_id %in% round_id, , drop = FALSE]
  dataset <- as.data.frame(
    dataset,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  if (!uuid_column %in% names(dataset)) {
    stop("The dataset has no `", uuid_column, "` column.", call. = FALSE)
  }
  has_label <- isTRUE(skip_label_row) && nrow(dataset) > 0
  body_rows <- if (has_label) {
    seq_len(nrow(dataset))[-1]
  } else {
    seq_len(nrow(dataset))
  }
  ids <- trimws(as.character(dataset[[uuid_column]][body_rows]))
  hit <- body_rows[ids %in% ours$uuid & !duplicated(ids)]
  data <- dataset[c(if (has_label) 1L, hit), , drop = FALSE]

  fp <- round_fingerprint(
    data,
    uuid_column,
    skip_label_row,
    columns = info$fingerprint_columns
  )
  then <- stats::setNames(ours$fingerprint, ours$uuid)
  differs <- !is.na(then[fp$uuid]) &
    nzchar(then[fp$uuid]) &
    then[fp$uuid] != fp$fingerprint
  list(
    data = data,
    missing = setdiff(ours$uuid, fp$uuid),
    changed = fp$uuid[differs],
    n_round = nrow(ours)
  )
}

#' @export
print.ck_round_info <- function(x, ...) {
  m <- x$meta
  cat("<ck_round_info>\n")
  if (!is.null(m$round_name)) {
    cat(
      "  Round:        ",
      m$round_name,
      " (checked ",
      m$checked_on,
      ")\n",
      sep = ""
    )
    cat(
      "  In this round:",
      sum(x$checked$round_id == m$round_id),
      "survey(s)\n"
    )
  }
  cat("  Checked so far:", length(unique(x$checked$uuid)), "survey(s)\n")
  cat(
    "  Questionnaire:",
    if (is.null(x$tool_survey)) "no" else paste(nrow(x$tool_survey), "rows"),
    "\n"
  )
  invisible(x)
}

# ---- internals --------------------------------------------------------------

`%or%` <- function(a, b) if (is.null(a)) b else a

.new_round_info <- function(
  meta = list(),
  checked = NULL,
  fingerprint_columns = character(0),
  settings = NULL,
  tool_survey = NULL,
  tool_choices = NULL,
  logical_checklist = NULL,
  sources = NULL
) {
  if (is.null(checked)) {
    checked <- data.frame(
      uuid = character(0),
      round_name = character(0),
      round_id = character(0),
      checked_on = character(0),
      fingerprint = character(0),
      stringsAsFactors = FALSE
    )
  }
  structure(
    list(
      meta = meta,
      checked = checked,
      fingerprint_columns = fingerprint_columns,
      settings = settings,
      tool_survey = tool_survey,
      tool_choices = tool_choices,
      logical_checklist = logical_checklist,
      sources = sources
    ),
    class = "ck_round_info"
  )
}

.as_round_info <- function(x) {
  if (is.null(x)) {
    return(.new_round_info())
  }
  if (inherits(x, "ck_round_info")) {
    return(x)
  }
  if (is.character(x)) {
    ids <- unique(trimws(x[!is.na(x)]))
    ids <- ids[nzchar(ids)]
    return(.new_round_info(
      checked = data.frame(
        uuid = ids,
        round_name = rep("earlier rounds", length(ids)),
        round_id = rep(NA_character_, length(ids)),
        checked_on = rep(NA_character_, length(ids)),
        fingerprint = rep(NA_character_, length(ids)),
        stringsAsFactors = FALSE
      )
    ))
  }
  stop(
    "`previous` must be a ck_round_info, a vector of survey IDs or NULL.",
    call. = FALSE
  )
}

.round_body <- function(dataset, uuid_column, skip_label_row) {
  dataset <- as.data.frame(
    dataset,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  if (!uuid_column %in% names(dataset)) {
    stop("The dataset has no `", uuid_column, "` column.", call. = FALSE)
  }
  if (isTRUE(skip_label_row) && nrow(dataset) > 0) {
    dataset <- dataset[-1, , drop = FALSE]
  }
  dataset
}

# Character table, every column as text, for writing.
.as_text_table <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
  df[] <- lapply(df, function(v) {
    v <- as.character(v)
    v[is.na(v)] <- ""
    v
  })
  df
}

#' Write the round memory into a workbook as very hidden sheets
#'
#' @param wb An openxlsx workbook.
#' @param round_info A \code{ck_round_info}.
#' @return The workbook, invisibly.
#' @noRd
.ck_write_round_sheets <- function(wb, round_info) {
  if (is.null(round_info)) {
    return(invisible(wb))
  }
  if (!inherits(round_info, "ck_round_info")) {
    stop("`round_info` must come from ck_round_info().", call. = FALSE)
  }
  add <- function(key, df) {
    sheet <- .round_sheets[[key]]
    if (sheet %in% names(wb)) {
      openxlsx::removeWorksheet(wb, sheet)
    }
    openxlsx::addWorksheet(wb, sheet, visible = "veryHidden")
    openxlsx::writeData(wb, sheet, .as_text_table(df), rowNames = FALSE)
  }

  meta <- round_info$meta
  add(
    "round",
    data.frame(
      key = c(
        names(meta),
        rep("fingerprint_column", length(round_info$fingerprint_columns))
      ),
      value = c(
        unlist(meta, use.names = FALSE),
        round_info$fingerprint_columns
      ),
      stringsAsFactors = FALSE
    )
  )
  add("checked", round_info$checked)

  settings <- round_info$settings
  if (length(settings) > 0) {
    rows <- lapply(names(settings), function(key) {
      value <- paste(as.character(settings[[key]]), collapse = "\n")
      starts <- seq(1L, max(1L, nchar(value)), by = .round_cell_limit)
      parts <- substring(value, starts, starts + .round_cell_limit - 1L)
      data.frame(
        key = key,
        part = seq_along(parts),
        value = parts,
        stringsAsFactors = FALSE
      )
    })
    add("settings", do.call(rbind, rows))
  }
  if (!is.null(round_info$tool_survey)) {
    add("survey", round_info$tool_survey)
  }
  if (!is.null(round_info$tool_choices)) {
    add("choices", round_info$tool_choices)
  }
  if (!is.null(round_info$logical_checklist)) {
    add("checklist", round_info$logical_checklist)
  }
  invisible(wb)
}

.read_text_sheet <- function(path, sheet) {
  out <- readxl::read_excel(path, sheet = sheet, col_types = "text")
  out <- as.data.frame(out, stringsAsFactors = FALSE, check.names = FALSE)
  out[] <- lapply(out, function(v) {
    v[is.na(v)] <- ""
    v
  })
  out
}

.read_one_round_file <- function(path, name, uuid_column, skip_label_row) {
  if (!file.exists(path)) {
    stop("File not found: ", name, call. = FALSE)
  }
  source_row <- function(type, info, note = "") {
    data.frame(
      file = name,
      type = type,
      round_name = info$meta$round_name %or% NA_character_,
      checked_on = info$meta$checked_on %or% NA_character_,
      n_surveys = length(unique(info$checked$uuid)),
      note = note,
      stringsAsFactors = FALSE
    )
  }

  if (
    grepl("[.]csv$", path, ignore.case = TRUE) ||
      grepl("[.]csv$", name, ignore.case = TRUE)
  ) {
    ledger <- .read_uuid_ledger(path)
    if (nrow(ledger) == 0) {
      stop(name, " has no `uuid` column, or it is empty.", call. = FALSE)
    }
    info <- .new_round_info(
      checked = data.frame(
        uuid = ledger$uuid,
        round_name = rep("earlier rounds (ledger)", nrow(ledger)),
        round_id = rep(NA_character_, nrow(ledger)),
        checked_on = as.character(ledger$date_added),
        fingerprint = rep(NA_character_, nrow(ledger)),
        stringsAsFactors = FALSE
      )
    )
    info$sources <- source_row("ledger", info)
    return(info)
  }

  sheets <- tryCatch(readxl::excel_sheets(path), error = function(e) {
    stop(
      name,
      " is not a CSV or Excel file the package can read.",
      call. = FALSE
    )
  })

  if (
    .round_sheets[["checked"]] %in%
      sheets &&
      .round_sheets[["round"]] %in% sheets
  ) {
    kv <- .read_text_sheet(path, .round_sheets[["round"]])
    fp_cols <- kv$value[kv$key == "fingerprint_column"]
    kv <- kv[kv$key != "fingerprint_column", , drop = FALSE]
    meta <- as.list(stats::setNames(kv$value, kv$key))
    checked <- .read_text_sheet(path, .round_sheets[["checked"]])
    checked[checked == ""] <- NA_character_
    settings <- NULL
    if (.round_sheets[["settings"]] %in% sheets) {
      st <- .read_text_sheet(path, .round_sheets[["settings"]])
      st <- st[order(st$key, as.integer(st$part)), , drop = FALSE]
      settings <- lapply(split(st$value, st$key), paste, collapse = "")
    }
    opt <- function(key) {
      if (.round_sheets[[key]] %in% sheets) {
        .read_text_sheet(path, .round_sheets[[key]])
      }
    }
    info <- .new_round_info(
      meta = meta,
      checked = checked,
      fingerprint_columns = fp_cols,
      settings = settings,
      tool_survey = opt("survey"),
      tool_choices = opt("choices"),
      logical_checklist = opt("checklist")
    )
    info$sources <- source_row("workbook", info)
    return(info)
  }

  # An earlier export or data.xlsx: the survey IDs of its first sheet.
  df <- .read_data_export(path, sheet = 1)
  if (!uuid_column %in% names(df)) {
    stop(
      name,
      " has no round memory and no `",
      uuid_column,
      "` column on its first sheet, so it can't say which surveys were ",
      "checked. Upload the review or final workbook of the last round.",
      call. = FALSE
    )
  }
  ids <- df[[uuid_column]]
  if (isTRUE(skip_label_row) && length(ids) > 0) {
    ids <- ids[-1]
  }
  info <- .as_round_info(as.character(ids))
  info$checked$round_name <- rep(name, nrow(info$checked))
  info$sources <- source_row(
    "export",
    info,
    "survey IDs only: no questionnaire or settings"
  )
  info
}

.merge_round_infos <- function(infos) {
  sources <- do.call(rbind, lapply(infos, `[[`, "sources"))
  checked <- do.call(rbind, lapply(infos, `[[`, "checked"))
  # The first time a survey was checked wins.
  ord <- order(is.na(checked$checked_on), checked$checked_on)
  checked <- checked[ord, , drop = FALSE]
  checked <- checked[!duplicated(checked$uuid), , drop = FALSE]
  rownames(checked) <- NULL

  # The newest workbook gives the round details; the newest one holding each
  # optional part supplies it.
  dated <- Filter(function(i) !is.null(i$meta$round_id), infos)
  dated <- dated[order(vapply(
    dated,
    # ties (rounds made in the same instant) keep the order the files were given
    function(i) i$meta$created %or% i$meta$checked_on,
    character(1)
  ))]
  newest <- if (length(dated)) dated[[length(dated)]] else NULL
  latest_with <- function(part) {
    for (i in rev(dated)) {
      if (!is.null(i[[part]])) return(i[[part]])
    }
    NULL
  }
  # The newest round's own surveys keep its fingerprints even when an older
  # file listed them first (it can't: a survey is checked in one round).
  if (!is.null(newest)) {
    mine <- newest$checked[
      newest$checked$round_id %in% newest$meta$round_id,
      ,
      drop = FALSE
    ]
    checked <- rbind(
      checked[!checked$uuid %in% mine$uuid, , drop = FALSE],
      mine
    )
  }

  .new_round_info(
    meta = newest$meta %or% list(),
    checked = checked,
    fingerprint_columns = newest$fingerprint_columns %or% character(0),
    settings = latest_with("settings"),
    tool_survey = latest_with("tool_survey"),
    tool_choices = latest_with("tool_choices"),
    logical_checklist = latest_with("logical_checklist"),
    sources = sources
  )
}
