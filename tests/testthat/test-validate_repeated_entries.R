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

# --------------------------------------------------------------------------
# labelled exports
# --------------------------------------------------------------------------

test_that("a labelled None closes the list and no 996 is written", {
  df <- ck_rep_dataset("u1")
  df <- ck_rep_set(
    df,
    "u1",
    list(
      Q98 = "Afghanistan",
      Q99 = "Bamyan (city)",
      Q102 = "Afghanistan",
      Q103 = "Bamyan (city)",
      Q106 = "None"
    )
  )

  log <- ck_rep_run(df)$repeated_entries_log
  # None moves up into location 2 and location 3 is blanked, not set to 996
  expect_equal(ck_rep_new(log, "u1", "Q102"), "None")
  expect_equal(ck_rep_new(log, "u1", "Q106"), "blank")
  expect_false(any(grepl("'996'", log$issue)))
})

test_that("a full labelled list gets the None label in the freed slot", {
  df <- ck_rep_dataset("u1")
  vals <- stats::setNames(
    as.list(c(
      "Iran",
      "Iran",
      "Iraq",
      "Syria",
      "Jordan",
      "Egypt",
      "Libya",
      "Mali"
    )),
    paste0("Q", 47:54)
  )
  df <- ck_rep_set(df, "u1", vals)

  log <- ck_rep_run(df)$repeated_entries_log
  expect_equal(ck_rep_new(log, "u1", "Q54"), "None")
})

# --------------------------------------------------------------------------
# dangerous locations across the whole loop
# --------------------------------------------------------------------------

test_that("a dangerous location repeated later in the loop is a possible repeat", {
  df <- ck_rep_dataset("u1")
  df <- ck_rep_set(
    df,
    "u1",
    list(
      Q98 = "Turkiye",
      Q99 = "Adana (city)",
      Q102 = "Egypt",
      Q103 = "Border",
      Q106 = "Turkiye",
      Q107 = "Adana (city)",
      Q110 = "None"
    )
  )

  out <- ck_rep_run(df)
  log <- out$repeated_entries_log
  expect_true(all(grepl("Possible repeat: location 3", log$issue)))
  expect_true(all(grepl("not next to each other", log$issue)))
  expect_equal(ck_rep_new(log, "u1", "Q106"), "None")
  expect_true(out$checked_dataset$repeated_dangerous_locations[2])
})

test_that("countries and stops repeated later in the loop are left alone", {
  df <- ck_rep_dataset("u1")
  df <- ck_rep_set(
    df,
    "u1",
    list(
      Q47 = "Iran",
      Q48 = "Afghanistan",
      Q49 = "Iran",
      Q50 = "None",
      Q56 = "Iran",
      Q57 = "Tehran",
      Q59 = "Iraq",
      Q60 = "Erbil",
      Q62 = "Iran",
      Q63 = "Tehran",
      Q65 = "None"
    )
  )
  expect_equal(nrow(ck_rep_run(df)$repeated_entries_log), 0)
})

# --------------------------------------------------------------------------
# typed "Other" answers
# --------------------------------------------------------------------------

