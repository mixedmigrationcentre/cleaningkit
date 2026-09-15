# Tests for create_cleaning_log_vba() and the VBA injection machinery.
#
# create_cleaning_log() itself is deliberately untouched by this feature - the
# first test below guards that, so the plain .xlsx path can never be broken by
# work on the macro.

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

ck_test_write_list <- function() {
  raw <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    a = c("label", "u1", "u2"),
    b = c("label", "2026-08-01", "2026-08-02"),
    c = c("label", "enum_a", "enum_b"),
    d = c("Age of respondent", "31", "204"),
    e = c("Sex of respondent", "female", "male")
  )
  names(raw) <- c("_uuid", "today", "username", "age", "sex")

  cleaning_log <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    uuid = "u2",
    old_value = "204",
    question = "age",
    issue = "outlier",
    check_binding = "check_outlier_01 ~/~ u2"
  )

  list(cleaning_log = cleaning_log, checked_dataset = raw)
}

# A stand-in for the compiled VBA project. add_vba_project() copies the file
# verbatim and never parses it, so the package surgery can be tested in full
# without a real Excel-built binary.
ck_fake_vba <- function() {
  f <- tempfile(fileext = ".bin")
  writeBin(as.raw(c(0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 1:64)), f)
  f
}

# read one part out of an OPC package as text
ck_read_part <- function(zip_path, part) {
  con <- unz(zip_path, part, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_bytes <- raw(0)
  repeat {
    chunk <- readBin(con, "raw", n = 65536L)
    if (length(chunk) == 0) {
      break
    }
    raw_bytes <- c(raw_bytes, chunk)
  }
  rawToChar(raw_bytes)
}


# --------------------------------------------------------------------------
# separation of the two functions
# --------------------------------------------------------------------------

test_that("create_cleaning_log() carries no macro machinery", {
  # The whole point of the split: if the macro route breaks, this one is
  # untouched. Assert on the formals rather than the body so the guard is
  # readable.
  fmls <- names(formals(create_cleaning_log))
  expect_false("macro" %in% fmls)
  expect_false("vba_project" %in% fmls)
  expect_false("macro_issue_prefix" %in% fmls)
  # and it still returns a workbook when given no path
  expect_true("output_path" %in% fmls)
})


test_that("create_cleaning_log_vba() mirrors create_cleaning_log()'s arguments", {
  plain <- names(formals(create_cleaning_log))
  vba <- names(formals(create_cleaning_log_vba))

  # include_dataset is forced TRUE by the vba version, so it is the one
  # argument deliberately dropped
  expect_setequal(setdiff(plain, vba), "include_dataset")
  expect_setequal(
    setdiff(vba, plain),
    c("macro_issue_prefix", "vba_project")
  )
})


test_that("ck_action_codes() matches the codes create_cleaning_log() writes", {
  # The macro writes one of these into Action taken and offers them as the
  # drop-down on appended rows. If the two lists ever drift, evaluate_cleaning_log()
  # would reject the macro's own rows - so fail here instead.
  out <- tempfile(fileext = ".xlsx")
  on.exit(unlink(out, force = TRUE), add = TRUE)
  create_cleaning_log(ck_test_write_list(), output_path = out)

  written <- openxlsx::read.xlsx(out, sheet = "validation_rules")
  expect_equal(as.character(written[[1]]), ck_action_codes())
})


# --------------------------------------------------------------------------
# locating the compiled VBA project
# --------------------------------------------------------------------------

test_that("ck_vba_project_path() honours the option override", {
  f <- ck_fake_vba()
  old <- getOption("cleaningkit.vba_project")
  options(cleaningkit.vba_project = f)
  on.exit(
    {
      options(cleaningkit.vba_project = old)
      unlink(f, force = TRUE)
    },
    add = TRUE
  )

  expect_equal(
    normalizePath(ck_vba_project_path(), winslash = "/", mustWork = FALSE),
    normalizePath(f, winslash = "/", mustWork = FALSE)
  )
})


test_that("ck_vba_project_path() returns \"\" rather than erroring when nothing is found", {
  old <- getOption("cleaningkit.vba_project")
  options(cleaningkit.vba_project = tempfile("no-such-", fileext = ".bin"))
  on.exit(options(cleaningkit.vba_project = old), add = TRUE)

  # the installed package may legitimately ship a binary, so only assert the
  # contract: a single string, never an error
  expect_type(ck_vba_project_path(), "character")
  expect_length(ck_vba_project_path(), 1L)
})


test_that("the not-found message names every place it looked and how to fix it", {
  msg <- ck_vba_missing_message()
  expect_match(msg, "cleaningkit_vba.bin", fixed = TRUE)
  expect_match(msg, "resources", fixed = TRUE)
  expect_match(msg, "cleaningkit.vba_project", fixed = TRUE)
  expect_match(msg, "vba_project =", fixed = TRUE)
  # points at the plain function as the fallback, not at a `macro` argument
  # that no longer exists
  expect_match(msg, "create_cleaning_log()", fixed = TRUE)
  expect_false(grepl("macro = FALSE", msg, fixed = TRUE))
})


# --------------------------------------------------------------------------
# configuration written for the macro
# --------------------------------------------------------------------------

test_that("ck_macro_config_df carries everything the macro reads", {
  cfg <- ck_macro_config_df(
    dataset_sheet = "dataset",
    log_sheet = "cleaning_log",
    uuid_column = "_uuid",
    date_column = "today",
    enumerator_column = "username",
    issue_prefix = "manual_edit",
    action_codes = c("recoded", "delete_data_point", "discard"),
    body_front = "Arial Narrow",
    body_front_size = 11
  )

  expect_s3_class(cfg, "data.frame")
  expect_named(cfg, c("key", "value"))
  expect_true(all(
    c(
      "dataset_sheet",
      "log_sheet",
      "uuid_column",
      "date_column",
      "enumerator_column",
      "issue_prefix",
      "action_codes",
      "header_row",
      "label_row",
      "first_data_row"
    ) %in%
      cfg$key
  ))

  # the action list is what the macro feeds to Validation.Add
  expect_identical(
    cfg$value[cfg$key == "action_codes"],
    "recoded,delete_data_point,discard"
  )
  expect_identical(cfg$value[cfg$key == "first_data_row"], "3")
})


# --------------------------------------------------------------------------
# the codeName splice
# --------------------------------------------------------------------------

test_that("ck_patch_sheet_codename inserts a sheetPr when there is none", {
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f, force = TRUE), add = TRUE)
  writeLines(
    paste0(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
      '<worksheet xmlns="http://x"><dimension ref="A1"/><sheetData/></worksheet>'
    ),
    f
  )

  expect_true(ck_patch_sheet_codename(f, "Sheet3"))

  out <- readLines(f, warn = FALSE)
  expect_match(out, '<sheetPr codeName="Sheet3"/>', fixed = TRUE, all = FALSE)
  # must land immediately after the opening tag, before <dimension>
  expect_match(
    out,
    '<worksheet xmlns="http://x"><sheetPr codeName="Sheet3"/><dimension',
    fixed = TRUE,
    all = FALSE
  )
})


