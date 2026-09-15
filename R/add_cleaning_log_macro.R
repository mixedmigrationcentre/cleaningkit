#' Places the compiled VBA project is looked for, in order
#'
#' Kept separate from \code{ck_vba_project_path()} so the "not found" error can
#' list exactly where it looked.
#'
#' @return Character vector of candidate paths.
#' @noRd
ck_vba_candidates <- function() {
  c(
    getOption("cleaningkit.vba_project", default = ""),
    Sys.getenv("CLEANINGKIT_VBA_PROJECT", unset = ""),
    tryCatch(
      system.file("extdata", "cleaningkit_vba.bin", package = "cleaningkit"),
      error = function(e) ""
    ),
    file.path("inst", "extdata", "cleaningkit_vba.bin"),
    file.path("resources", "cleaningkit_vba.bin"),
    file.path("functions", "cleaningkit_vba.bin"),
    file.path("dev", "cleaningkit_vba.bin"),
    "cleaningkit_vba.bin"
  )
}


#' Path to the compiled VBA project
#'
#' Locates \code{cleaningkit_vba.bin}, the compiled VBA project injected into
#' macro-enabled cleaning logs. Returns \code{""} when it cannot be found.
#'
#' @details
#' The search order is:
#' \enumerate{
#'   \item \code{getOption("cleaningkit.vba_project")};
#'   \item the \code{CLEANINGKIT_VBA_PROJECT} environment variable;
#'   \item \code{inst/extdata} of the installed package;
#'   \item \code{inst/extdata/}, \code{resources/}, \code{functions/},
#'     \code{dev/} and the working directory itself.
#' }
#'
#' Steps 1 and 4 exist because these functions are often sourced straight into
#' an analysis project rather than used from the installed package. In that
#' situation \code{system.file()} returns \code{""} - and it also returns
#' \code{""} when the package \emph{is} installed but was installed before the
#' binary was built, which is easy to miss. Dropping the \code{.bin} into the
#' project (\code{resources/} is a natural home) or setting the option in a
#' setup script both work:
#'
#' \preformatted{
#' options(cleaningkit.vba_project = "C:/path/to/cleaningkit_vba.bin")
#' }
#'
#' @return A file path, or \code{""} if the VBA project cannot be found.
#' @export
#'
#' @examples
#' \dontrun{
#' ck_vba_project_path()
#' }
ck_vba_project_path <- function() {
  candidates <- ck_vba_candidates()
  candidates <- candidates[nzchar(candidates)]
  hit <- candidates[file.exists(candidates)]
  if (length(hit) == 0) {
    return("")
  }
  normalizePath(hit[1], winslash = "/", mustWork = FALSE)
}


#' The "no VBA project" error message, listing where we looked
#'
#' @return A single string.
#' @noRd
ck_vba_missing_message <- function() {
  candidates <- ck_vba_candidates()
  shown <- candidates[nzchar(candidates)]
  paste0(
    "No VBA project found, so `create_cleaning_log_vba()` cannot run.\n",
    "Looked for `cleaningkit_vba.bin` in:\n",
    paste0("  - ", shown, collapse = "\n"),
    "\n\nFixes, easiest first:\n",
    "  * point at it directly:  create_cleaning_log_vba(..., vba_project = \"path/to/cleaningkit_vba.bin\")\n",
    "  * or set it once:        options(cleaningkit.vba_project = \"path/to/cleaningkit_vba.bin\")\n",
    "  * or copy the .bin into this project's `resources/` folder\n",
    "  * or reinstall cleaningkit so the built .bin ships with it\n",
    "    (system.file() also returns \"\" when the package was installed ",
    "before the binary was built)\n",
    "If it has never been built, run `dev/build_vba_bin.R` on a Windows machine ",
    "with Excel, or follow `inst/vba/README.md`.\n",
    "Use `create_cleaning_log()` for a plain .xlsx in the meantime."
  )
}


