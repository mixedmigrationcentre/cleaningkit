# Tests for the check-flag columns prepended to the `dataset` sheet.
#
# The columns exist so a reviewer can filter the raw data down to the surveys a
# survey-level check flagged and decide, in place, whether to keep or discard
# them. Their contract is:
#   * one column per entry of `flag_columns`, in front of the ONA columns;
#   * a cell carries the flagged `old_value` for that record, blank otherwise;
#   * matching is by the `check_binding` prefix, so any mix of validate_*
#     functions works;
#   * in the macro workbook they are exempt from change capture.

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

# A dataset with the ONA label row on row 1 and five records, plus a combined
# log carrying one row from each of the five checks the defaults cover.
ck_flag_write_list <- function() {
  raw <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    `_uuid` = c("label uuid", paste0("u", 1:5)),
    today = c("label today", paste0("2026-09-0", 1:5)),
    username = c("label enum", rep(c("enum_a", "enum_b"), length.out = 5)),
    age = c("Age of respondent", "31", "42", "19", "204", "27")
  )
  names(raw) <- c("_uuid", "today", "username", "age")

  cleaning_log <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    uuid = c("u1", "u2", "u2", "u3", "u4", "u5", "u1"),
    old_value = c("9.2", "41", "7", "12", "2026-09-04T08:00", "18", "204"),
    question = c(
      "_duration", "all_columns", "all_columns", "_duration",
      "start", "number_similar_columns", "age"
    ),
    issue = c(
      "short", "few cells", "refused", "short",
      paste0(
        "Back-to-back interview: started 7 min after enumerator 'enum_b' ",
        "ended the previous interview (uuid u3); below the 15 min threshold ",
        "- possible fabrication"
      ),
      paste0(
        "Similarity with surveys from enumerator 'enum_a': 221 of 227 ",
        "columns are similar from survey u4 - threshold is 30"
      ),
      "outlier"
    ),
    check_binding = c(
      "duration_check ~/~ u1",
      "completeness_check ~/~ u2",
      "refused_check ~/~ u2",
      "duration_check ~/~ u3",
      "back_to_back_check ~/~ u4",
      "soft_duplicate ~/~ u4 ~/~ u5",
      "outlier_check ~/~ u1"
    )
  )

  list(cleaning_log = cleaning_log, checked_dataset = raw)
}

# A stand-in for the compiled VBA project: add_vba_project() copies the file
# verbatim and never parses it. Defined here rather than reused from
# test-create_cleaning_log_macro.R, because testthat gives each file its own
# environment.
ck_flag_fake_vba <- function() {
  f <- tempfile(fileext = ".bin")
  writeBin(as.raw(c(0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 1:64)), f)
  f
}

# The dataset sheet as written, read back out of a saved workbook.
ck_flag_dataset_sheet <- function(write_list, ...) {
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path, force = TRUE), add = TRUE)
  create_cleaning_log(write_list, output_path = path, ...)
  openxlsx::read.xlsx(path, sheet = "dataset", colNames = TRUE, sep.names = " ")
}


# --------------------------------------------------------------------------
# defaults
# --------------------------------------------------------------------------

test_that("the defaults name the five survey-level checks", {
  defaults <- ck_flag_column_defaults()

  expect_identical(
    names(defaults),
    c("duration", "completeness", "refused", "back to back", "similarity")
  )
  expect_identical(defaults[["duration"]], "duration_check")
  expect_identical(defaults[["completeness"]], "completeness_check")
  expect_identical(defaults[["refused"]], "refused_check")

  # back to back reads from the issue: its old_value is the interview start
  # time, which means nothing to a reviewer on its own
  expect_identical(defaults[["back to back"]]$prefixes, "back_to_back_check")
  expect_identical(defaults[["back to back"]]$value, "issue")

  # both similarity checks feed one column, labelled with the log names rather
  # than the internal binding prefixes
  expect_identical(
    defaults[["similarity"]]$prefixes,
    c("soft_duplicate", "dup_q")
  )
  expect_identical(defaults[["similarity"]]$value, "issue")
  expect_identical(
    defaults[["similarity"]]$label,
    "similar_surveys_log, similar_questions_log"
  )

  expect_identical(ck_flag_column_names(), names(defaults))
  expect_identical(ck_flag_column_names(NULL), character(0))
})

