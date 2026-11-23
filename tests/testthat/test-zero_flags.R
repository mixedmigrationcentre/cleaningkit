# A batch with nothing to flag must give an empty log, not an error.

zf_data <- function() {
  data.frame(
    check.names = FALSE,
    stringsAsFactors = FALSE,
    `_uuid` = c("Unique ID", "u1", "u2"),
    `_duration` = c("Duration", "2400", "2400"),
    start = c("Start", "2026-11-01T10:00:00", "2026-11-01T12:00:00"),
    Q1 = c("Question 1", "a", "b")
  )
}

test_that("checks that find nothing return an empty log", {
  d <- zf_data()
  expect_identical(nrow(validate_duration(d)$duration_log), 0L)
  expect_identical(nrow(validate_refused(d)$refused_log), 0L)
  expect_identical(
    nrow(validate_completeness(d, min_content_cells = 1)$completeness_log),
    0L
  )
  expect_identical(
    nrow(validate_interview_time(d)$interview_time_log),
    0L
  )
  expect_length(validate_duration(d)$duration_log$check_binding, 0)
})