#' Configuration written to the hidden `_ck_config` sheet
#'
#' The VBA project reads every name it needs from this sheet rather than
#' hard-coding it, so one compiled \code{vbaProject.bin} serves every log the
#' package produces, whatever the sheet names or key columns happen to be.
#'
#' @param dataset_sheet Name of the editable raw-data sheet.
#' @param log_sheet Name of the cleaning log sheet.
#' @param uuid_column,date_column,enumerator_column Key columns in the dataset sheet.
#' @param issue_prefix Prefix used to build the per-edit \strong{Issue} values.
#' @param action_codes Character vector of valid action codes.
#' @param body_front Body font name.
#' @param body_front_size Body font size.
#' @param header_row,label_row,first_data_row Row layout of the dataset sheet.
#'
#' @return A two-column dataframe of key/value pairs.
#' @noRd
ck_macro_config_df <- function(
  dataset_sheet,
  log_sheet,
  uuid_column,
  date_column,
  enumerator_column,
  issue_prefix,
  action_codes,
  body_front,
  body_front_size,
  header_row = 1,
  label_row = 2,
  first_data_row = 3
) {
  data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    key = c(
      "dataset_sheet",
      "log_sheet",
      "uuid_column",
      "date_column",
      "enumerator_column",
      "issue_prefix",
      "action_codes",
      "action_recoded",
      "action_addition",
      "action_delete",
      "body_font",
      "body_font_size",
      "header_row",
      "label_row",
      "first_data_row"
    ),
    value = c(
      dataset_sheet,
      log_sheet,
      uuid_column,
      date_column,
      enumerator_column,
      issue_prefix,
      paste(action_codes, collapse = ","),
      "recoded",
      "addition",
      "delete_data_point",
      body_front,
      as.character(body_front_size),
      as.character(header_row),
      as.character(label_row),
      as.character(first_data_row)
    )
  )
}


#' Splice a `codeName` attribute into one worksheet part
#'
#' Worksheet XML can be tens of megabytes, and only its first few hundred bytes
#' need changing, so the file is patched by splicing the head and streaming the
#' remainder rather than reading it all into memory. Everything is done on raw
#' vectors, so no re-encoding can occur.
#'
#' Two shapes must be handled: openxlsx omits \code{<sheetPr>} entirely on most
#' sheets, but emits one whenever a tab colour is set. A naive "insert if absent"
#' patch silently skips the latter.
#'
#' @param path Path to the worksheet XML part.
#' @param code_name VBA code name to assign, e.g. \code{"Sheet1"}.
#'
#' @return \code{TRUE} if the file was changed, \code{FALSE} otherwise.
#' @noRd
ck_patch_sheet_codename <- function(path, code_name) {
  size <- file.info(path)$size
  head_n <- min(size, 8192)

  con <- file(path, "rb")
  head_raw <- readBin(con, "raw", n = head_n)

  ws_at <- grepRaw("<worksheet", head_raw, fixed = TRUE)
  if (length(ws_at) == 0) {
    close(con)
    return(FALSE)
  }
  ws_at <- ws_at[1]

  # end of the opening <worksheet ...> tag
  gt <- which(head_raw[ws_at:length(head_raw)] == as.raw(0x3E))
  if (length(gt) == 0) {
    close(con)
    return(FALSE)
  }
  ws_end <- ws_at + gt[1] - 1

  if (length(grepRaw("codeName=", head_raw, fixed = TRUE)) > 0) {
    close(con)
    return(FALSE)
  }

  pr_at <- grepRaw("<sheetPr", head_raw, fixed = TRUE)
  pr_at <- pr_at[pr_at > ws_end]

  if (length(pr_at) > 0 && pr_at[1] == ws_end + 1) {
    # A <sheetPr> already sits where it must (openxlsx emits one whenever a tab
    # colour is set): add the attribute to that element instead of a second one.
    split_at <- pr_at[1] + nchar("<sheetPr") - 1
    insert <- charToRaw(paste0(' codeName="', code_name, '"'))
  } else {
    split_at <- ws_end
    insert <- charToRaw(paste0('<sheetPr codeName="', code_name, '"/>'))
  }

  # hold only the head in memory; the body is streamed through in blocks
  rest_path <- tempfile("ck_ws_")
  rest_con <- file(rest_path, "wb")
  repeat {
    chunk <- readBin(con, "raw", n = 1048576L)
    if (length(chunk) == 0) {
      break
    }
    writeBin(chunk, rest_con)
  }
  close(rest_con)
  close(con)
  on.exit(unlink(rest_path, force = TRUE), add = TRUE)

  out <- file(path, "wb")
  writeBin(head_raw[seq_len(split_at)], out)
  writeBin(insert, out)
  if (split_at < length(head_raw)) {
    writeBin(head_raw[(split_at + 1):length(head_raw)], out)
  }
  if (file.info(rest_path)$size > 0) {
    rest_in <- file(rest_path, "rb")
    repeat {
      chunk <- readBin(rest_in, "raw", n = 1048576L)
      if (length(chunk) == 0) {
        break
      }
      writeBin(chunk, out)
    }
    close(rest_in)
  }
  close(out)

  TRUE
}