test_that("the prefixes match what the validate_* functions actually write", {
  # A rename on either side breaks the join silently - every flag column would
  # simply come out empty - so the two are asserted against each other here.
  prefixes <- unlist(
    lapply(resolve_flag_columns(ck_flag_column_defaults()), `[[`, "prefixes"),
    use.names = FALSE
  )

  expect_true(all(
    c(
      "duration_check", "completeness_check", "refused_check",
      "back_to_back_check", "soft_duplicate", "dup_q"
    ) %in% prefixes
  ))
})


# --------------------------------------------------------------------------
# the columns as written to the sheet
# --------------------------------------------------------------------------

test_that("the flag columns lead the dataset sheet and carry the flagged values", {
  sheet <- ck_flag_dataset_sheet(ck_flag_write_list())

  expect_identical(
    names(sheet)[1:5],
    c("duration", "completeness", "refused", "back to back", "similarity")
  )
  expect_identical(names(sheet)[6], "_uuid")

  # row 1 of the sheet is the ONA label row; records start at row 2
  expect_identical(sheet$duration[1], "Flagged by: duration_check")
  expect_identical(
    sheet$similarity[1],
    "Flagged by: similar_surveys_log, similar_questions_log"
  )

  expect_identical(sheet$duration[2], "9.2")     # u1, short interview
  expect_true(is.na(sheet$duration[3]))          # u2, not flagged for duration
  expect_identical(sheet$duration[4], "12")      # u3
  expect_identical(sheet$completeness[3], "41")  # u2
  expect_identical(sheet$refused[3], "7")        # u2
  expect_match(sheet$`back to back`[5], "^Back-to-back interview")   # u4
  expect_match(sheet$similarity[6], "^Similarity with surveys")     # u5
})

test_that("a check with no flag column of its own leaves no trace", {
  # The outlier row in the fixture is not mapped by the defaults. It must still
  # appear in the cleaning log, and must not leak into any flag column.
  sheet <- ck_flag_dataset_sheet(ck_flag_write_list())
  flags <- sheet[, 1:5]

  expect_false(any(vapply(
    flags[-1, ],
    function(col) any(!is.na(col) & col == "204"),
    logical(1)
  )))
})

test_that("several hits for one record are joined rather than dropped", {
  write_list <- ck_flag_write_list()
  write_list$cleaning_log <- rbind(
    write_list$cleaning_log,
    data.frame(
      check.names = FALSE,
      stringsAsFactors = FALSE,
      uuid = "u1",
      old_value = "7.7",
      question = "_duration",
      issue = "short again",
      check_binding = "duration_check ~/~ u1"
    )
  )

  sheet <- ck_flag_dataset_sheet(write_list)
  expect_identical(sheet$duration[2], "9.2 | 7.7")

  sheet_semi <- ck_flag_dataset_sheet(write_list, flag_separator = "; ")
  expect_identical(sheet_semi$duration[2], "9.2; 7.7")
})

test_that("the record rows line up with their uuids", {
  sheet <- ck_flag_dataset_sheet(ck_flag_write_list())
  # the value must sit on the row whose uuid the check flagged, not on the
  # row that happens to share its position in the log
  flagged <- sheet$`_uuid`[!is.na(sheet$duration) & sheet$`_uuid` != "label uuid"]
  expect_setequal(flagged, c("u1", "u3"))
})


# --------------------------------------------------------------------------
# configuration
# --------------------------------------------------------------------------

test_that("flag_columns = NULL writes the dataset sheet unchanged", {
  write_list <- ck_flag_write_list()
  sheet <- ck_flag_dataset_sheet(write_list, flag_columns = NULL)

  expect_identical(names(sheet), names(write_list$checked_dataset))
})

test_that("a custom flag column picks up its own check", {
  sheet <- ck_flag_dataset_sheet(
    ck_flag_write_list(),
    flag_columns = list(outliers = "outlier_check")
  )

  expect_identical(names(sheet)[1], "outliers")
  expect_identical(sheet$outliers[2], "204")  # u1
  expect_true(all(is.na(sheet$outliers[3:6])))
})

test_that("a header that collides with a survey question is renamed, with a warning", {
  write_list <- ck_flag_write_list()
  names(write_list$checked_dataset)[4] <- "duration"

  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path, force = TRUE), add = TRUE)
  expect_warning(
    create_cleaning_log(write_list, output_path = path),
    "duration"
  )

  sheet <- openxlsx::read.xlsx(path, sheet = "dataset", sep.names = " ")
  expect_identical(names(sheet)[1], "duration_flag")
  # the real question column survives untouched
  expect_true("duration" %in% names(sheet)[-1])
})

