# Round memory: the survey IDs already checked, kept in very hidden sheets of
# the workbooks a round produces, so the next round needs only the new ONA
# download and the last workbook.

# An ONA download: label row, then one survey per ID.
ck_ri_download <- function(ids, q1 = paste0("answer ", ids)) {
  data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    `_uuid` = c("Unique ID", ids),
    `_submission_time` = c("Submitted", rep("2026-11-01", length(ids))),
    today = c("Date", rep("2026-11-01", length(ids))),
    Q1 = c("Question 1", q1),
    username = c("Enumerator", rep("enum_a", length(ids)))
  )
}

# Sheet name -> state, read from the workbook XML: openxlsx::loadWorkbook()
# reports very hidden sheets as visible.
ck_ri_sheet_states <- function(path) {
  d <- withr::local_tempdir()
  utils::unzip(path, "xl/workbook.xml", exdir = d)
  xml <- paste(
    readLines(file.path(d, "xl", "workbook.xml"), warn = FALSE),
    collapse = ""
  )
  tags <- regmatches(xml, gregexpr("<sheet [^>]*>", xml))[[1]]
  stats::setNames(
    sub('.*state="([^"]*)".*', "\\1", tags),
    sub('.*name="([^"]*)".*', "\\1", tags)
  )
}

ck_ri_write_list <- function(dataset) {
  list(
    cleaning_log = data.frame(
      uuid = dataset[["_uuid"]][2],
      old_value = "x",
      question = "Q1",
      issue = "test",
      check_binding = paste0("check_01 ~/~ ", dataset[["_uuid"]][2]),
      stringsAsFactors = FALSE
    ),
    checked_dataset = dataset
  )
}

ck_ri_tool <- function() {
  list(
    survey = data.frame(
      type = "text",
      name = "Q1",
      `label::English` = "Question 1",
      check.names = FALSE
    ),
    choices = data.frame(list_name = "yn", name = "1", label = "Yes")
  )
}

test_that("fingerprints follow the answers, not the ONA metadata", {
  a <- ck_ri_download(c("u1", "u2"))
  b <- a
  b[["_submission_time"]][2:3] <- "2026-11-20"
  expect_identical(
    round_fingerprint(a)$fingerprint,
    round_fingerprint(b)$fingerprint
  )

  b$Q1[3] <- "changed"
  fa <- round_fingerprint(a)
  fb <- round_fingerprint(b)
  expect_identical(fa$uuid, c("u1", "u2"))
  expect_identical(fa$fingerprint[1], fb$fingerprint[1])
  expect_false(identical(fa$fingerprint[2], fb$fingerprint[2]))
  expect_identical(attr(fa, "columns"), c("today", "Q1", "username"))
})

test_that("a new column in a later download does not change the fingerprint", {
  a <- ck_ri_download(c("u1", "u2"))
  b <- a
  b$Q99 <- c("New module", "x", "y")
  cols <- attr(round_fingerprint(a), "columns")
  expect_identical(
    round_fingerprint(a)$fingerprint,
    round_fingerprint(b, columns = cols)$fingerprint
  )
})

test_that("keep_new_records drops checked surveys and keeps the label row", {
  dl <- ck_ri_download(paste0("u", 1:5))
  res <- keep_new_records(dl, previous = c("u1", "u2", " u3 "))
  expect_identical(res$n_total, 5L)
  expect_identical(res$n_checked_before, 3L)
  expect_identical(res$n_new, 2L)
  expect_identical(res$data[["_uuid"]], c("Unique ID", "u4", "u5"))

  first <- keep_new_records(dl)
  expect_identical(first$n_new, 5L)
  expect_error(keep_new_records(dl, uuid_column = "id"), "no `id` column")
})

test_that("ck_round_info adds this round to what earlier rounds checked", {
  r1 <- ck_round_info(
    ck_ri_download(c("u1", "u2")),
    "R1",
    tool_survey = ck_ri_tool()$survey
  )
  expect_s3_class(r1, "ck_round_info")
  expect_identical(r1$checked$uuid, c("u1", "u2"))
  expect_true(all(nzchar(r1$checked$fingerprint)))

  r2 <- ck_round_info(ck_ri_download(c("u3")), "Nov week 2", previous = r1)
  expect_setequal(r2$checked$uuid, c("u1", "u2", "u3"))
  expect_identical(r2$meta$round_name, "Nov week 2")
  expect_false(identical(r1$meta$round_id, r2$meta$round_id))
  expect_identical(r2$checked$round_name[r2$checked$uuid == "u1"], "R1")
  # the questionnaire carries over when not given again
  expect_identical(r2$tool_survey, r1$tool_survey)

  expect_error(ck_round_info(ck_ri_download("u1"), ""), "must not be empty")
  expect_output(print(r2), "Checked so far: 3")
})

test_that("the review workbook carries the round memory in very hidden sheets", {
  dir <- withr::local_tempdir()
  dl <- ck_ri_download(c("u1", "u2", "u3"))
  tool <- ck_ri_tool()
  info <- ck_round_info(
    dl,
    "R1",
    tool_survey = tool$survey,
    tool_choices = tool$choices,
    settings = list(app = strrep("a", 70000), other = "x")
  )
  path <- file.path(dir, "review.xlsx")
  suppressMessages(create_review_workbook(
    ck_ri_write_list(dl),
    path,
    round_info = info
  ))

  vis <- ck_ri_sheet_states(path)
  expect_true(all(
    vis[c("_ck_round", "_ck_checked", "_ck_survey")] == "veryHidden"
  ))
  expect_identical(unname(vis["cleaning_log"]), "visible")

  back <- read_round_info(path)
  expect_setequal(back$checked$uuid, c("u1", "u2", "u3"))
  expect_identical(back$meta$round_name, "R1")
  expect_identical(back$meta$round_id, info$meta$round_id)
  expect_identical(back$fingerprint_columns, info$fingerprint_columns)
  # long settings are split across cells and put back together
  expect_identical(nchar(back$settings$app), 70000L)
  expect_identical(back$settings$other, "x")
  expect_identical(back$tool_survey$name, "Q1")
  expect_identical(back$sources$type, "workbook")
})

