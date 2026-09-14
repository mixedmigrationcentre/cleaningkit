#' Read a raw export as plain text
#'
#' Thin wrapper around \code{readxl::read_excel()} that keeps every cell as text
#' and preserves the original column names (including the leading underscore of
#' ONA metadata columns such as \code{_uuid}).
#'
#' @param path Path to the Excel file.
#' @param sheet Sheet number or name.
#'
#' @return A base data frame with all columns of type character.
#' @noRd
.read_data_export <- function(path, sheet = 1) {
  df <- readxl::read_excel(path, sheet = sheet, col_types = "text")
  as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
}

#' Normalise a vector of uuids
#'
#' Trims whitespace and drops missing / empty values so that uuids coming from
#' different exports compare reliably.
#'
#' @param x Character vector of uuids.
#'
#' @return Character vector of cleaned, unique uuids.
#' @noRd
.clean_uuids <- function(x) {
  x <- trimws(as.character(x))
  x <- x[!is.na(x) & x != ""]
  unique(x)
}

#' Read the processed-uuid ledger
#'
#' Reads the running record of every uuid that has already been through a
#' validation round. A missing, empty or malformed ledger returns an empty
#' ledger rather than an error, so a lost file simply degrades to the two-file
#' comparison instead of breaking the pipeline.
#'
#' @param path Path to the ledger csv.
#'
#' @return A data frame with columns \code{uuid} and \code{date_added}.
#' @noRd
.read_uuid_ledger <- function(path) {
  empty <- data.frame(
    uuid = character(0),
    date_added = character(0),
    stringsAsFactors = FALSE
  )

  if (!file.exists(path)) {
    return(empty)
  }

  ledger <- try(
    utils::read.csv(
      path,
      colClasses = "character",
      stringsAsFactors = FALSE,
      check.names = FALSE
    ),
    silent = TRUE
  )

  if (inherits(ledger, "try-error") || !("uuid" %in% names(ledger))) {
    warning(
      "Could not read a 'uuid' column from the ledger at ",
      path,
      "; it will be ignored and rebuilt."
    )
    return(empty)
  }

  if (!("date_added" %in% names(ledger))) {
    ledger$date_added <- NA_character_
  }

  ledger <- ledger[, c("uuid", "date_added"), drop = FALSE]
  ledger$uuid <- trimws(as.character(ledger$uuid))
  ledger <- ledger[!is.na(ledger$uuid) & ledger$uuid != "", , drop = FALSE]
  ledger[!duplicated(ledger$uuid), , drop = FALSE]
}