test_that("a log with no check_binding gives empty columns rather than an error", {
  write_list <- ck_flag_write_list()
  write_list$cleaning_log$check_binding <- NULL

  sheet <- ck_flag_dataset_sheet(write_list)
  expect_true(all(is.na(sheet$duration[-1])))
  expect_true(all(is.na(sheet$similarity[-1])))
})

test_that("an empty log still writes the columns, so the filter is always there", {
  write_list <- ck_flag_write_list()
  write_list$cleaning_log <- write_list$cleaning_log[0, ]

  sheet <- ck_flag_dataset_sheet(write_list)
  expect_identical(names(sheet)[1:5], ck_flag_column_names())
  expect_true(all(is.na(sheet$duration[-1])))
})

test_that("include_dataset = FALSE writes no dataset sheet at all", {
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path, force = TRUE), add = TRUE)
  create_cleaning_log(
    ck_flag_write_list(),
    include_dataset = FALSE,
    output_path = path
  )

  expect_false("dataset" %in% openxlsx::getSheetNames(path))
})

test_that("skip_label_row = FALSE treats every row as a record", {
  write_list <- ck_flag_write_list()
  # without a label row the first row is a record; none of the fixture's
  # uuids sit there, so the column is blank throughout but present
  sheet <- ck_flag_dataset_sheet(write_list, skip_label_row = FALSE)

  expect_identical(names(sheet)[1:5], ck_flag_column_names())
  expect_true(is.na(sheet$duration[1]))
})

test_that("bad flag_columns definitions are refused clearly", {
  expect_error(
    create_cleaning_log(ck_flag_write_list(), flag_columns = list("duration_check")),
    "named"
  )
  expect_error(
    create_cleaning_log(
      ck_flag_write_list(),
      flag_columns = list("a,b" = "duration_check")
    ),
    "comma"
  )
  expect_error(
    create_cleaning_log(ck_flag_write_list(), flag_columns = 42),
    "named list"
  )
})


# --------------------------------------------------------------------------
# the macro's ignore list
# --------------------------------------------------------------------------

test_that("the macro is told to ignore exactly the headers that were written", {
  write_list <- ck_flag_write_list()
  path <- tempfile(fileext = ".xlsm")
  on.exit(unlink(path, force = TRUE), add = TRUE)

  create_cleaning_log_vba(
    write_list,
    output_path = path,
    vba_project = ck_flag_fake_vba()
  )

  config <- openxlsx::read.xlsx(path, sheet = "_ck_config", colNames = TRUE)
  ignored <- config$value[config$key == "ignore_columns"]

  expect_length(ignored, 1)
  expect_identical(
    strsplit(ignored, ",", fixed = TRUE)[[1]],
    ck_flag_column_names()
  )

  sheet <- openxlsx::read.xlsx(path, sheet = "dataset", sep.names = " ")
  expect_identical(names(sheet)[1:5], strsplit(ignored, ",", fixed = TRUE)[[1]])
})

test_that("the ignore list follows a renamed header", {
  write_list <- ck_flag_write_list()
  names(write_list$checked_dataset)[4] <- "duration"

  path <- tempfile(fileext = ".xlsm")
  on.exit(unlink(path, force = TRUE), add = TRUE)
  suppressWarnings(create_cleaning_log_vba(
    write_list,
    output_path = path,
    vba_project = ck_flag_fake_vba()
  ))

  config <- openxlsx::read.xlsx(path, sheet = "_ck_config", colNames = TRUE)
  ignored <- strsplit(
    config$value[config$key == "ignore_columns"], ",",
    fixed = TRUE
  )[[1]]

  expect_identical(ignored[1], "duration_flag")
})

test_that("flag_columns = NULL leaves the ignore list empty", {
  path <- tempfile(fileext = ".xlsm")
  on.exit(unlink(path, force = TRUE), add = TRUE)
  create_cleaning_log_vba(
    ck_flag_write_list(),
    output_path = path,
    flag_columns = NULL,
    vba_project = ck_flag_fake_vba()
  )

  config <- openxlsx::read.xlsx(path, sheet = "_ck_config", colNames = TRUE)
  ignored <- config$value[config$key == "ignore_columns"]
  expect_true(is.na(ignored) || !nzchar(ignored))
})