test_that("ck_patch_sheet_codename amends an existing sheetPr instead of adding a second", {
  # openxlsx emits <sheetPr> whenever a tab colour is set; a naive
  # "insert if absent" patch silently skips those sheets.
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f, force = TRUE), add = TRUE)
  writeLines(
    paste0(
      '<?xml version="1.0"?>',
      '<worksheet xmlns="http://x"><sheetPr><tabColor rgb="FF00A2A5"/></sheetPr>',
      "<sheetData/></worksheet>"
    ),
    f
  )

  expect_true(ck_patch_sheet_codename(f, "Sheet2"))

  out <- paste(readLines(f, warn = FALSE), collapse = "")
  expect_equal(
    lengths(regmatches(out, gregexpr("<sheetPr", out, fixed = TRUE))),
    1L
  )
  expect_match(out, '<sheetPr codeName="Sheet2">', fixed = TRUE)
  expect_match(out, '<tabColor rgb="FF00A2A5"/>', fixed = TRUE)
})


test_that("ck_patch_sheet_codename leaves an existing codeName alone", {
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f, force = TRUE), add = TRUE)
  original <- '<worksheet xmlns="http://x"><sheetPr codeName="Keep"/><sheetData/></worksheet>'
  writeLines(original, f)

  expect_false(ck_patch_sheet_codename(f, "Sheet9"))
  expect_equal(
    trimws(paste(readLines(f, warn = FALSE), collapse = "")),
    original
  )
})


# --------------------------------------------------------------------------
# create_cleaning_log_vba()
# --------------------------------------------------------------------------

test_that("create_cleaning_log_vba() refuses what it cannot deliver", {
  wl <- ck_test_write_list()

  expect_error(
    create_cleaning_log_vba(wl),
    "output_path",
    fixed = TRUE
  )
  expect_error(
    create_cleaning_log_vba(
      wl,
      vba_project = file.path(tempdir(), "definitely-not-here.bin"),
      output_path = tempfile(fileext = ".xlsm")
    ),
    "does not point at a file that exists",
    fixed = TRUE
  )
})


test_that("the plain .xlsx path is unchanged", {
  wl <- ck_test_write_list()
  out <- tempfile(fileext = ".xlsx")
  on.exit(unlink(out, force = TRUE), add = TRUE)

  create_cleaning_log(wl, output_path = out)

  expect_true(file.exists(out))
  sheets <- openxlsx::getSheetNames(out)
  expect_equal(sheets[1], "cleaning_log")
  expect_false("_ck_config" %in% sheets)

  ct <- ck_read_part(out, "[Content_Types].xml")
  expect_false(grepl("macroEnabled", ct, fixed = TRUE))
})


