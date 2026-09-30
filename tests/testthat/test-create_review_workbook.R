# Tests for the merged review workbook: create_review_workbook(), the
# other-responses writer that was split out of save_other_responses(), and the
# name-based sheet resolution both readers now use.
#
# The point of the merge is that one file carries both logs and that the two
# readers each find their own sheet in it. The legacy two-file layout has to
# keep reading, so it is tested alongside.

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

ck_rw_write_list <- function() {
  raw <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    `_uuid` = c("uuid label", paste0("u", 1:4)),
    today = c("date label", rep("2026-09-01T08:00:00.000+03:00", 4)),
    username = c("enumerator label", paste0("enum", c(1, 1, 2, 2))),
    Q34 = c("Reason", c("other", "work", "other", "other")),
    Q34_other = c("Reason other", c("busness", "", "war", "familly")),
    age = c("Age of respondent", c("31", "204", "29", "44"))
  )

  cleaning_log <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    uuid = c("u2", "u4"),
    old_value = c("204", "familly"),
    question = c("age", "Q34_other"),
    issue = c("outlier", "typo"),
    check_binding = c("check_outlier_01 ~/~ u2", "check_text_02 ~/~ u4")
  )

  list(cleaning_log = cleaning_log, checked_dataset = raw)
}

ck_rw_other <- function() {
  df <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    uuid = c("u1", "u3", "u4"),
    username = c("enum1", "enum2", "enum2"),
    question_name = rep("Q34_other", 3),
    list_name = rep("reasons", 3),
    selected_choices = rep("Other", 3),
    response_en = c("busness", "war", "familly")
  )
  for (h in .ck_other_review_headers()) df[[h]] <- NA_character_
  attr(df, "ona_label_row_skipped") <- TRUE
  df
}

ck_rw_other_db <- function() {
  data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    name = "Q34_other",
    ref_question = "Q34",
    q_type = "select_one",
    list_name = "reasons",
    option_other = "other",
    choices = "Work;;Study;;Conflict;;Family;;Other",
    num_choices = 5
  )
}

ck_rw_tool_choices <- function() {
  data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    list_name = rep("reasons", 5),
    name = c("work", "study", "conflict", "family", "other"),
    `label::English` = c("Work", "Study", "Conflict", "Family", "Other")
  )
}

# A stand-in for the compiled VBA project: add_vba_project() copies the file
# verbatim and never parses it.
ck_rw_fake_vba <- function() {
  f <- tempfile(fileext = ".bin")
  writeBin(as.raw(c(0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 1:64)), f)
  f
}

# Fill a single cell on a sheet of an existing workbook and save it elsewhere.
ck_rw_fill <- function(from, to, edits) {
  wb <- openxlsx::loadWorkbook(from)
  for (e in edits) {
    openxlsx::writeData(
      wb,
      sheet = e$sheet,
      x = e$value,
      startCol = e$col,
      startRow = e$row,
      colNames = FALSE
    )
  }
  openxlsx::saveWorkbook(wb, to, overwrite = TRUE)
  to
}


# --------------------------------------------------------------------------
# sheet names
# --------------------------------------------------------------------------

test_that("the canonical sheet names are the ones the writers use", {
  nms <- ck_sheet_names()
  expect_identical(unname(nms[["cleaning_log"]]), "cleaning_log")
  expect_identical(unname(nms[["other_responses"]]), "other_responses")
  expect_identical(unname(nms[["dropdown"]]), "Dropdown_values")
  # unique, so a workbook built from them can never collide with itself
  expect_false(any(duplicated(tolower(nms))))
})

test_that("Sheet1 stays a candidate for the other-responses sheet", {
  # files already out with reviewers were written before the merge
  expect_identical(
    ck_sheet_candidates("other_responses"),
    c("other_responses", "Sheet1")
  )
})

