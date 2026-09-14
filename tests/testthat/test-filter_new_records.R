make_export <- function(path, ids, label = TRUE) {
  df <- data.frame(
    `_uuid` = ids,
    start = paste0("2026-09-", sprintf("%02d", seq_along(ids))),
    Q13 = rep("Kenya", length(ids)),
    username = rep("enum_a", length(ids)),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  if (label) {
    lab <- df[1, , drop = FALSE]
    lab[1, ] <- c(
      "Unique ID",
      "Start time",
      "Country of interview",
      "Enumerator"
    )
    df <- rbind(lab, df)
  }
  openxlsx::write.xlsx(df, file = path, overwrite = TRUE)
  invisible(df)
}

read_output <- function(path) {
  as.data.frame(
    readxl::read_excel(path, col_types = "text"),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

test_that("the new export is reduced to records not seen before", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "round1_export.xlsx"), paste0("u", 1:5))
  make_export(file.path(dd, "ona_export.xlsx"), paste0("u", 1:8))

  res <- filter_new_records(data_folder = dd, verbose = FALSE)

  expect_equal(res$new_export, "ona_export.xlsx")
  expect_equal(res$previous_file, "round1_export.xlsx")
  expect_equal(res$n_kept, 3)
  expect_equal(res$n_dropped, 5)

  out <- read_output(file.path(dd, "data.xlsx"))
  expect_equal(nrow(out), 4) # label row + 3 records
  expect_equal(out[["_uuid"]][1], "Unique ID")
  expect_equal(out[["_uuid"]][-1], c("u6", "u7", "u8"))
  expect_equal(names(out), c("_uuid", "start", "Q13", "username"))
})

test_that("inputs are archived and the folder is left clean", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "prev.xlsx"), paste0("u", 1:5))
  make_export(file.path(dd, "new.xlsx"), paste0("u", 1:8))

  filter_new_records(data_folder = dd, verbose = FALSE)

  expect_false(file.exists(file.path(dd, "prev.xlsx")))
  expect_false(file.exists(file.path(dd, "new.xlsx")))
  expect_length(list.files(file.path(dd, "archive")), 2)
  expect_setequal(
    list.files(dd),
    c("archive", "data.xlsx", "processed_uuids.csv")
  )
})

test_that("archive = FALSE deletes the inputs outright", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "prev.xlsx"), paste0("v", 1:4))
  make_export(file.path(dd, "new.xlsx"), paste0("v", 1:6))

  res <- filter_new_records(data_folder = dd, archive = FALSE, verbose = FALSE)

  expect_false(dir.exists(file.path(dd, "archive")))
  expect_setequal(list.files(dd), c("data.xlsx", "processed_uuids.csv"))
  expect_equal(res$n_kept, 2)
})

test_that("the ledger keeps earlier rounds from reappearing", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "round1.xlsx"), paste0("u", 1:5))
  make_export(file.path(dd, "round2.xlsx"), paste0("u", 1:8))
  filter_new_records(data_folder = dd, verbose = FALSE)

  # third round: data.xlsx now holds only u6-u8, so a plain two-file
  # comparison would let u1-u5 back in
  make_export(file.path(dd, "round3.xlsx"), paste0("u", 1:12))
  res <- filter_new_records(data_folder = dd, verbose = FALSE)

  out <- read_output(file.path(dd, "data.xlsx"))
  expect_equal(res$previous_file, "data.xlsx")
  expect_equal(res$n_kept, 4)
  expect_equal(out[["_uuid"]][-1], c("u9", "u10", "u11", "u12"))
  expect_false(any(paste0("u", 1:5) %in% out[["_uuid"]]))

  ledger <- utils::read.csv(
    file.path(dd, "processed_uuids.csv"),
    colClasses = "character"
  )
  expect_setequal(ledger$uuid, paste0("u", 1:12))
})