#' Worksheet parts, in the order the sheets appear in the workbook
#'
#' Resolves \code{<sheet r:id>} entries in \code{workbook.xml} through
#' \code{workbook.xml.rels}, so the Nth returned part really is the Nth sheet
#' rather than merely \code{sheetN.xml}.
#'
#' @param dir Unzipped package root.
#'
#' @return Character vector of paths, in sheet order.
#' @noRd
ck_sheet_parts_in_order <- function(dir) {
  wb_xml <- readChar(
    file.path(dir, "xl", "workbook.xml"),
    file.info(file.path(dir, "xl", "workbook.xml"))$size,
    useBytes = TRUE
  )
  rels_path <- file.path(dir, "xl", "_rels", "workbook.xml.rels")
  rels_xml <- readChar(rels_path, file.info(rels_path)$size, useBytes = TRUE)

  sheet_nodes <- regmatches(
    wb_xml,
    gregexpr("<sheet [^>]*/>", wb_xml, useBytes = TRUE)
  )[[1]]
  rids <- sub('.*r:id="([^"]+)".*', "\\1", sheet_nodes)

  rel_nodes <- regmatches(
    rels_xml,
    gregexpr("<Relationship [^>]*/>", rels_xml, useBytes = TRUE)
  )[[1]]
  rel_ids <- sub('.*Id="([^"]+)".*', "\\1", rel_nodes)
  rel_targets <- sub('.*Target="([^"]+)".*', "\\1", rel_nodes)

  targets <- rel_targets[match(rids, rel_ids)]
  targets <- targets[!is.na(targets)]
  targets <- sub("^/xl/", "", sub("^\\.\\./", "", targets))

  file.path(dir, "xl", targets)
}