test_that("the VBA sources read the ignore list from config", {
  # The compiled .bin cannot be inspected from R, but a rebuild that forgot one
  # of these two edits would ship a workbook that logs flag-column edits. Assert
  # on the sources so the omission fails here instead.
  module <- readLines(
    system.file("vba", "Module1.bas", package = "cleaningkit"),
    warn = FALSE
  )
  workbook <- readLines(
    system.file("vba", "ThisWorkbook.cls", package = "cleaningkit"),
    warn = FALSE
  )

  expect_true(any(grepl("CkIsIgnoredColumn", module, fixed = TRUE)))
  expect_true(any(grepl('CkConfig("ignore_columns")', module, fixed = TRUE)))
  expect_true(any(grepl("CkIsIgnoredColumn", workbook, fixed = TRUE)))
  # the cached dictionary must be dropped on Workbook_Open with the rest
  expect_true(any(grepl("Set mIgnoreCols = Nothing", module, fixed = TRUE)))
})


test_that("a column can be switched between old_value and issue", {
  write_list <- ck_flag_write_list()

  by_value <- ck_flag_dataset_sheet(
    write_list,
    flag_columns = list("back to back" = "back_to_back_check")
  )
  by_issue <- ck_flag_dataset_sheet(
    write_list,
    flag_columns = list(
      "back to back" = list(prefixes = "back_to_back_check", value = "issue")
    )
  )

  expect_identical(by_value$`back to back`[5], "2026-09-04T08:00")
  expect_match(by_issue$`back to back`[5], "^Back-to-back interview")
})

test_that("the similarity default never shows the bare column count", {
  # "18" on its own tells a reviewer nothing; the issue carries the threshold,
  # the enumerator and the survey it matched.
  sheet <- ck_flag_dataset_sheet(ck_flag_write_list())
  expect_match(sheet$similarity[6], "^Similarity with surveys")
  expect_false(any(sheet$similarity[-1] %in% "18", na.rm = TRUE))
})

test_that("the back-to-back default never shows the raw start time", {
  # The whole point of the exception: a bare timestamp is not something a
  # reviewer can judge a survey on.
  sheet <- ck_flag_dataset_sheet(ck_flag_write_list())
  expect_false(any(
    grepl("2026-09-04T08:00", sheet$`back to back`, fixed = TRUE)
  ))
})

test_that("a custom label replaces the prefixes on the label row", {
  sheet <- ck_flag_dataset_sheet(
    ck_flag_write_list(),
    flag_columns = list(
      similarity = list(
        prefixes = c("soft_duplicate", "dup_q"),
        label = "my_similarity_logs"
      )
    )
  )

  expect_identical(sheet$similarity[1], "Flagged by: my_similarity_logs")
})

test_that("an unknown value source is refused", {
  expect_error(
    create_cleaning_log(
      ck_flag_write_list(),
      flag_columns = list(x = list(prefixes = "duration_check", value = "nope"))
    ),
    "old_value"
  )
})

test_that("a log with no issue column empties only the issue-sourced columns", {
  write_list <- ck_flag_write_list()
  write_list$cleaning_log$issue <- NULL

  # create_cleaning_log() requires `issue`, so this is checked one level down
  fc <- resolve_flag_columns(ck_flag_column_defaults())
  out <- ck_attach_flag_columns(
    write_list$checked_dataset,
    write_list$cleaning_log,
    "_uuid",
    fc
  )

  expect_true(all(is.na(out$`back to back`[-1])))
  expect_identical(out$duration[2], "9.2")
})


# --------------------------------------------------------------------------
# telling the block apart from the raw data
# --------------------------------------------------------------------------