test_that("illegal and colliding sheet names are rejected before any writing", {
  expect_error(ck_assert_sheet_names(c("log", "log")), "same name")
  expect_error(ck_assert_sheet_names(c("log", "LOG")), "same name")
  expect_error(
    ck_assert_sheet_names(paste(rep("x", 32), collapse = "")),
    "31 characters"
  )
  expect_error(ck_assert_sheet_names("a/b"), "cannot contain")
  expect_error(ck_assert_sheet_names("a:b"), "cannot contain")
  expect_silent(ck_assert_sheet_names(c("cleaning_log", "other_responses")))
})


# --------------------------------------------------------------------------
# the merged workbook
# --------------------------------------------------------------------------

test_that("create_review_workbook() writes both logs into one file", {
  out <- withr::local_tempfile(fileext = ".xlsx")

  res <- suppressWarnings(create_review_workbook(
    write_list = ck_rw_write_list(),
    other_responses = ck_rw_other(),
    other_db = ck_rw_other_db(),
    other_enumerator_id = "username",
    output_path = out
  ))

  expect_true(file.exists(res))
  expect_identical(
    readxl::excel_sheets(res),
    c(
      "cleaning_log",
      "dataset",
      "readme",
      "validation_rules",
      "other_responses",
      "Dropdown_values"
    )
  )
})

test_that("without other_responses it is a drop-in for create_cleaning_log()", {
  a <- withr::local_tempfile(fileext = ".xlsx")
  b <- withr::local_tempfile(fileext = ".xlsx")

  create_review_workbook(write_list = ck_rw_write_list(), output_path = a)
  create_cleaning_log(write_list = ck_rw_write_list(), output_path = b)

  expect_identical(readxl::excel_sheets(a), readxl::excel_sheets(b))
})

test_that("a clash between the log and other-responses sheet names is caught", {
  expect_error(
    create_review_workbook(
      write_list = ck_rw_write_list(),
      other_responses = ck_rw_other(),
      other_db = ck_rw_other_db(),
      other_sheet_name = "cleaning_log",
      output_path = withr::local_tempfile(fileext = ".xlsx")
    ),
    "same name"
  )
})

test_that("other_db without other_responses warns rather than silently dropping it", {
  expect_warning(
    create_review_workbook(
      write_list = ck_rw_write_list(),
      other_db = ck_rw_other_db(),
      output_path = withr::local_tempfile(fileext = ".xlsx")
    ),
    "without"
  )
})

test_that("the readme covers the other-responses sheet only when it is there", {
  with_other <- withr::local_tempfile(fileext = ".xlsx")
  without <- withr::local_tempfile(fileext = ".xlsx")

  suppressWarnings(create_review_workbook(
    write_list = ck_rw_write_list(),
    other_responses = ck_rw_other(),
    other_db = ck_rw_other_db(),
    output_path = with_other
  ))
  create_review_workbook(
    write_list = ck_rw_write_list(),
    output_path = without
  )

  a <- openxlsx::read.xlsx(with_other, sheet = "readme")
  b <- openxlsx::read.xlsx(without, sheet = "readme")

  expect_true(any(grepl("other_responses", a[[1]], fixed = TRUE)))
  expect_false(any(grepl("other_responses", b[[1]], fixed = TRUE)))
  # the action vocabulary survives in both
  expect_true(all(c("recoded", "discard") %in% a[[1]]))
  expect_true(all(c("recoded", "discard") %in% b[[1]]))
})


# --------------------------------------------------------------------------
# reading it back
# --------------------------------------------------------------------------