test_that("the macro workbook keeps _ck_config last with the round sheets added", {
  skip_if_not(
    nzchar(ck_vba_project_path()) && file.exists(ck_vba_project_path())
  )
  dir <- withr::local_tempdir()
  dl <- ck_ri_download(c("u1", "u2"))
  path <- suppressMessages(create_review_workbook(
    ck_ri_write_list(dl),
    file.path(dir, "review.xlsm"),
    round_info = ck_round_info(dl, "R1")
  ))
  sheets <- readxl::excel_sheets(path)
  expect_identical(utils::tail(sheets, 1), "_ck_config")
  expect_true(all(c("_ck_round", "_ck_checked") %in% sheets))
  expect_identical(read_round_info(path)$meta$round_name, "R1")
})

test_that("the final workbook carries the round memory too", {
  dir <- withr::local_tempdir()
  dl <- ck_ri_download(c("u1", "u2"))
  info <- ck_round_info(dl, "R1")
  path <- file.path(dir, "final.xlsx")
  suppressMessages(export_final_output(
    raw_dataset = dl,
    clean_dataset = dl,
    combined_log = data.frame(
      `Survey UUID` = "u1",
      Date = "2026-11-01",
      check.names = FALSE
    ),
    output_path = path,
    round_info = info
  ))
  expect_identical(read_round_info(path)$meta$round_id, info$meta$round_id)
})

test_that("the next round starts from the last workbook alone", {
  dir <- withr::local_tempdir()
  r1_data <- ck_ri_download(c("u1", "u2"))
  r1 <- ck_round_info(r1_data, "R1")
  wb1 <- file.path(dir, "r1.xlsx")
  suppressMessages(create_review_workbook(
    ck_ri_write_list(r1_data),
    wb1,
    round_info = r1
  ))

  # round 2: the download holds everything so far
  dl2 <- ck_ri_download(paste0("u", 1:4))
  new2 <- keep_new_records(dl2, read_round_info(wb1))
  expect_identical(new2$data[["_uuid"]][-1], c("u3", "u4"))
  r2 <- ck_round_info(new2$data, "R2", previous = read_round_info(wb1))
  wb2 <- file.path(dir, "r2.xlsx")
  suppressMessages(create_review_workbook(
    ck_ri_write_list(new2$data),
    wb2,
    round_info = r2
  ))

  # round 3 needs only round 2's workbook: the list is cumulative
  dl3 <- ck_ri_download(paste0("u", 1:6))
  new3 <- keep_new_records(dl3, read_round_info(wb2))
  expect_identical(new3$data[["_uuid"]][-1], c("u5", "u6"))

  # uploading both workbooks gives the same answer, and the newest leads
  both <- read_round_info(c(wb1, wb2))
  expect_identical(both$meta$round_name, "R2")
  expect_identical(keep_new_records(dl3, both)$n_new, 2L)
})

test_that("old ledgers and earlier exports count as checked surveys", {
  dir <- withr::local_tempdir()
  csv <- file.path(dir, "processed_uuids.csv")
  utils::write.csv(
    data.frame(uuid = c("u1", "u2"), date_added = "2026-10-01"),
    csv,
    row.names = FALSE
  )
  old <- file.path(dir, "data.xlsx")
  openxlsx::write.xlsx(ck_ri_download(c("u3")), old)

  info <- read_round_info(c(csv, old))
  expect_setequal(info$checked$uuid, c("u1", "u2", "u3"))
  expect_identical(info$sources$type, c("ledger", "export"))
  expect_null(info$meta$round_id)
  expect_identical(
    keep_new_records(ck_ri_download(paste0("u", 1:5)), info)$n_new,
    2L
  )

  other <- file.path(dir, "notes.xlsx")
  openxlsx::write.xlsx(data.frame(x = 1), other)
  expect_error(read_round_info(other), "no round memory")
})

test_that("round_records picks the round's surveys from a later download", {
  dir <- withr::local_tempdir()
  checked <- ck_ri_download(c("u2", "u3", "u4"))
  info <- ck_round_info(checked, "R2", previous = c("u1"))
  path <- file.path(dir, "r2.xlsx")
  suppressMessages(create_review_workbook(
    ck_ri_write_list(checked),
    path,
    round_info = info
  ))
  info <- read_round_info(path, names = "r2_follow-ups_edited.xlsx")
  expect_identical(info$sources$file, "r2_follow-ups_edited.xlsx")

  # a later download: u3 was edited on ONA, u4 deleted, u5 is new
  later <- ck_ri_download(
    c("u1", "u2", "u3", "u5"),
    q1 = c("answer u1", "answer u2", "edited on ONA", "answer u5")
  )
  later$Q99 <- c("New module", "a", "b", "c", "d")
  res <- round_records(later, info)
  expect_identical(res$data[["_uuid"]], c("Unique ID", "u2", "u3"))
  expect_identical(res$changed, "u3")
  expect_identical(res$missing, "u4")
  expect_identical(res$n_round, 3L)

  expect_error(round_records(later, c("u1")), "survey IDs only")
})