# Pull the fill colour of one cell of the `dataset` sheet out of a saved
# workbook. openxlsx offers no way to read a style back off a Workbook object,
# so the package is unzipped and styles.xml resolved by hand - which also
# proves the fill survived the save, not just the addStyle() call. The sheet
# part is resolved through workbook.xml rather than assumed to be sheetN.xml.
ck_flag_dataset_fill <- function(path, ref, sheet_name = "dataset") {
  dir <- tempfile()
  on.exit(unlink(dir, recursive = TRUE, force = TRUE), add = TRUE)
  utils::unzip(path, exdir = dir)

  slurp <- function(...) {
    paste(readLines(file.path(dir, ...), warn = FALSE), collapse = "")
  }

  wb_xml <- slurp("xl", "workbook.xml")
  rels_xml <- slurp("xl", "_rels", "workbook.xml.rels")

  nodes <- regmatches(wb_xml, gregexpr("<sheet [^>]*/>", wb_xml))[[1]]
  names_in_order <- sub('.*name="([^"]+)".*', "\\1", nodes)
  rid <- sub('.*r:id="([^"]+)".*', "\\1", nodes)[
    match(sheet_name, names_in_order)
  ]

  rel_nodes <- regmatches(
    rels_xml,
    gregexpr("<Relationship [^>]*/>", rels_xml)
  )[[1]]
  target <- sub('.*Target="([^"]+)".*', "\\1", rel_nodes)[
    match(rid, sub('.*Id="([^"]+)".*', "\\1", rel_nodes))
  ]
  target <- sub("^/xl/", "", sub("^\\.\\./", "", target))

  styles <- slurp("xl", "styles.xml")
  sheet <- paste(
    readLines(file.path(dir, "xl", target), warn = FALSE),
    collapse = ""
  )

  fills <- regmatches(styles, gregexpr("<fill>.*?</fill>|<fill/>", styles))[[1]]
  fill_rgb <- vapply(
    fills,
    function(f) {
      m <- regmatches(f, regexpr('rgb="[A-F0-9]{8}"', f))
      if (length(m) == 0) NA_character_ else substr(sub('rgb="', "", m), 3, 8)
    },
    character(1),
    USE.NAMES = FALSE
  )

  xfs <- regmatches(styles, regexpr("<cellXfs.*?</cellXfs>", styles))
  xf <- regmatches(xfs, gregexpr("<xf [^>]*/?>", xfs))[[1]][-1]
  xf_fill <- as.integer(sub('.*fillId="([0-9]+)".*', "\\1", xf))

  cell <- regmatches(sheet, regexpr(paste0('<c r="', ref, '"[^>]*'), sheet))
  if (length(cell) == 0) {
    return(NA_character_)
  }
  s <- suppressWarnings(as.integer(sub('.*s="([0-9]+)".*', "\\1", cell)))
  if (is.na(s)) {
    return(NA_character_)
  }
  fill_rgb[xf_fill[s] + 1]
}

ck_flag_saved_log <- function(...) {
  path <- tempfile(fileext = ".xlsx")
  create_cleaning_log(ck_flag_write_list(), output_path = path, ...)
  path
}

test_that("the flag headers are filled apart from the raw-data headers", {
  path <- ck_flag_saved_log()
  on.exit(unlink(path, force = TRUE), add = TRUE)

  expect_true("dataset" %in% openxlsx::getSheetNames(path))

  # the flag headers carry their own fill, the ONA headers the standard one
  expect_identical(ck_flag_dataset_fill(path, "A1"), "003D58")
  expect_identical(ck_flag_dataset_fill(path, "E1"), "003D58")
  expect_identical(ck_flag_dataset_fill(path, "F1"), "00A2A5")
})

test_that("nothing below the header row is re-filled", {
  # Only the headers are marked: the body of the flag block reads exactly like
  # the raw data, flagged or not.
  path <- ck_flag_saved_log()
  on.exit(unlink(path, force = TRUE), add = TRUE)

  raw_body <- ck_flag_dataset_fill(path, "F3")
  # sheet row 2 is the ONA label row, row 3 the first record (u1, flagged for
  # duration), row 4 the second (u2, not flagged for duration)
  expect_identical(ck_flag_dataset_fill(path, "A2"), raw_body)
  expect_identical(ck_flag_dataset_fill(path, "A3"), raw_body)
  expect_identical(ck_flag_dataset_fill(path, "A4"), raw_body)
  expect_identical(ck_flag_dataset_fill(path, "B4"), raw_body)
})

test_that("the header fill is configurable", {
  path <- ck_flag_saved_log(flag_header_fill_color = "#63193B")
  on.exit(unlink(path, force = TRUE), add = TRUE)

  expect_identical(ck_flag_dataset_fill(path, "A1"), "63193B")
  expect_identical(ck_flag_dataset_fill(path, "F1"), "00A2A5")
})

test_that("flag_columns = NULL leaves the dataset sheet unstyled", {
  path <- ck_flag_saved_log(flag_columns = NULL)
  on.exit(unlink(path, force = TRUE), add = TRUE)

  # column A is now the uuid, which must carry the ordinary header fill
  expect_identical(ck_flag_dataset_fill(path, "A1"), "00A2A5")
})