test_that("both readers find their own sheet in the merged workbook", {
  dir <- withr::local_tempdir()
  built <- file.path(dir, "build.xlsx")
  suppressWarnings(create_review_workbook(
    write_list = ck_rw_write_list(),
    other_responses = ck_rw_other(),
    other_db = ck_rw_other_db(),
    other_enumerator_id = "username",
    output_path = built
  ))

  log_cols <- names(openxlsx::read.xlsx(built, sheet = "cleaning_log"))
  or_cols <- names(openxlsx::read.xlsx(built, sheet = "other_responses"))

  edited <- ck_rw_fill(
    built,
    file.path(dir, "2026-09-29_follow-ups_edited.xlsx"),
    list(
      list(
        sheet = "cleaning_log",
        row = 2,
        col = which(log_cols == "Action.taken"),
        value = "recoded"
      ),
      list(
        sheet = "cleaning_log",
        row = 2,
        col = which(log_cols == "New.value"),
        value = "31"
      ),
      list(
        sheet = "other_responses",
        row = 2,
        col = grep("^Input.translation", or_cols)[1],
        value = "business"
      )
    )
  )
  # the build file must not be picked up as a second log
  file.remove(built)

  raw <- ck_rw_write_list()[["checked_dataset"]]

  cl <- read_cleaning_log(
    path = dir,
    raw_dataset = raw,
    raw_uuid_column = "_uuid",
    verbose = FALSE
  )
  expect_equal(nrow(cl), 2)
  expect_true("Survey UUID" %in% names(cl))

  or <- read_other_responses(
    path = edited,
    dataset = raw,
    other_db = ck_rw_other_db(),
    tool_choices = ck_rw_tool_choices(),
    uuid_column = "_uuid",
    log_uuid_col = "uuid",
    verbose = FALSE
  )
  expect_equal(nrow(or), 1)
  expect_identical(or$action_taken, "true_other")
  expect_identical(or$new_value, "business")
})

test_that("read_other_responses() still reads a legacy Sheet1 file", {
  f <- withr::local_tempfile(fileext = ".xlsx")

  df <- ck_rw_other()
  hdr <- .ck_other_review_headers()
  df[[hdr[["true_other"]]]][1] <- "business"

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  openxlsx::writeData(wb, "Sheet1", df)
  openxlsx::addWorksheet(wb, "Dropdown_values")
  openxlsx::saveWorkbook(wb, f, overwrite = TRUE)

  or <- read_other_responses(
    path = f,
    dataset = ck_rw_write_list()[["checked_dataset"]],
    other_db = ck_rw_other_db(),
    tool_choices = ck_rw_tool_choices(),
    uuid_column = "_uuid",
    log_uuid_col = "uuid",
    verbose = FALSE
  )
  expect_equal(nrow(or), 1)
  expect_identical(or$new_value, "business")
})

test_that("save_other_responses() writes the named sheet, not Sheet1", {
  dir <- withr::local_tempdir()
  suppressWarnings(save_other_responses(
    df = ck_rw_other(),
    other_db = ck_rw_other_db(),
    save_location = dir,
    file_name = "standalone"
  ))
  f <- file.path(dir, "standalone.xlsx")
  expect_true(file.exists(f))
  expect_identical(
    readxl::excel_sheets(f),
    c("other_responses", "Dropdown_values")
  )
})

test_that("read_cleaning_log() finds the log by name, whatever its position", {
  f <- withr::local_tempfile(fileext = ".xlsx")

  # a workbook where the log is deliberately not the first sheet
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "dataset")
  openxlsx::writeData(wb, "dataset", data.frame(x = 1))
  openxlsx::addWorksheet(wb, "cleaning_log")
  openxlsx::writeData(
    wb,
    "cleaning_log",
    data.frame(
      check.names = FALSE,
      `Survey UUID` = "u2",
      `Question number` = "age",
      `Old value` = "204",
      `New value` = "31",
      `Action taken` = "recoded"
    )
  )
  openxlsx::saveWorkbook(wb, f, overwrite = TRUE)

  cl <- read_cleaning_log(
    path = f,
    raw_dataset = ck_rw_write_list()[["checked_dataset"]],
    raw_uuid_column = "_uuid",
    verbose = FALSE
  )
  expect_equal(nrow(cl), 1)
  expect_identical(cl[["Survey UUID"]], "u2")
})


# --------------------------------------------------------------------------
# the macro workbook
# --------------------------------------------------------------------------