ck_rep_choices <- function() {
  turkiye <- intToUtf8(c(84, 252, 114, 107, 105, 121, 101))
  turkiye_fa <- intToUtf8(c(0x062a, 0x0631, 0x06a9, 0x06cc, 0x0647))
  data.frame(
    list_name = c(
      rep("country_transited_3", 4),
      rep("places_stop", 3)
    ),
    name = c("181", "78", "997", "996", "TR0001", "TR0035", "9997"),
    label = c(
      turkiye,
      "Iran",
      "Other",
      "None",
      "Adana (city)",
      "Van (city)",
      "Other"
    ),
    `label::persian (fa)` = c(
      turkiye_fa,
      "Iran",
      "Other",
      "None",
      "Adana",
      "Van",
      "Other"
    ),
    cf = c(NA, NA, NA, NA, "181", "181", NA),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

test_that("a typed country in another spelling or language matches the picked one", {
  turkiye <- intToUtf8(c(84, 252, 114, 107, 105, 121, 101))
  turkiye_fa <- intToUtf8(c(0x062a, 0x0631, 0x06a9, 0x06cc, 0x0647))
  df <- ck_rep_dataset(c("alias", "persian", "typo", "other_country"))
  base <- list(Q56 = turkiye, Q57 = "Van (city)", Q59 = "Other country")
  df <- ck_rep_set(
    df,
    "alias",
    c(base, Q59_1 = "Turkey", Q60_1 = "Van", Q62 = "None")
  )
  df <- ck_rep_set(
    df,
    "persian",
    c(base, Q59_1 = turkiye_fa, Q60_1 = "van", Q62 = "None")
  )
  df <- ck_rep_set(
    df,
    "typo",
    c(base, Q59_1 = "Turkiy", Q60_1 = "Van", Q62 = "None")
  )
  df <- ck_rep_set(
    df,
    "other_country",
    c(base, Q59_1 = "Iran", Q60_1 = "Van", Q62 = "None")
  )

  log <- ck_rep_run(
    df,
    tool_choices = ck_rep_choices(),
    sections = ck_repeated_entries_sections()["main_stops"]
  )$repeated_entries_log

  expect_setequal(unique(log$uuid), c("alias", "persian", "typo"))
  expect_true(all(grepl(
    "Possible repeat: .*through the typed answer",
    log$issue
  )))
})

test_that("typed answers are not matched to choices without tool_choices", {
  df <- ck_rep_dataset("u1")
  df <- ck_rep_set(
    df,
    "u1",
    list(
      Q56 = "Turkiye",
      Q57 = "Van (city)",
      Q59 = "Other country",
      Q59_1 = "Turkey",
      Q60_1 = "Van",
      Q62 = "None"
    )
  )
  log <- ck_rep_run(df)$repeated_entries_log
  expect_equal(nrow(log), 0)
})

test_that("two nearly identical typed places are a possible repeat", {
  df <- ck_rep_dataset(c("near", "far"))
  df <- ck_rep_set(
    df,
    "near",
    list(
      Q98 = "Other",
      Q99_1 = "border between Iran and Turkey",
      Q102 = "Other",
      Q103_1 = "border between Iran and Turkey.",
      Q106 = "Other",
      Q107_1 = "the border between Iran and Turkiye",
      Q110 = "None"
    )
  )
  df <- ck_rep_set(
    df,
    "far",
    list(
      Q98 = "Other",
      Q99_1 = "border between Iran and Turkey",
      Q102 = "Other",
      Q103_1 = "the mountains near Van",
      Q106 = "None"
    )
  )

  log <- ck_rep_run(df)$repeated_entries_log
  expect_equal(unique(log$uuid), "near")
  # identical once punctuation is ignored is still only "possible": the key
  # compares the raw text
  expect_true(all(grepl("Possible repeat", log$issue)))

  log1 <- ck_rep_run(df, similarity = 1)$repeated_entries_log
  expect_true(all(grepl("location 2 ", log1$issue)))
  expect_false(any(grepl("location 3 (Q106", log1$issue, fixed = TRUE)))
})

test_that("similarity must be between 0 and 1", {
  df <- ck_rep_dataset("u1")
  expect_error(ck_rep_run(df, similarity = 0), "similarity")
  expect_error(ck_rep_run(df, similarity = 1.5), "similarity")
})

# --------------------------------------------------------------------------
# applying possible repeats
# --------------------------------------------------------------------------

ck_rep_possible_data <- function() {
  df <- ck_rep_dataset(c("u1", "u2"))
  for (u in c("u1", "u2")) {
    df <- ck_rep_set(
      df,
      u,
      list(
        Q98 = "Iran",
        Q99 = "Zahedan",
        Q102 = "Iraq",
        Q103 = "Erbil",
        Q106 = "Iran",
        Q107 = "Zahedan",
        Q110 = "None"
      )
    )
  }
  df
}

test_that("possible repeats are kept unless the reviewer accepts them", {
  df <- ck_rep_possible_data()
  log <- ck_rep_run(df)$repeated_entries_log
  cl <- ck_rep_reviewed_log(log)
  out <- ck_rep_apply(df, cl)
  expect_equal(nrow(out$audit_log), 0)
  expect_equal(out$clean_dataset$Q106[2], "Iran")
})

test_that("accepting one row of a possible repeat applies the whole record", {
  df <- ck_rep_possible_data()
  log <- ck_rep_run(df)$repeated_entries_log
  cl <- ck_rep_reviewed_log(log)
  i <- which(cl$`Survey UUID` == "u1" & cl$`Question number` == "Q106")
  cl$`Action taken`[i] <- "recoded"
  cl$`New value`[i] <- "None"

  out <- ck_rep_apply(df, cl)
  clean <- out$clean_dataset
  u1 <- clean[clean[["_uuid"]] == "u1", ]
  u2 <- clean[clean[["_uuid"]] == "u2", ]
  expect_equal(u1$Q106, "None")
  expect_true(is.na(u1$Q107))
  expect_true(is.na(u1$Q110))
  # u2 was not accepted
  expect_equal(u2$Q106, "Iran")
})
