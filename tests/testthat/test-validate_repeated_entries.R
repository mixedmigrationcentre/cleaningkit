# Tests for validate_repeated_entries().
#
# Contract:
#   * only back-to-back repeats are flagged (A, B, C, A stays);
#   * countries compare on country, stops/locations on country + place;
#   * the repeat is removed, later entries move up, the list closes with None;
#   * "Other" answers only match when the typed text matches;
#   * select-multiple sub-columns move with their entry;
#   * the data is not changed - only a log is written.

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

# a dataset with every default column blank, an ONA label row first, and one
# record per uuid in `ids`
ck_rep_dataset <- function(ids) {
  sets <- ck_repeated_entries_sections()
  cols <- unique(unlist(lapply(sets, function(s) unlist(s$slots))))
  df <- data.frame(
    `_uuid` = c("label uuid", ids),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  for (col in cols) {
    df[[col]] <- NA_character_
  }
  df
}

ck_rep_set <- function(df, uuid, values) {
  i <- which(df[["_uuid"]] == uuid)
  for (col in names(values)) {
    if (!col %in% names(df)) {
      df[[col]] <- NA_character_
    }
    df[[col]][i] <- values[[col]]
  }
  df
}

ck_rep_new <- function(log, uuid, question) {
  issue <- log$issue[log$uuid == uuid & log$question == question]
  sub(".*Suggested new value: '?([^'.]*)'?\\.$", "\\1", issue)
}

ck_rep_run <- function(df, ...) {
  suppressMessages(validate_repeated_entries(df, ...))
}

# --------------------------------------------------------------------------
# countries transited
# --------------------------------------------------------------------------

test_that("a back-to-back repeated country is removed and the list shifts up", {
  df <- ck_rep_dataset("u1")
  # Kenya, Kenya, Uganda, None
  df <- ck_rep_set(
    df,
    "u1",
    list(Q47 = "113", Q48 = "113", Q49 = "220", Q50 = "996")
  )

  out <- ck_rep_run(df)
  log <- out$repeated_entries_log

  expect_setequal(log$question, c("Q48", "Q49", "Q50"))
  expect_equal(ck_rep_new(log, "u1", "Q48"), "220")
  expect_equal(ck_rep_new(log, "u1", "Q49"), "996")
  expect_equal(ck_rep_new(log, "u1", "Q50"), "blank")
  expect_true(all(grepl(
    "^\\[Countries transited\\] Back-to-back repeat",
    log$issue
  )))
  expect_true(all(log$check_binding == "repeated_countries_transited ~/~ u1"))
})

test_that("a repeat that is not back to back is left alone", {
  df <- ck_rep_dataset("u1")
  # Kenya, Uganda, Tanzania, Kenya
  df <- ck_rep_set(
    df,
    "u1",
    list(Q47 = "113", Q48 = "220", Q49 = "209", Q50 = "113", Q51 = "996")
  )

  out <- ck_rep_run(df)
  expect_equal(nrow(out$repeated_entries_log), 0)
  expect_false(any(out$checked_dataset$repeated_countries_transited))
})

test_that("a run of three collapses to one entry", {
  df <- ck_rep_dataset("u1")
  df <- ck_rep_set(
    df,
    "u1",
    list(Q47 = "113", Q48 = "113", Q49 = "113", Q50 = "220", Q51 = "996")
  )

  log <- ck_rep_run(df)$repeated_entries_log
  expect_equal(ck_rep_new(log, "u1", "Q48"), "220")
  expect_equal(ck_rep_new(log, "u1", "Q49"), "996")
  expect_equal(ck_rep_new(log, "u1", "Q50"), "blank")
  expect_equal(ck_rep_new(log, "u1", "Q51"), "blank")
})

test_that("a full list with no None gets None in the freed slot", {
  df <- ck_rep_dataset("u1")
  vals <- stats::setNames(
    as.list(c("1", "2", "3", "4", "5", "6", "7", "7")),
    paste0("Q", 47:54)
  )
  df <- ck_rep_set(df, "u1", vals)

  log <- ck_rep_run(df)$repeated_entries_log
  expect_equal(log$question, "Q54")
  expect_equal(ck_rep_new(log, "u1", "Q54"), "996")
  expect_match(log$issue, "close the list with None (996)", fixed = TRUE)
})

test_that("a Refused closing answer moves up instead of None", {
  df <- ck_rep_dataset("u1")
  df <- ck_rep_set(df, "u1", list(Q47 = "113", Q48 = "113", Q49 = "999"))

  log <- ck_rep_run(df)$repeated_entries_log
  expect_equal(ck_rep_new(log, "u1", "Q48"), "999")
  expect_equal(ck_rep_new(log, "u1", "Q49"), "blank")
  expect_match(log$issue[1], "keep the closing answer (999)", fixed = TRUE)
})

test_that("two None answers in a row are not a repeat", {
  df <- ck_rep_dataset("u1")
  df <- ck_rep_set(df, "u1", list(Q47 = "996", Q48 = "996"))
  expect_equal(nrow(ck_rep_run(df)$repeated_entries_log), 0)
})

test_that("'Other' countries only match when the typed text matches", {
  df <- ck_rep_dataset(c("same", "different"))
  df <- ck_rep_set(
    df,
    "same",
    list(
      Q47 = "997",
      Q47_1 = "Narnia",
      Q48 = "997",
      Q48_1 = " narnia ",
      Q49 = "996"
    )
  )
  df <- ck_rep_set(
    df,
    "different",
    list(
      Q47 = "997",
      Q47_1 = "Narnia",
      Q48 = "997",
      Q48_1 = "Atlantis",
      Q49 = "996"
    )
  )

  log <- ck_rep_run(df)$repeated_entries_log
  expect_equal(unique(log$uuid), "same")
  # the typed text moves up with its country
  expect_equal(ck_rep_new(log, "same", "Q48_1"), "blank")
  expect_equal(ck_rep_new(log, "same", "Q48"), "996")
})

# --------------------------------------------------------------------------
# main stops and dangerous locations
# --------------------------------------------------------------------------

test_that("a stop is only a repeat when country and place both match", {
  df <- ck_rep_dataset(c("dup", "same_country"))
  df <- ck_rep_set(
    df,
    "dup",
    list(
      Q56 = "113",
      Q57 = "5",
      Q58 = "1",
      Q59 = "113",
      Q60 = "5",
      Q61 = "2",
      Q62 = "220",
      Q63 = "9",
      Q64 = "3",
      Q65 = "996"
    )
  )
  df <- ck_rep_set(
    df,
    "same_country",
    list(
      Q56 = "113",
      Q57 = "5",
      Q58 = "1",
      Q59 = "113",
      Q60 = "6",
      Q61 = "2",
      Q62 = "996"
    )
  )

  log <- ck_rep_run(df)$repeated_entries_log
  expect_equal(unique(log$uuid), "dup")
  expect_equal(ck_rep_new(log, "dup", "Q59"), "220")
  expect_equal(ck_rep_new(log, "dup", "Q60"), "9")
  expect_equal(ck_rep_new(log, "dup", "Q61"), "3")
  expect_equal(ck_rep_new(log, "dup", "Q62"), "996")
  expect_equal(ck_rep_new(log, "dup", "Q63"), "blank")
  expect_equal(ck_rep_new(log, "dup", "Q64"), "blank")
  expect_equal(ck_rep_new(log, "dup", "Q65"), "blank")
  expect_true(all(log$check_binding == "repeated_main_stops ~/~ dup"))
})

test_that("select-multiple sub-columns move with their stop", {
  df <- ck_rep_dataset("u1")
  for (col in c("Q58", "Q61", "Q64")) {
    df[[paste0(col, "/1")]] <- NA_character_
    df[[paste0(col, "/2")]] <- NA_character_
  }
  df <- ck_rep_set(
    df,
    "u1",
    list(
      Q56 = "113",
      Q57 = "5",
      Q58 = "1",
      `Q58/1` = "1",
      `Q58/2` = "0",
      Q59 = "113",
      Q60 = "5",
      Q61 = "1",
      `Q61/1` = "1",
      `Q61/2` = "0",
      Q62 = "220",
      Q63 = "9",
      Q64 = "2",
      `Q64/1` = "0",
      `Q64/2` = "1",
      Q65 = "996"
    )
  )

  log <- ck_rep_run(df)$repeated_entries_log
  expect_equal(ck_rep_new(log, "u1", "Q61/1"), "0")
  expect_equal(ck_rep_new(log, "u1", "Q61/2"), "1")
  expect_equal(ck_rep_new(log, "u1", "Q64/1"), "blank")
  expect_equal(ck_rep_new(log, "u1", "Q64/2"), "blank")
})

test_that("the second dangerous location is checked against Q98", {
  df <- ck_rep_dataset("u1")
  df <- ck_rep_set(
    df,
    "u1",
    list(
      Q98 = "113",
      Q99 = "5",
      Q100 = "1",
      Q102 = "113",
      Q103 = "5",
      Q104 = "2",
      Q106 = "996"
    )
  )

  log <- ck_rep_run(df)$repeated_entries_log
  expect_equal(ck_rep_new(log, "u1", "Q102"), "996")
  expect_equal(ck_rep_new(log, "u1", "Q103"), "blank")
  expect_match(
    log$issue[1],
    "location 2 (Q102/Q103) is the same as location 1 (Q98/Q99)",
    fixed = TRUE
  )
})

# --------------------------------------------------------------------------
# general behaviour
# --------------------------------------------------------------------------

test_that("the data is not changed and flag columns skip the label row", {
  df <- ck_rep_dataset(c("u1", "u2"))
  df <- ck_rep_set(df, "u1", list(Q47 = "113", Q48 = "113", Q49 = "996"))

  out <- ck_rep_run(df)
  expect_equal(out$checked_dataset[names(df)], df)
  expect_equal(
    out$checked_dataset$repeated_countries_transited,
    c(FALSE, TRUE, FALSE)
  )
  expect_named(
    out$repeated_entries_log,
    c("uuid", "old_value", "question", "issue", "check_binding")
  )
})

test_that("a subset of sections can be run on its own", {
  df <- ck_rep_dataset("u1")
  df <- ck_rep_set(
    df,
    "u1",
    list(Q47 = "113", Q48 = "113", Q56 = "1", Q57 = "1", Q59 = "1", Q60 = "1")
  )

  out <- ck_rep_run(df, sections = ck_repeated_entries_sections()["main_stops"])
  expect_true(all(grepl("^\\[Main stops\\]", out$repeated_entries_log$issue)))
  expect_null(out$checked_dataset$repeated_countries_transited)
})

test_that("missing columns warn instead of failing", {
  df <- data.frame(
    `_uuid` = c("label", "u1"),
    Q47 = c("l", "113"),
    Q48 = c("l", "113"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  expect_warning(
    out <- ck_rep_run(df),
    "not in the dataset"
  )
  expect_equal(out$repeated_entries_log$question, "Q48")
})

# --------------------------------------------------------------------------
# apply_cleaning_log(apply_repeated_entries = )
# --------------------------------------------------------------------------

# the reviewer-facing log, as read_cleaning_log() hands it to apply_cleaning_log()
ck_rep_reviewed_log <- function(
  log,
  action = NA_character_,
  new_value = NA_character_
) {
  data.frame(
    `Survey UUID` = log$uuid,
    `Question number` = log$question,
    Issue = log$issue,
    `Old value` = log$old_value,
    `Action taken` = action,
    `New value` = new_value,
    check_binding = log$check_binding,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

ck_rep_stops_data <- function() {
  df <- ck_rep_dataset(c("u1", "u2"))
  df <- ck_rep_set(
    df,
    "u1",
    list(
      Q47 = "113",
      Q48 = "113",
      Q49 = "220",
      Q50 = "996",
      Q56 = "113",
      Q57 = "5",
      Q58 = "1",
      Q59 = "113",
      Q60 = "5",
      Q61 = "2",
      Q62 = "220",
      Q63 = "9",
      Q64 = "3",
      Q65 = "996"
    )
  )
  df <- ck_rep_set(df, "u2", list(Q47 = "113", Q48 = "220", Q49 = "996"))
  df
}

ck_rep_apply <- function(df, cl, ...) {
  suppressMessages(apply_cleaning_log(df, cl, restore_types = FALSE, ...))
}

test_that("apply_cleaning_log applies repeated entries by default", {
  df <- ck_rep_stops_data()
  log <- ck_rep_run(df)$repeated_entries_log
  out <- ck_rep_apply(df, ck_rep_reviewed_log(log))
  clean <- out$clean_dataset
  u1 <- clean[clean[["_uuid"]] == "u1", ]

  expect_equal(
    unname(unlist(u1[paste0("Q", 47:50)])),
    c("113", "220", "996", NA)
  )
  expect_equal(
    unname(unlist(u1[c("Q59", "Q60", "Q61", "Q62", "Q63", "Q64", "Q65")])),
    c("220", "9", "3", "996", NA, NA, NA)
  )
  # the record without repeats and the label row are untouched
  expect_equal(clean[clean[["_uuid"]] == "u2", "Q48"], "220")
  expect_equal(clean[1, "_uuid"], "label uuid")

  # the returned log says what was applied
  cl <- out$cleaning_log
  expect_true(all(cl[["Action taken"]] %in% c("recoded", "delete_data_point")))
  expect_equal(cl[["New value"]][cl[["Question number"]] == "Q48"], "220")
  expect_true(is.na(cl[["New value"]][cl[["Question number"]] == "Q50"]))
})

test_that("the suggestion wins over what the reviewer filled in", {
  df <- ck_rep_stops_data()
  log <- ck_rep_run(df)$repeated_entries_log
  cl <- ck_rep_reviewed_log(log, action = "no_action")
  cl[["Action taken"]][cl[["Question number"]] == "Q48"] <- "recoded"
  cl[["New value"]][cl[["Question number"]] == "Q48"] <- "999"

  expect_message(
    out <- apply_cleaning_log(df, cl, restore_types = FALSE),
    "differed from what the reviewer filled in"
  )
  expect_equal(
    out$clean_dataset[out$clean_dataset[["_uuid"]] == "u1", "Q48"],
    "220"
  )
})

test_that("apply_repeated_entries = FALSE applies only the reviewer's choices", {
  df <- ck_rep_stops_data()
  log <- ck_rep_run(df)$repeated_entries_log
  cl <- ck_rep_reviewed_log(log)
  cl[["Action taken"]][cl[["Question number"]] == "Q48"] <- "recoded"
  cl[["New value"]][cl[["Question number"]] == "Q48"] <- "220"

  out <- ck_rep_apply(df, cl, apply_repeated_entries = FALSE)
  u1 <- out$clean_dataset[out$clean_dataset[["_uuid"]] == "u1", ]
  expect_equal(
    unname(unlist(u1[paste0("Q", 47:50)])),
    c("113", "220", "220", "996")
  )
  expect_equal(u1[["Q59"]], "113")
  expect_equal(out$cleaning_log, cl)
})

test_that("a discarded survey is still removed", {
  df <- ck_rep_stops_data()
  log <- ck_rep_run(df)$repeated_entries_log
  cl <- ck_rep_reviewed_log(log)
  cl <- rbind(
    cl,
    data.frame(
      `Survey UUID` = "u1",
      `Question number` = NA,
      Issue = "Too short",
      `Old value` = NA,
      `Action taken` = "discard",
      `New value` = NA,
      check_binding = "duration_check ~/~ u1",
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  )

  out <- ck_rep_apply(df, cl)
  expect_false("u1" %in% out$clean_dataset[["_uuid"]])
})

test_that("rows from other checks are not touched", {
  df <- ck_rep_stops_data()
  cl <- data.frame(
    `Survey UUID` = "u2",
    `Question number` = "Q48",
    Issue = "[check_01] Something else",
    `Old value` = "220",
    `Action taken` = NA,
    `New value` = NA,
    check_binding = "check_01 ~/~ u2",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  out <- ck_rep_apply(df, cl)
  expect_equal(nrow(out$audit_log), 0)
})