test_that("the macro workbook keeps _ck_config last and points at the right sheets", {
  out <- withr::local_tempfile(fileext = ".xlsm")

  res <- suppressWarnings(create_review_workbook(
    write_list = ck_rw_write_list(),
    other_responses = ck_rw_other(),
    other_db = ck_rw_other_db(),
    vba = TRUE,
    vba_project = ck_rw_fake_vba(),
    output_path = out
  ))

  sheets <- readxl::excel_sheets(res)
  expect_identical(
    sheets,
    c(
      "cleaning_log",
      "dataset",
      "readme",
      "validation_rules",
      "other_responses",
      "Dropdown_values",
      "_ck_config"
    )
  )
  # added last, so nothing that was already there moved
  expect_identical(sheets[length(sheets)], "_ck_config")

  cfg <- as.data.frame(readxl::read_excel(res, sheet = "_ck_config"))
  # the macro watches the dataset sheet and writes to the log sheet - the extra
  # other-responses sheets must not change either
  expect_identical(cfg$value[cfg$key == "dataset_sheet"], "dataset")
  expect_identical(cfg$value[cfg$key == "log_sheet"], "cleaning_log")
})

test_that("an .xlsm path turns the macro on by itself", {
  out <- withr::local_tempfile(fileext = ".xlsm")
  res <- create_review_workbook(
    write_list = ck_rw_write_list(),
    vba_project = ck_rw_fake_vba(),
    output_path = out
  )
  expect_true("_ck_config" %in% readxl::excel_sheets(res))
})

test_that("an .xlsx path is corrected when the macro is asked for", {
  out <- file.path(withr::local_tempdir(), "log.xlsx")
  expect_message(
    res <- create_review_workbook(
      write_list = ck_rw_write_list(),
      vba = TRUE,
      vba_project = ck_rw_fake_vba(),
      output_path = out
    ),
    "must be .xlsm"
  )
  expect_match(res, "\\.xlsm$")
})

test_that("every worksheet in the macro workbook gets a unique code name", {
  out <- withr::local_tempfile(fileext = ".xlsm")
  res <- suppressWarnings(create_review_workbook(
    write_list = ck_rw_write_list(),
    other_responses = ck_rw_other(),
    other_db = ck_rw_other_db(),
    vba = TRUE,
    vba_project = ck_rw_fake_vba(),
    output_path = out
  ))

  dir <- withr::local_tempdir()
  utils::unzip(res, exdir = dir)
  parts <- list.files(
    file.path(dir, "xl", "worksheets"),
    pattern = "\\.xml$",
    full.names = TRUE
  )
  codes <- vapply(
    parts,
    function(f) {
      head_txt <- readChar(f, min(4096, file.info(f)$size), useBytes = TRUE)
      m <- regmatches(head_txt, regexpr('codeName="[^"]+"', head_txt))
      if (length(m) == 0) NA_character_ else m
    },
    character(1)
  )

  expect_length(parts, 7)
  expect_false(any(is.na(codes)))
  expect_false(any(duplicated(codes)))
})

test_that("both sets of drop-downs survive in one workbook", {
  out <- withr::local_tempfile(fileext = ".xlsx")
  suppressWarnings(create_review_workbook(
    write_list = ck_rw_write_list(),
    other_responses = ck_rw_other(),
    other_db = ck_rw_other_db(),
    output_path = out
  ))

  dir <- withr::local_tempdir()
  utils::unzip(out, exdir = dir)
  read_part <- function(n) {
    f <- file.path(dir, "xl", "worksheets", n)
    readChar(f, file.info(f)$size, useBytes = TRUE)
  }

  # sheet1 is cleaning_log, sheet5 is other_responses
  expect_true(grepl("validation_rules", read_part("sheet1.xml"), fixed = TRUE))
  expect_true(grepl("Dropdown_values", read_part("sheet5.xml"), fixed = TRUE))
})