test_that("create_cleaning_log_vba() produces a well-formed macro-enabled package", {
  wl <- ck_test_write_list()
  vba <- ck_fake_vba()
  out <- tempfile(fileext = ".xlsm")
  on.exit(unlink(c(out, vba), force = TRUE), add = TRUE)

  create_cleaning_log_vba(wl, output_path = out, vba_project = vba)

  expect_true(file.exists(out))
  entries <- utils::unzip(out, list = TRUE)$Name

  # the VBA project is present and byte-identical (so a signature would survive)
  expect_true("xl/vbaProject.bin" %in% entries)
  extract_dir <- tempfile("ck_x_")
  dir.create(extract_dir)
  on.exit(unlink(extract_dir, recursive = TRUE, force = TRUE), add = TRUE)
  utils::unzip(out, files = "xl/vbaProject.bin", exdir = extract_dir)
  expect_identical(
    readBin(file.path(extract_dir, "xl", "vbaProject.bin"), "raw", n = 1e6),
    readBin(vba, "raw", n = 1e6)
  )

  # content types: main part retyped, explicit override added.
  # The override matters because openxlsx's genBaseContent_Type() maps
  # Default Extension="bin" to printerSettings, which would mis-type the
  # VBA part and make Excel offer to repair the file.
  ct <- ck_read_part(out, "[Content_Types].xml")
  expect_true(grepl(
    "application/vnd.ms-excel.sheet.macroEnabled.main+xml",
    ct,
    fixed = TRUE
  ))
  expect_true(grepl('PartName="/xl/vbaProject.bin"', ct, fixed = TRUE))
  expect_false(grepl("spreadsheetml.sheet.main+xml", ct, fixed = TRUE))

  # relationship
  rels <- ck_read_part(out, "xl/_rels/workbook.xml.rels")
  expect_true(grepl("office/2006/relationships/vbaProject", rels, fixed = TRUE))
  expect_true(grepl('Target="vbaProject.bin"', rels, fixed = TRUE))

  # code names: openxlsx drops these, and without them the VBA project has
  # nothing to bind its document modules to
  wb_xml <- ck_read_part(out, "xl/workbook.xml")
  expect_true(grepl('codeName="ThisWorkbook"', wb_xml, fixed = TRUE))

  sheet_parts <- grep("^xl/worksheets/sheet[0-9]+\\.xml$", entries, value = TRUE)
  expect_gt(length(sheet_parts), 0)
  for (p in sheet_parts) {
    expect_match(ck_read_part(out, p), 'codeName="Sheet[0-9]+"')
  }
})


test_that("the hidden config sheet describes the workbook the macro will see", {
  wl <- ck_test_write_list()
  vba <- ck_fake_vba()
  out <- tempfile(fileext = ".xlsm")
  on.exit(unlink(c(out, vba), force = TRUE), add = TRUE)

  create_cleaning_log_vba(
    wl,
    output_path = out,
    macro_issue_prefix = "reviewer_edit",
    vba_project = vba
  )

  sheets <- openxlsx::getSheetNames(out)
  expect_true("_ck_config" %in% sheets)
  # last, so the positions of the existing sheets do not move
  expect_equal(sheets[length(sheets)], "_ck_config")
  expect_equal(sheets[1], "cleaning_log")
  expect_equal(sheets[2], "dataset")

  cfg <- openxlsx::read.xlsx(out, sheet = "_ck_config")
  kv <- stats::setNames(as.character(cfg$value), as.character(cfg$key))

  expect_equal(unname(kv[["dataset_sheet"]]), "dataset")
  expect_equal(unname(kv[["log_sheet"]]), "cleaning_log")
  expect_equal(unname(kv[["uuid_column"]]), "_uuid")
  expect_equal(unname(kv[["issue_prefix"]]), "reviewer_edit")
  # openxlsx writes names on row 1, so the ONA label row is row 2 and the
  # records start on row 3
  expect_equal(unname(kv[["header_row"]]), "1")
  expect_equal(unname(kv[["label_row"]]), "2")
  expect_equal(unname(kv[["first_data_row"]]), "3")

  # The config sheet must not be reachable from the Unhide dialog, which means
  # state="veryHidden" rather than state="hidden" in workbook.xml.
  #
  # Assert on the package bytes, not on loadWorkbook(): openxlsx cannot read
  # veryHidden back. loadWorkbook.R decides visibility with
  #   is_visible <- !grepl("hidden", sheets)
  # which is case-sensitive, so state="veryHidden" (capital H) does not match
  # and the sheet is reloaded as plain visible. A lower-case state="hidden"
  # does match, which is why validation_rules round-trips and this has gone
  # unnoticed. The file Excel opens is correct either way, and that is what
  # this test needs to pin down.
  wb_xml <- ck_read_part(out, "xl/workbook.xml")
  sheet_nodes <- regmatches(wb_xml, gregexpr("<sheet [^>]*/>", wb_xml))[[1]]
  node_for <- function(nm) {
    hit <- sheet_nodes[
      grepl(paste0('name="', nm, '"'), sheet_nodes, fixed = TRUE)
    ]
    if (length(hit) == 0) NA_character_ else hit[[1]]
  }

  expect_false(is.na(node_for("_ck_config")))
  expect_match(node_for("_ck_config"), 'state="veryHidden"', fixed = TRUE)
  # and the existing hidden sheet is untouched
  expect_match(node_for("validation_rules"), 'state="hidden"', fixed = TRUE)
  expect_match(node_for("cleaning_log"), 'state="visible"', fixed = TRUE)
})