#' Keep Only Newly Collected Records Before a Validation Round
#'
#' Prepares the \code{data/} folder for a fresh validation round by reducing a
#' cumulative ONA export down to the records that have not been validated yet.
#' Data collection for a 4Mi round typically runs over several weeks while
#' validation runs twice a week, and every ONA download contains the whole
#' dataset collected so far. Running the \code{validate_*} functions on the full
#' download regenerates cleaning log entries for surveys that were already
#' reviewed in earlier rounds. This function removes that duplication so each
#' follow-up workbook only contains genuinely new issues.
#'
#' @details
#' The function expects the \code{data/} folder to hold the freshly downloaded
#' ONA export plus the file left behind by the previous round (at most two
#' Excel files). The file with more records is treated as the new export, the
#' other as the previous round. Every uuid found in the previous file - and in
#' the processed-uuid ledger, see below - is removed from the new export, and
#' the remaining records are written to \code{data.xlsx}. The two input files
#' are then archived (or deleted).
#'
#' \strong{The ledger.} Because the file left behind is itself already filtered,
#' comparing two files alone would only ever exclude the most recent round. From
#' the third round onwards records from round one would silently return. To
#' prevent this, the function maintains \code{processed_uuids.csv} in the same
#' folder, listing every uuid that has already been through validation. Each run
#' filters against the ledger \emph{and} the previous file, then appends whatever
#' it processed. The csv is ignored when the function looks for input files, so
#' it can live in \code{data/} without interfering. If the ledger is deleted or
#' unreadable the function falls back to the plain two-file comparison and says
#' so.
#'
#' \strong{Safety.} Nothing is removed until the filtered output has been built
#' successfully, and nothing is removed at all if the filtering leaves zero new
#' records - that usually means the same export was downloaded twice. With
#' \code{archive = TRUE} (the default) the inputs are moved to
#' \code{data/archive/} under a timestamped name rather than deleted, so a round
#' can be redone if something goes wrong.
#'
#' The ONA label/description row of the new export is preserved as row one of
#' the output, so \code{read_raw_data()} and the \code{validate_*} functions can
#' keep their default \code{skip_label_row = TRUE}.
#'
#' @param data_folder Path to the folder holding the raw exports. Default
#'   \code{"./data"}, the folder created by \code{setup_project_folders()}.
#' @param uuid_column Name of the unique survey identifier column. Default
#'   \code{"_uuid"}, the standard ONA export column.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of
#'   each file is treated as the ONA label/description row rather than a survey.
#'   It is excluded from the record counts and from the uuid comparison, and the
#'   label row of the new export is written back as row one of the output.
#' @param output_name Name of the filtered file written to \code{data_folder}.
#'   Default \code{"data.xlsx"}, the file name used by the example pipeline.
#' @param sheet Sheet number or name to read from each Excel file. Default
#'   \code{1}.
#' @param use_ledger Logical. If \code{TRUE} (the default), previously processed
#'   uuids are also read from, and written back to, the ledger csv. Set to
#'   \code{FALSE} for a plain comparison of the two files in the folder.
#' @param ledger_name File name of the processed-uuid ledger inside
#'   \code{data_folder}. Default \code{"processed_uuids.csv"}.
#' @param archive Logical. If \code{TRUE} (the default), the input files are
#'   copied into \code{archive_folder} with a timestamp prefix before being
#'   removed from \code{data_folder}. If \code{FALSE} they are deleted outright.
#' @param archive_folder Name of the archive sub-folder inside
#'   \code{data_folder}. Default \code{"archive"}. Created if it does not exist.
#' @param verbose Logical. If \code{TRUE} (the default), progress messages are
#'   printed showing how many records were read, dropped and kept.
#'
#' @return Invisibly, a list with:
#' \describe{
#'   \item{\code{data}}{The filtered dataset as written, label row included.}
#'   \item{\code{output_path}}{Path of the written file.}
#'   \item{\code{new_export}}{File name treated as the new ONA export.}
#'   \item{\code{previous_file}}{File name treated as the previous round, or
#'     \code{NA} if the ledger alone was used.}
#'   \item{\code{n_new_export}}{Records in the new export, label row excluded.}
#'   \item{\code{n_previous}}{Records in the previous file, label row excluded.}
#'   \item{\code{n_dropped}}{Records removed as already validated.}
#'   \item{\code{n_kept}}{Records written to the output.}
#'   \item{\code{archived_files}}{Paths of the archived copies, empty when
#'     \code{archive = FALSE}.}
#'   \item{\code{ledger_path}}{Path of the ledger, or \code{NA} when
#'     \code{use_ledger = FALSE}.}
#' }
#'
#' @examples
#' \dontrun{
#' # Drop the new ONA download next to the previous round's file in ./data,
#' # then reduce it to the records collected since the last validation round
#' filter_new_records(
#'   data_folder = "./data",
#'   uuid_column = "_uuid",
#'   skip_label_row = TRUE
#' )
#'
#' # ./data now holds data.xlsx (new records only), processed_uuids.csv
#' # and archive/ with the two inputs
#' raw_data <- read_raw_data(
#'   filename = "./data/data.xlsx",
#'   tool_survey = tool_survey
#' )
#' }
#'
#' @export
filter_new_records <- function(
  data_folder = "./data",
  uuid_column = "_uuid",
  skip_label_row = TRUE,
  output_name = "data.xlsx",
  sheet = 1,
  use_ledger = TRUE,
  ledger_name = "processed_uuids.csv",
  archive = TRUE,
  archive_folder = "archive",
  verbose = TRUE
) {
  # ---- argument checks ----
  if (
    !is.character(data_folder) ||
      length(data_folder) != 1 ||
      is.na(data_folder) ||
      !nzchar(data_folder)
  ) {
    stop("`data_folder` must be a single, non-empty character string.")
  }
  if (!dir.exists(data_folder)) {
    stop(
      "`data_folder` does not exist: ",
      data_folder,
      ". Run setup_project_folders() first."
    )
  }
  if (
    !is.character(uuid_column) ||
      length(uuid_column) != 1 ||
      is.na(uuid_column) ||
      !nzchar(uuid_column)
  ) {
    stop("`uuid_column` must be a single, non-empty character string.")
  }
  if (
    !is.character(output_name) ||
      length(output_name) != 1 ||
      !grepl("\\.xlsx$", output_name, ignore.case = TRUE)
  ) {
    stop("`output_name` must be a single file name ending in \".xlsx\".")
  }
  if (length(sheet) != 1) {
    stop("`sheet` must be a single sheet number or sheet name.")
  }
  if (!is.logical(skip_label_row) || length(skip_label_row) != 1) {
    stop("`skip_label_row` must be TRUE or FALSE.")
  }
  if (!is.logical(use_ledger) || length(use_ledger) != 1) {
    stop("`use_ledger` must be TRUE or FALSE.")
  }
  if (!is.logical(archive) || length(archive) != 1) {
    stop("`archive` must be TRUE or FALSE.")
  }

  ledger_path <- file.path(data_folder, ledger_name)
  archive_path <- file.path(data_folder, archive_folder)
  output_path <- file.path(data_folder, output_name)

  # ---- locate the input exports ----
  input_files <- list.files(
    data_folder,
    pattern = "\\.xlsx$|\\.xls$",
    ignore.case = TRUE,
    recursive = FALSE
  )
  # drop the temporary lock files Excel leaves behind while a workbook is open
  input_files <- input_files[!grepl("^~\\$", input_files)]

  if (length(input_files) == 0) {
    stop(
      "No Excel files found in ",
      data_folder,
      ". Place the new ONA export (and the previous round's file) there first."
    )
  }
  if (length(input_files) > 2) {
    stop(
      "Expected at most 2 Excel files in ",
      data_folder,
      " (the new ONA export and the previous round's file), found ",
      length(input_files),
      ": ",
      paste(input_files, collapse = ", "),
      ". Move the extras out of the folder and run again."
    )
  }

  input_paths <- file.path(data_folder, input_files)

  if (verbose) {
    cat(crayon::green(paste0(
      "--> FILTER --> reading ",
      length(input_files),
      " file(s) from ",
      data_folder,
      "\n"
    )))
  }

  datasets <- lapply(input_paths, .read_data_export, sheet = sheet)
  names(datasets) <- input_files

  for (i in seq_along(datasets)) {
    if (!uuid_column %in% names(datasets[[i]])) {
      stop(
        "Column \"",
        uuid_column,
        "\" not found in ",
        input_files[i],
        ". Available columns include: ",
        paste(utils::head(names(datasets[[i]]), 10), collapse = ", "),
        "..."
      )
    }
  }

  # ---- record counts, label row excluded ----
  n_records <- vapply(
    datasets,
    function(d) {
      n <- nrow(d)
      if (skip_label_row && n > 0) {
        n <- n - 1
      }
      as.numeric(n)
    },
    numeric(1)
  )

  # ---- decide which file is the new export ----
  if (length(input_files) == 2) {
    if (n_records[1] == n_records[2]) {
      new_idx <- which.max(file.mtime(input_paths))
      warning(
        "Both files hold ",
        n_records[1],
        " records; using the most recently modified file (",
        input_files[new_idx],
        ") as the new export."
      )
    } else {
      new_idx <- which.max(n_records)
    }
    prev_idx <- setdiff(seq_along(input_files), new_idx)
  } else {
    new_idx <- 1L
    prev_idx <- integer(0)
    if (!use_ledger || !file.exists(ledger_path)) {
      stop(
        "Only one Excel file found in ",
        data_folder,
        " (",
        input_files,
        ") and no usable ledger at ",
        ledger_path,
        ". Add the previous round's file to the folder, or set use_ledger = TRUE",
        " once a ledger exists."
      )
    }
    if (verbose) {
      cat(crayon::yellow(paste0(
        "--> only one export found; filtering against the ledger alone\n"
      )))
    }
  }

  # ---- split the label row off the new export ----
  new_data <- datasets[[new_idx]]
  label_row <- NULL
  if (skip_label_row && nrow(new_data) > 0) {
    label_row <- new_data[1, , drop = FALSE]
    new_data <- new_data[-1, , drop = FALSE]
  }

  new_uuids <- trimws(as.character(new_data[[uuid_column]]))
  n_missing_uuid <- sum(is.na(new_uuids) | new_uuids == "")
  if (n_missing_uuid > 0) {
    warning(
      n_missing_uuid,
      " record(s) in ",
      input_files[new_idx],
      " have no ",
      uuid_column,
      "; they cannot be matched and are kept in the output."
    )
  }

  # ---- collect everything already validated ----
  previous_uuids <- character(0)
  n_previous <- 0
  if (length(prev_idx) == 1) {
    prev_data <- datasets[[prev_idx]]
    if (skip_label_row && nrow(prev_data) > 0) {
      prev_data <- prev_data[-1, , drop = FALSE]
    }
    previous_uuids <- .clean_uuids(prev_data[[uuid_column]])
    n_previous <- nrow(prev_data)
  }

  ledger <- NULL
  ledger_uuids <- character(0)
  if (use_ledger) {
    ledger <- .read_uuid_ledger(ledger_path)
    ledger_uuids <- ledger$uuid
  }

  seen_uuids <- unique(c(previous_uuids, ledger_uuids))

  # ---- filter ----
  keep <- !(new_uuids %in% seen_uuids)
  keep[is.na(new_uuids) | new_uuids == ""] <- TRUE

  n_kept <- sum(keep)
  n_dropped <- sum(!keep)

  if (verbose) {
    cat(crayon::green(paste0(
      "--> NEW EXPORT --> ",
      input_files[new_idx],
      " --> ",
      n_records[new_idx],
      " records \n"
    )))
    if (length(prev_idx) == 1) {
      cat(crayon::green(paste0(
        "--> PREVIOUS   --> ",
        input_files[prev_idx],
        " --> ",
        n_records[prev_idx],
        " records \n"
      )))
    }
    cat(crayon::green(paste0(
      "--> LEDGER     --> ",
      if (use_ledger) length(ledger_uuids) else 0,
      " uuid(s) already validated \n"
    )))
  }

  if (n_kept == 0) {
    stop(
      "No new records found in ",
      input_files[new_idx],
      ": all ",
      n_dropped,
      " uuid(s) were already validated. Nothing was written, archived or",
      " deleted - check that the latest ONA export was downloaded."
    )
  }

  filtered <- new_data[keep, , drop = FALSE]
  if (!is.null(label_row)) {
    filtered <- rbind(label_row, filtered)
  }
  rownames(filtered) <- NULL

  # ---- build the output before touching anything on disk ----
  tmp_path <- file.path(tempdir(), output_name)
  openxlsx::write.xlsx(filtered, file = tmp_path, overwrite = TRUE)
  if (!file.exists(tmp_path)) {
    stop(
      "Could not build the filtered output; no files were archived or deleted."
    )
  }

  # ---- archive, then remove, the inputs ----
  archived_files <- character(0)
  if (archive) {
    if (!dir.exists(archive_path)) {
      dir.create(archive_path, recursive = TRUE, showWarnings = FALSE)
    }
    if (!dir.exists(archive_path)) {
      stop(
        "Could not create the archive folder: ",
        archive_path,
        ". No files were removed."
      )
    }
    stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    for (i in seq_along(input_files)) {
      destination <- file.path(
        archive_path,
        paste0(stamp, "_", input_files[i])
      )
      copied <- file.copy(input_paths[i], destination, overwrite = TRUE)
      if (!copied) {
        stop(
          "Could not archive ",
          input_files[i],
          " to ",
          archive_path,
          ". No files were removed."
        )
      }
      archived_files <- c(archived_files, destination)
    }
  }

  removed <- suppressWarnings(file.remove(input_paths))
  if (!all(removed)) {
    warning(
      "Could not remove: ",
      paste(input_files[!removed], collapse = ", "),
      ". Delete the file(s) manually before the next round, or the folder will",
      " hold more than two exports."
    )
  }

  # ---- write the filtered file into the data folder ----
  written <- file.copy(tmp_path, output_path, overwrite = TRUE)
  unlink(tmp_path)
  if (!written) {
    stop(
      "Could not write ",
      output_path,
      ". The input files are ",
      if (archive) {
        paste0("still available in ", archive_path, ".")
      } else {
        "gone - restore them from ONA."
      }
    )
  }

  # ---- update the ledger ----
  if (use_ledger) {
    processed <- unique(c(previous_uuids, .clean_uuids(new_uuids)))
    to_add <- setdiff(processed, ledger$uuid)
    if (length(to_add) > 0) {
      ledger <- rbind(
        ledger,
        data.frame(
          uuid = to_add,
          date_added = format(Sys.Date()),
          stringsAsFactors = FALSE
        )
      )
    }
    utils::write.csv(ledger, ledger_path, row.names = FALSE, na = "")
  }

  # ---- summary ----
  if (verbose) {
    cat(crayon::yellow(paste0(
      "--> dropped ",
      n_dropped,
      " already validated record(s) \n"
    )))
    cat(crayon::green(paste0(
      "--> FILTERED --> ",
      output_path,
      " --> ",
      n_kept,
      " new record(s), ",
      ncol(filtered),
      " columns \n"
    )))
    if (archive) {
      cat(crayon::green(paste0(
        "--> archived ",
        length(archived_files),
        " input file(s) to ",
        archive_path,
        " \n"
      )))
    } else {
      cat(crayon::yellow(paste0(
        "--> deleted ",
        sum(removed),
        " input file(s) from ",
        data_folder,
        " \n"
      )))
    }
    if (use_ledger) {
      cat(crayon::green(paste0(
        "--> LEDGER   --> ",
        ledger_path,
        " --> ",
        nrow(ledger),
        " uuid(s) recorded \n"
      )))
    }
  }

  invisible(list(
    data = filtered,
    output_path = output_path,
    new_export = input_files[new_idx],
    previous_file = if (length(prev_idx) == 1) {
      input_files[prev_idx]
    } else {
      NA_character_
    },
    n_new_export = n_records[[new_idx]],
    n_previous = n_previous,
    n_dropped = n_dropped,
    n_kept = n_kept,
    archived_files = archived_files,
    ledger_path = if (use_ledger) ledger_path else NA_character_
  ))
}
