# Choice labels can contain a single ";". The "correct to existing" choices are
# joined and split on ";;" only, so such a label stays one choice.

ck_semi_label <- function() {
  "Lack of freedom (of expression; movement; association)/repressive government"
}

ck_semi_choices <- function() {
  data.frame(
    list_name = "reasons_rights",
    name = c("1", "2", "97"),
    label = c(ck_semi_label(), "Religious discrimination", "Other"),
    stringsAsFactors = FALSE
  )
}

ck_semi_data <- function() {
  data.frame(
    `_uuid` = c("label row", "u1"),
    Q81 = c("Q81", "97"),
    `Q81/1` = c("Q81/1", "0"),
    `Q81/2` = c("Q81/2", "0"),
    `Q81/97` = c("Q81/97", "1"),
    Q81_1 = c("Q81_1", "no freedom of speech"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

ck_semi_row <- function(existing_other) {
  data.frame(
    uuid = "u1",
    ref_type = "select_multiple",
    question_name = "Q81_1",
    ref_question = "Q81",
    response_en = "no freedom of speech",
    existing_other = existing_other,
    list_name = "reasons_rights",
    option_other = "97",
    stringsAsFactors = FALSE
  )
}

test_that("a label containing ';' is recoded as one choice", {
  expect_no_warning(
    rows <- .build_recode_rows(
      ck_semi_row(ck_semi_label()),
      ck_semi_data(),
      ck_semi_choices(),
      uuid_column = "_uuid",
      sm_separator = "/",
      skip_label_row = TRUE
    )
  )
  expect_equal(rows$new_value[rows$question == "Q81/1"], "1")
  expect_equal(rows$new_value[rows$question == "Q81/97"], "0")
})

test_that("several choices separated by ';;' are each recoded", {
  rows <- .build_recode_rows(
    ck_semi_row(paste0(ck_semi_label(), ";;Religious discrimination")),
    ck_semi_data(),
    ck_semi_choices(),
    uuid_column = "_uuid",
    sm_separator = "/",
    skip_label_row = TRUE
  )
  expect_equal(rows$new_value[rows$question == "Q81/1"], "1")
  expect_equal(rows$new_value[rows$question == "Q81/2"], "1")
})