test_that("a single export is filtered against the ledger alone", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "round1.xlsx"), paste0("u", 1:5))
  make_export(file.path(dd, "round2.xlsx"), paste0("u", 1:8))
  filter_new_records(data_folder = dd, verbose = FALSE)
  file.remove(file.path(dd, "data.xlsx"))

  make_export(file.path(dd, "round3.xlsx"), paste0("u", 1:11))
  res <- filter_new_records(data_folder = dd, verbose = FALSE)

  expect_true(is.na(res$previous_file))
  expect_equal(res$n_kept, 3)
  out <- read_output(file.path(dd, "data.xlsx"))
  expect_equal(out[["_uuid"]][-1], c("u9", "u10", "u11"))
})

test_that("nothing is touched when the same export is downloaded twice", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "prev.xlsx"), paste0("u", 1:8))
  make_export(file.path(dd, "same.xlsx"), paste0("u", 1:8))
  before <- sort(list.files(dd))

  expect_error(
    filter_new_records(data_folder = dd, verbose = FALSE),
    "No new records"
  )
  expect_equal(sort(list.files(dd)), before)
})

test_that("skip_label_row = FALSE treats row one as data", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "prev.xlsx"), paste0("w", 1:3), label = FALSE)
  make_export(file.path(dd, "new.xlsx"), paste0("w", 1:5), label = FALSE)

  filter_new_records(data_folder = dd, skip_label_row = FALSE, verbose = FALSE)

  out <- read_output(file.path(dd, "data.xlsx"))
  expect_equal(out[["_uuid"]], c("w4", "w5"))
})

test_that("use_ledger = FALSE compares the two files only", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "prev.xlsx"), paste0("x", 1:3))
  make_export(file.path(dd, "new.xlsx"), paste0("x", 1:6))

  res <- filter_new_records(data_folder = dd, use_ledger = FALSE, verbose = FALSE)

  expect_false(file.exists(file.path(dd, "processed_uuids.csv")))
  expect_true(is.na(res$ledger_path))
  expect_equal(res$n_kept, 3)
})

test_that("Excel lock files are ignored", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "prev.xlsx"), paste0("z", 1:2))
  make_export(file.path(dd, "new.xlsx"), paste0("z", 1:5))
  writeLines("lock", file.path(dd, "~$new.xlsx"))

  res <- filter_new_records(data_folder = dd, verbose = FALSE)
  expect_equal(res$n_kept, 3)
})

test_that("records without a uuid are kept and reported", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "prev.xlsx"), paste0("m", 1:2))
  make_export(file.path(dd, "new.xlsx"), c(paste0("m", 1:4), NA))

  expect_warning(
    res <- filter_new_records(data_folder = dd, verbose = FALSE),
    "have no _uuid"
  )
  expect_equal(res$n_kept, 3)
})

test_that("equal record counts fall back to the most recent file", {
  dd <- withr::local_tempdir()
  make_export(file.path(dd, "older.xlsx"), paste0("q", 1:4))
  Sys.sleep(1.1)
  make_export(file.path(dd, "newer.xlsx"), c(paste0("q", 1:3), "q9"))

  expect_warning(
    res <- filter_new_records(data_folder = dd, verbose = FALSE),
    "most recently modified"
  )
  expect_equal(res$new_export, "newer.xlsx")
  expect_equal(res$n_kept, 1)
})

test_that("bad inputs are rejected with a clear message", {
  dd <- withr::local_tempdir()

  expect_error(
    filter_new_records(data_folder = file.path(dd, "nope")),
    "does not exist"
  )
  expect_error(filter_new_records(data_folder = dd), "No Excel files found")

  make_export(file.path(dd, "a.xlsx"), paste0("y", 1:3))
  expect_error(filter_new_records(data_folder = dd), "Only one Excel file")
  expect_error(
    filter_new_records(data_folder = dd, uuid_column = "nope"),
    "not found in"
  )
  expect_error(
    filter_new_records(data_folder = dd, output_name = "data.csv"),
    "must be a single file name"
  )

  make_export(file.path(dd, "b.xlsx"), paste0("y", 1:4))
  make_export(file.path(dd, "c.xlsx"), paste0("y", 1:5))
  expect_error(filter_new_records(data_folder = dd), "Expected at most 2")
})