#' Turn a saved .xlsx into a macro-enabled .xlsm
#'
#' Adds a pre-built VBA project to a workbook that openxlsx has already written,
#' by patching the OPC package directly.
#'
#' @details
#' openxlsx can carry a VBA project, but only half-way: \code{saveWorkbook()}
#' copies \code{wb$vbaProject} into the package, yet the content-type fix-up
#' happens only inside \code{loadWorkbook()}. Worse, \code{genBaseContent_Type()}
#' registers \code{<Default Extension="bin">} as \emph{printer settings}, so a
#' \code{vbaProject.bin} added without an explicit override is mis-typed and
#' Excel offers to repair the file. openxlsx also drops per-sheet VBA code names:
#' its \code{sheetPr} field is only ever populated from \code{tabColour}, and
#' \code{loadWorkbook()} never reads \code{sheetPr} back from the source.
#'
#' This function therefore does all five things the package needs:
#' \enumerate{
#'   \item rewrites the \code{workbook.xml} content type to
#'     \code{application/vnd.ms-excel.sheet.macroEnabled.main+xml} and adds an
#'     explicit override for \code{/xl/vbaProject.bin};
#'   \item adds the \code{vbaProject} relationship to \code{workbook.xml.rels};
#'   \item sets \code{codeName="ThisWorkbook"} on \code{<workbookPr>};
#'   \item sets \code{<sheetPr codeName="SheetN"/>} on every worksheet, in sheet
#'     order;
#'   \item drops the VBA project in and rezips.
#' }
#'
#' Because all of the macro's code lives in \code{ThisWorkbook} and a standard
#' module, and sheets are addressed by display name, the code names only have to
#' be present and unique - they are not referenced by the macro itself.
#'
#' @param xlsx_path Path to the \code{.xlsx} file to convert.
#' @param xlsm_path Path the macro-enabled workbook is written to.
#' @param vba_project Path to a \code{vbaProject.bin}. Defaults to the one
#'   shipped with the package.
#' @param overwrite Logical. Overwrite \code{xlsm_path} if it exists.
#'
#' @return \code{xlsm_path}, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' add_vba_project("log.xlsx", "log.xlsm")
#' }
add_vba_project <- function(
  xlsx_path,
  xlsm_path,
  vba_project = NULL,
  overwrite = TRUE
) {
  if (!file.exists(xlsx_path)) {
    stop(paste0("`xlsx_path` does not exist: ", xlsx_path))
  }
  if (is.null(vba_project)) {
    vba_project <- ck_vba_project_path()
  }
  if (!nzchar(vba_project) || !file.exists(vba_project)) {
    stop(ck_vba_missing_message(), call. = FALSE)
  }
  if (file.exists(xlsm_path) && !overwrite) {
    stop(paste0("File already exists: ", xlsm_path))
  }

  # Restore the working directory before anything else on exit: the rezip step
  # below has to setwd() into the temp tree, and on Windows a directory cannot
  # be removed while it is the working directory.
  wd <- getwd()
  on.exit(setwd(wd), add = TRUE, after = FALSE)

  tmp <- tempfile("ck_xlsm_")
  dir.create(tmp, recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
  out_tmp <- tempfile("ck_out_", fileext = ".xlsm")
  on.exit(unlink(out_tmp, force = TRUE), add = TRUE)

  utils::unzip(xlsx_path, exdir = tmp)

  # ---- 1. content types ----
  ct_path <- file.path(tmp, "[Content_Types].xml")
  ct <- readChar(ct_path, file.info(ct_path)$size, useBytes = TRUE)
  ct <- sub(
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
    "application/vnd.ms-excel.sheet.macroEnabled.main+xml",
    ct,
    fixed = TRUE
  )
  if (!grepl('PartName="/xl/vbaProject.bin"', ct, fixed = TRUE)) {
    ct <- sub(
      "</Types>",
      paste0(
        '<Override PartName="/xl/vbaProject.bin"',
        ' ContentType="application/vnd.ms-office.vbaProject"/></Types>'
      ),
      ct,
      fixed = TRUE
    )
  }
  writeChar(ct, ct_path, nchars = nchar(ct, type = "bytes"), eos = NULL, useBytes = TRUE)

  # ---- 2. workbook relationship ----
  rels_path <- file.path(tmp, "xl", "_rels", "workbook.xml.rels")
  rels <- readChar(rels_path, file.info(rels_path)$size, useBytes = TRUE)
  if (!grepl("vbaProject.bin", rels, fixed = TRUE)) {
    used <- as.integer(gsub(
      "[^0-9]",
      "",
      regmatches(rels, gregexpr('Id="rId[0-9]+"', rels, useBytes = TRUE))[[1]]
    ))
    next_id <- if (length(used) == 0) 1L else max(used, na.rm = TRUE) + 1L
    rels <- sub(
      "</Relationships>",
      paste0(
        '<Relationship Id="rId', next_id, '"',
        ' Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject"',
        ' Target="vbaProject.bin"/></Relationships>'
      ),
      rels,
      fixed = TRUE
    )
    writeChar(rels, rels_path, nchars = nchar(rels, type = "bytes"), eos = NULL, useBytes = TRUE)
  }

  # ---- 3. workbook code name ----
  wb_path <- file.path(tmp, "xl", "workbook.xml")
  wb_xml <- readChar(wb_path, file.info(wb_path)$size, useBytes = TRUE)
  if (!grepl("codeName=", wb_xml, fixed = TRUE)) {
    if (grepl("<workbookPr", wb_xml, fixed = TRUE)) {
      wb_xml <- sub(
        "<workbookPr",
        '<workbookPr codeName="ThisWorkbook"',
        wb_xml,
        fixed = TRUE
      )
    } else {
      wb_xml <- sub(
        "<sheets>",
        '<workbookPr codeName="ThisWorkbook"/><sheets>',
        wb_xml,
        fixed = TRUE
      )
    }
    writeChar(wb_xml, wb_path, nchars = nchar(wb_xml, type = "bytes"), eos = NULL, useBytes = TRUE)
  }

  # ---- 4. per-sheet code names, in sheet order ----
  parts <- ck_sheet_parts_in_order(tmp)
  for (i in seq_along(parts)) {
    if (file.exists(parts[i])) {
      ck_patch_sheet_codename(parts[i], paste0("Sheet", i))
    }
  }

  # ---- 5. the VBA project itself ----
  file.copy(vba_project, file.path(tmp, "xl", "vbaProject.bin"), overwrite = TRUE)

  # ---- rezip ----
  setwd(tmp)
  zip::zipr(
    zipfile = out_tmp,
    files = list.files(tmp, all.files = FALSE),
    include_directories = FALSE,
    recurse = TRUE
  )
  setwd(wd)

  if (file.exists(xlsm_path)) {
    unlink(xlsm_path, force = TRUE)
  }
  ok <- file.copy(out_tmp, xlsm_path, overwrite = TRUE)
  if (!ok) {
    stop(paste0("Could not write the macro-enabled workbook to: ", xlsm_path))
  }

  invisible(xlsm_path)
}
