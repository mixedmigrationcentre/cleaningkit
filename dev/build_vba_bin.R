# ---------------------------------------------------------------------------
# Build inst/extdata/cleaningkit_vba.bin from the sources in inst/vba/
#
# Run this once (and again whenever the VBA changes). It needs:
#   * Windows with Excel installed
#   * the RDCOMClient package, from the MMC fork (the upstream omegahat
#     package has an issue):          pak::pak("iAthmanMMC/RDCOMClient")
#                                     or cleaningkit::load_packages(vba = TRUE)
#   * Excel > File > Options > Trust Center > Trust Center Settings >
#     Macro Settings > "Trust access to the VBA project object model" ticked
#
# The last one is off by default and is often locked down by IT. If you cannot
# enable it, use the manual procedure in inst/vba/README.md instead - it takes
# about five minutes and produces exactly the same file.
#
# WHY R CANNOT JUST GENERATE THIS FILE
# ------------------------------------
# vbaProject.bin is an OLE compound file holding MS-OVBA-compressed source plus
# a compiled p-code cache. Writing one from scratch means reimplementing that
# format; the few libraries that attempt it are immature and none document
# Excel compatibility. Building it in Excel is the only route that gives a file
# Excel is guaranteed to accept - and the macro has to be debugged in Excel
# anyway. The .bas/.cls sources are the reviewable artefact; the .bin is a
# build output that happens to be committed.
# ---------------------------------------------------------------------------

build_vba_bin <- function(
  pkg_root = ".",
  out_path = file.path(pkg_root, "inst", "extdata", "cleaningkit_vba.bin"),
  keep_authoring_workbook = TRUE
) {
  if (.Platform$OS.type != "windows") {
    stop("This builder drives Excel through COM and only runs on Windows.")
  }
  # RDCOMClient must be ATTACHED, not merely namespaced. Its native code calls
  # back into R by name - createCOMReference(), among others - and resolves
  # those through the search path. With RDCOMClient::COMCreate() the package is
  # loaded but not attached, so the very first call dies with
  #   could not find function "createCOMReference"
  # even though the function is exported. Same reason the S4 methods for `$`
  # and `[[` on COM objects need the package on the search path.
  # The MMC fork, not the upstream omegahat package, which has an issue.
  if (!requireNamespace("RDCOMClient", quietly = TRUE)) {
    stop(
      "RDCOMClient is required to build the VBA project.\n",
      "Install the MMC fork:\n",
      "  pak::pak(\"iAthmanMMC/RDCOMClient\")\n",
      "or:\n",
      "  cleaningkit::load_packages(vba = TRUE)",
      call. = FALSE
    )
  }
  library(RDCOMClient)

  # Directories are normalised, not the files: normalizePath() on a path that
  # does not exist yet can leave it relative, and Excel's SaveAs resolves a
  # relative path against its own default folder (usually Documents), quietly
  # saving the authoring workbook somewhere other than the package.
  vba_dir <- normalizePath(
    file.path(pkg_root, "inst", "vba"),
    mustWork = TRUE
  )
  module_path <- normalizePath(
    file.path(vba_dir, "Module1.bas"),
    mustWork = TRUE
  )
  thisworkbook_path <- normalizePath(
    file.path(vba_dir, "ThisWorkbook.cls"),
    mustWork = TRUE
  )

  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  out_path <- file.path(
    normalizePath(dirname(out_path), mustWork = TRUE),
    basename(out_path)
  )

  authoring_xlsm <- file.path(vba_dir, "cleaningkit_vba_authoring.xlsm")
  if (file.exists(authoring_xlsm)) {
    unlink(authoring_xlsm, force = TRUE)
  }

  excel <- COMCreate("Excel.Application")
  on.exit(
    {
      try(excel$Quit(), silent = TRUE)
      rm(excel)
      gc()
    },
    add = TRUE
  )
  excel[["Visible"]] <- FALSE
  excel[["DisplayAlerts"]] <- FALSE

  # One worksheet only. The VBA project then declares exactly ThisWorkbook and
  # Sheet1 as document modules; Excel creates the modules for the cleaning log's
  # other sheets itself when the generated workbook is opened. A project that
  # declares MORE sheet modules than the workbook has leaves orphans behind.
  prev_sheets <- excel[["SheetsInNewWorkbook"]]
  excel[["SheetsInNewWorkbook"]] <- 1L
  wb <- excel[["Workbooks"]]$Add()
  excel[["SheetsInNewWorkbook"]] <- prev_sheets

  vbproj <- tryCatch(
    wb[["VBProject"]],
    error = function(e) {
      stop(
        "Could not reach the VBA project.\n",
        "Tick Excel > File > Options > Trust Center > Trust Center Settings > ",
        "Macro Settings > 'Trust access to the VBA project object model', ",
        "or use the manual steps in inst/vba/README.md.\n",
        "Original error: ",
        conditionMessage(e)
      )
    }
  )

  # Module1 is a standard module and imports cleanly.
  vbproj[["VBComponents"]]$Import(module_path)

  # ThisWorkbook is a document module and cannot be imported - its code has to
  # be inserted into the component that already exists.
  code <- paste(readLines(thisworkbook_path, warn = FALSE), collapse = "\r\n")
  doc <- vbproj[["VBComponents"]]$Item("ThisWorkbook")
  cm <- doc[["CodeModule"]]

  # CountOfLines is a property of VBIDE.CodeModule, not a method - read it with
  # [[ ]] rather than calling it.
  n_lines <- as.integer(cm[["CountOfLines"]])
  if (!is.na(n_lines) && n_lines > 0) {
    cm$DeleteLines(1L, n_lines)
  }
  cm$AddFromString(code)

  # 52 = xlOpenXMLWorkbookMacroEnabled
  wb$SaveAs(authoring_xlsm, 52L)
  wb$Close(FALSE)
  excel$Quit()
  on.exit()
  rm(excel)
  gc()

  # ---- pull xl/vbaProject.bin out of the saved workbook ----
  tmp <- tempfile("ck_vba_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
  utils::unzip(authoring_xlsm, files = "xl/vbaProject.bin", exdir = tmp)

  extracted <- file.path(tmp, "xl", "vbaProject.bin")
  if (!file.exists(extracted)) {
    stop("Excel saved the workbook but it contains no VBA project.")
  }
  file.copy(extracted, out_path, overwrite = TRUE)

  if (!keep_authoring_workbook) {
    unlink(authoring_xlsm, force = TRUE)
  }

  message(
    "Wrote ",
    out_path,
    " (",
    format(file.info(out_path)$size, big.mark = ","),
    " bytes)."
  )
  message(
    "Now smoke-test it: create_cleaning_log_vba(..., output_path = \"smoke.xlsm\") ",
    "and open the result in Excel. See inst/vba/README.md for the full check."
  )

  invisible(out_path)
}


if (identical(environment(), globalenv()) && !interactive()) {
  build_vba_bin()
}
