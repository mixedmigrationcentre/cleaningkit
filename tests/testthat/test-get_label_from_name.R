# get_label_from_name() and the label_column that prepare_other_responses()
# passes to it. prepare_other_responses() used to call
# get_label_from_name(..., label_column = preferred_language) when the function
# had no such argument; the "unused argument" error was swallowed by a
# tryCatch(), so every select_multiple label fell through to the raw code
# whenever the language fallback was switched off.

label_test_choices <- function() {
  data.frame(
    list_name = c("reasons", "reasons", "reasons"),
    name = c("work", "safety", "97"),
    label = c("Work", "Safety", "Other"),
    `label::Arabic (ar)` = c("Amal", "Aman", NA),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

test_that("get_label_from_name() reads the label column by default", {
  tc <- label_test_choices()
  expect_equal(get_label_from_name("reasons", "work", tc), "Work")
  expect_identical(
    get_label_from_name("reasons", "missing", tc),
    NA_character_
  )
})

test_that("get_label_from_name() prefers label_column, exact or partial", {
  tc <- label_test_choices()
  expect_equal(
    get_label_from_name(
      "reasons",
      "work",
      tc,
      label_column = "label::Arabic (ar)"
    ),
    "Amal"
  )
  expect_equal(
    get_label_from_name("reasons", "safety", tc, label_column = "arabic"),
    "Aman"
  )
})

test_that("get_label_from_name() falls back to label when label_column has nothing", {
  tc <- label_test_choices()
  # the choice has no Arabic label
  expect_equal(
    get_label_from_name("reasons", "97", tc, label_column = "Arabic"),
    "Other"
  )
  # no such column
  expect_equal(
    get_label_from_name("reasons", "work", tc, label_column = "French"),
    "Work"
  )
})

test_that("prepare_other_responses() resolves labels through get_label_from_name()", {
  raw_data <- data.frame(
    `_uuid` = c("u1", "u2"),
    Q86_b = c("work 97", "safety"),
    Q86_b_1 = c("Looking for family", NA),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  other_db <- data.frame(
    name = "Q86_b_1",
    full_label = "Other reason for leaving",
    list_name = "reasons",
    q_type = "select_multiple",
    ref_question = "Q86_b",
    choices = "Work;;Safety;;Other",
    option_other = "97",
    stringsAsFactors = FALSE
  )

  # Without the language fallback the only route to a label is
  # get_label_from_name(); before the fix this produced "work;\n97".
  out <- prepare_other_responses(
    raw_data,
    other_db,
    label_test_choices(),
    skip_label_row = FALSE,
    label_language_fallback = FALSE
  )
  expect_equal(out$selected_choices, "Work;\nOther")

  out_ar <- prepare_other_responses(
    raw_data,
    other_db,
    label_test_choices(),
    skip_label_row = FALSE,
    label_language_fallback = FALSE,
    preferred_language = "Arabic"
  )
  expect_equal(out_ar$selected_choices, "Amal;\nOther")
})
