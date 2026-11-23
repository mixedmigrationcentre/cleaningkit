# A discarded survey: only real changes on it contradict the discard.

rcd_case <- function(second_action, second_new = NA) {
  raw <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    `_uuid` = c("u1", "u2"),
    Q1 = c("a", "b")
  )
  log <- data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    `Survey UUID` = c("u1", "u1"),
    `Question number` = c("_duration", "Q1"),
    `Old value` = c("5", "a"),
    `New value` = c(NA, second_new),
    `Action taken` = c("discard", second_action)
  )
  suppressMessages(review_cleaned_data(
    raw_dataset = raw,
    clean_dataset = raw[2, , drop = FALSE],
    cleaning_log = log,
    skip_label_row = FALSE,
    verbose = FALSE
  ))
}

test_that("a no-action row on a discarded survey is not a contradiction", {
  res <- rcd_case("no_action")
  expect_false("cell_change_for_discarded_uuid" %in% res$check_type)
})

test_that("a real change on a discarded survey is still reported", {
  res <- rcd_case("recoded", "z")
  expect_true("cell_change_for_discarded_uuid" %in% res$check_type)
})