test_that("skip_label_row = FALSE shifts the row layout the macro is told about", {
  wl <- ck_test_write_list()
  vba <- ck_fake_vba()
  out <- tempfile(fileext = ".xlsm")
  on.exit(unlink(c(out, vba), force = TRUE), add = TRUE)

  create_cleaning_log_vba(
    wl,
    output_path = out,
    skip_label_row = FALSE,
    vba_project = vba
  )

  cfg <- openxlsx::read.xlsx(out, sheet = "_ck_config")
  kv <- stats::setNames(as.character(cfg$value), as.character(cfg$key))
  expect_equal(unname(kv[["label_row"]]), "0")
  expect_equal(unname(kv[["first_data_row"]]), "2")
})


test_that("an .xlsx output_path is redirected to .xlsm", {
  wl <- ck_test_write_list()
  vba <- ck_fake_vba()
  out <- tempfile(fileext = ".xlsx")
  on.exit(
    unlink(c(out, sub("\\.xlsx$", ".xlsm", out), vba), force = TRUE),
    add = TRUE
  )

  expect_message(
    res <- create_cleaning_log_vba(wl, output_path = out, vba_project = vba),
    "\\.xlsm"
  )

  expect_match(res, "\\.xlsm$")
  expect_true(file.exists(res))
  expect_false(file.exists(out))
})


# --------------------------------------------------------------------------
# the round trip the macro depends on
# --------------------------------------------------------------------------

test_that("repeat-edit rows survive read_cleaning_log rather than collapsing", {
  # A second edit of the same cell is appended as a NEW row, distinguished only
  # by its Issue. The dedup key is uuid + question + issue, so both rows must
  # come through, and the later one must sort last so apply_cleaning_log()
  # writes the final value.
  raw <- ck_test_write_list()$checked_dataset

  filled <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    a = c("u2", "u2"),
    b = c("age", "age"),
    c = c("manual_edit_001", "manual_edit_002"),
    d = c("204", "20"),
    e = c("recoded", "recoded"),
    f = c("20", "24")
  )
  names(filled) <- c(
    "Survey UUID",
    "Question number",
    "Issue",
    "Old value",
    "Action taken",
    "New value"
  )

  f <- tempfile(fileext = ".xlsx")
  on.exit(unlink(f, force = TRUE), add = TRUE)
  openxlsx::write.xlsx(filled, f)

  got <- read_cleaning_log(
    path = f,
    raw_dataset = raw,
    sheet = 1,
    verbose = FALSE
  )

  expect_equal(nrow(got), 2L)
  expect_equal(got[["Issue"]], c("manual_edit_001", "manual_edit_002"))
  # the sequence numbers sort in edit order, so the newest value is applied last
  expect_equal(got[["New value"]][nrow(got)], "24")

  applied <- apply_cleaning_log(
    raw_dataset = raw,
    cleaning_log = got,
    verbose = FALSE
  )
  cleaned <- applied$clean_dataset
  expect_equal(
    as.character(cleaned[["age"]][cleaned[["_uuid"]] == "u2"]),
    "24"
  )
})


test_that("without the case-insensitive issue lookup, repeat edits would be lost", {
  # Guards the ck_issue_values() fix. create_cleaning_log() writes the header
  # "Issue"; the dedup key used to match only the lower-case "issue", so a log
  # read back from a generated workbook silently keyed on uuid + question alone
  # and dropped every repeat-edit row but the first.
  df <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    Issue = c("manual_edit_001", "manual_edit_002")
  )
  expect_equal(ck_issue_values(df), c("manual_edit_001", "manual_edit_002"))

  names(df) <- "issue"
  expect_equal(ck_issue_values(df), c("manual_edit_001", "manual_edit_002"))

  expect_equal(ck_issue_values(data.frame(x = 1:2)), c("", ""))
})
