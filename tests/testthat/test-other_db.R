# Tests for parent-question resolution in get_other_labels() / get_other_db().
#
# Background: the parent of an "other" text question used to be read from the
# first ${question} reference in the relevance expression, which is wrong for
# compound expressions. Q32_1 relevant on
#   ${Q31} = 'kenya' and selected(${Q32}, 'other')
# resolved to Q31 ("What is your country of nationality?") instead of Q32
# ("What region are you from in your country of nationality?").

# --- a small but realistic 4Mi-style tool -----------------------------------

test_tool_survey <- function() {
  ts <- data.frame(
    name = c(
      "Q31", "Q31_1",
      "Q32", "Q32_1",
      "Q86_b", "Q86_b_1",
      "Q45_3", "Q45_3_1",
      "Q78", "Q78_1",
      "Q99", "Q99_1",
      "Q60", "Q60_2",
      "Q70_1",
      "Q88", "Q88_1",
      "Q90", "Q90_1"
    ),
    type = c(
      "select_one country", "text",
      "select_one region", "text",
      "select_multiple reasons", "text",
      "select_one services", "text",
      "select_multiple support", "text",
      "select_one status", "text",
      "select_one docs", "text",
      "text",
      "select_one yesno", "text",
      "integer", "text"
    ),
    relevant = c(
      NA, "selected(${Q31}, 'other')",
      "${Q31} != 'other'", "${Q31} = 'kenya' and selected(${Q32}, 'other')",
      "${Q31} = 'somalia'", "${Q31} = 'somalia' and selected(${Q86_b}, 'other')",
      NA, "selected(${Q45_3}, 'other_service')",
      NA, "selected(${Q78}, 'other')",
      NA, NA,
      NA, "${Q31} = 'ethiopia' and selected(${Q60}, 'other')",
      "selected(${Q78}, 'other')",
      NA, "${Q31} = 'kenya' and selected(${Q88}, 96)",
      NA, "${Q90} > 2 and selected(${Q78}, 'other')"
    ),
    label = c(
      "What is your country of nationality?", "Other country of nationality",
      "What region are you from in your country of nationality?", "Other region of nationality",
      "Why did you leave your country?", "Other reason for leaving",
      "Which service did you use?", "Other service used",
      "What support do you need?", "Other support needed",
      "What is your current status?", "Other status",
      "Which documents do you hold?", "Other documents held",
      "Orphan other question",
      "Do you have a phone?", "Other phone answer",
      "How many times did you move?", "Other movement detail"
    ),
    stringsAsFactors = FALSE
  )
  ts$q_type <- vapply(
    strsplit(ts$type, " "),
    function(x) x[1],
    character(1)
  )
  ts$list_name <- vapply(
    strsplit(ts$type, " "),
    function(x) if (length(x) > 1) x[2] else NA_character_,
    character(1)
  )
  ts
}

test_tool_choices <- function() {
  data.frame(
    list_name = c(
      rep("country", 3), rep("region", 3), rep("reasons", 3),
      rep("services", 2), rep("support", 2), rep("status", 2),
      rep("docs", 2), rep("yesno", 3)
    ),
    name = c(
      "kenya", "somalia", "other",
      "coast", "nairobi", "other",
      "conflict", "economic", "other",
      "health", "other_service",
      "cash", "other",
      "asylum", "other",
      "passport", "other",
      "yes", "no", "96"
    ),
    label = c(
      "Kenya", "Somalia", "Other",
      "Coast", "Nairobi", "Other",
      "Conflict", "Economic reasons", "Other",
      "Health", "Other service",
      "Cash", "Other",
      "Asylum seeker", "Other",
      "Passport", "Other",
      "Yes", "No", "Other"
    ),
    stringsAsFactors = FALSE
  )
}

# --- relevance-expression parsing -------------------------------------------

test_that("get_ref_question() is vectorized and returns the first reference", {
  expect_equal(
    get_ref_question(c("selected(${Q78}, 'other')", "${Q31} = 'kenya'", NA)),
    c("Q78", "Q31", NA_character_)
  )
  expect_equal(get_ref_question(NULL), NA_character_)
  # documented behaviour: the FIRST reference, which is why it must not be
  # used on its own to find the parent of an "other" question
  expect_equal(
    get_ref_question("${Q31} = 'kenya' and selected(${Q32}, 'other')"),
    "Q31"
  )
})

test_that(".relevant_refs() returns every reference in order", {
  expect_equal(
    .relevant_refs("${Q31} = 'kenya' and selected(${Q32}, 'other')"),
    c("Q31", "Q32")
  )
  expect_equal(.relevant_refs(NA), character(0))
  expect_equal(.relevant_refs(""), character(0))
  expect_equal(.relevant_refs(NULL), character(0))
})

test_that(".relevant_ref_options() pairs each reference with its own option", {
  pairs <- .relevant_ref_options(
    "${Q31} = 'kenya' and selected(${Q32}, 'other')"
  )
  expect_equal(pairs$ref, c("Q31", "Q32"))
  expect_equal(pairs$option, c("kenya", "other"))

  # unquoted numeric options
  num <- .relevant_ref_options("${Q31} = 'kenya' and selected(${Q88}, 96)")
  expect_equal(num$option[num$ref == "Q88"], "96")

  expect_equal(nrow(.relevant_ref_options(NA)), 0L)
})

test_that(".parent_name_candidates() strips numeric suffixes only", {
  expect_equal(.parent_name_candidates("Q32_1"), "Q32")
  expect_equal(.parent_name_candidates("Q86_b_1"), "Q86_b")
  expect_equal(.parent_name_candidates("Q45_3_1"), c("Q45_3", "Q45"))
  expect_equal(.parent_name_candidates("Q60_2"), "Q60")
  expect_equal(.parent_name_candidates("Q31"), character(0))
})

test_that(".relevant_option_for_ref() does not over-capture", {
  expr <- "${Q31} = 'kenya' and selected(${Q32}, 'other')"
  expect_equal(.relevant_option_for_ref(expr, "Q32"), "other")
  expect_equal(.relevant_option_for_ref(expr, "Q31"), "kenya")
  # the greedy regex this replaced returned
  # "kenya' and selected(${Q32}, 'other" for the same expression
  expect_false(grepl("selected", .relevant_option_for_ref(expr, "Q32")))
})

# --- parent-question resolution ---------------------------------------------

test_that(".resolve_ref_question() follows the naming convention", {
  ts <- test_tool_survey()
  others <- ts[
    ts$type == "text" & (grepl("_1$", ts$name) | ts$name == "Q60_2"),
  ]
  res <- .resolve_ref_question(others$name, others$relevant, ts)

  expected <- c(
    Q31_1 = "Q31",
    Q32_1 = "Q32", # the reported bug: was Q31
    Q86_b_1 = "Q86_b", # strips _1 only, not _b_1
    Q45_3_1 = "Q45_3", # nested numeric suffix
    Q78_1 = "Q78",
    Q99_1 = "Q99", # no relevance expression at all
    Q60_2 = "Q60", # other_text_types entry, _2 suffix
    Q70_1 = "Q78", # no Q70 in the tool -> relevance expression
    Q88_1 = "Q88", # numeric "other" code
    Q90_1 = "Q78" # Q90 exists but is an integer, not a select
  )
  for (nm in names(expected)) {
    expect_equal(
      res$ref_question[res$name == nm],
      expected[[nm]],
      info = nm
    )
  }
})

test_that(".resolve_ref_question() reports how each parent was found", {
  ts <- test_tool_survey()
  others <- ts[ts$type == "text" & grepl("_1$", ts$name), ]
  res <- .resolve_ref_question(others$name, others$relevant, ts)

  expect_equal(res$resolved_via[res$name == "Q32_1"], "name_and_relevance")
  expect_equal(res$resolved_via[res$name == "Q99_1"], "name")
  expect_equal(res$resolved_via[res$name == "Q70_1"], "relevance")
  expect_equal(res$resolved_via[res$name == "Q90_1"], "relevance")
})

test_that(".resolve_ref_question() copes with missing relevance expressions", {
  ts <- test_tool_survey()
  res <- .resolve_ref_question(
    c("Q32_1", "Q86_b_1", "Q45_3_1"),
    NULL,
    ts
  )
  expect_equal(res$ref_question, c("Q32", "Q86_b", "Q45_3"))
  expect_true(all(res$resolved_via == "name"))
})

test_that(".resolve_ref_question() falls back to the question itself", {
  ts <- test_tool_survey()
  res <- .resolve_ref_question("QZZ_1", NA_character_, ts)
  expect_equal(res$ref_question, "QZZ_1")
  expect_equal(res$resolved_via, "self")
})

# --- get_other_labels() -----------------------------------------------------

test_that("get_other_labels() labels each other question with its parent", {
  ts <- test_tool_survey()
  wd <- withr::local_tempdir()
  withr::local_dir(wd)

  labs <- suppressWarnings(
    get_other_labels(ts, preferred_language = NULL, other_text_types = "Q60_2")
  )

  expect_equal(names(labs), c("name", "ref_question", "full_label"))
  expect_equal(nrow(labs), 10L)
  expect_equal(
    labs$full_label[labs$name == "Q32_1"],
    "What region are you from in your country of nationality?"
  )
  expect_equal(
    labs$full_label[labs$name == "Q86_b_1"],
    "Why did you leave your country?"
  )
  expect_equal(
    labs$full_label[labs$name == "Q60_2"],
    "Which documents do you hold?"
  )
  expect_false(any(is.na(labs$full_label)))
  # questions that were already resolved correctly stay correct
  expect_equal(labs$ref_question[labs$name == "Q78_1"], "Q78")
})

test_that("get_other_labels() warns about unconfirmed parents", {
  ts <- test_tool_survey()
  wd <- withr::local_tempdir()
  withr::local_dir(wd)

  expect_warning(
    get_other_labels(ts, preferred_language = NULL),
    "Q70_1"
  )
})

test_that("get_other_labels() works without a `relevant` column", {
  ts <- test_tool_survey()
  ts$relevant <- NULL
  wd <- withr::local_tempdir()
  withr::local_dir(wd)

  labs <- suppressWarnings(
    get_other_labels(ts, preferred_language = NULL, other_text_types = "Q60_2")
  )
  expect_equal(labs$ref_question[labs$name == "Q32_1"], "Q32")
  expect_equal(labs$ref_question[labs$name == "Q86_b_1"], "Q86_b")
  expect_equal(labs$ref_question[labs$name == "Q45_3_1"], "Q45_3")
})

# --- get_other_db() ---------------------------------------------------------

test_that("get_other_db() picks the right option_other and choice list", {
  ts <- test_tool_survey()
  tc <- test_tool_choices()
  wd <- withr::local_tempdir()
  withr::local_dir(wd)

  labs <- suppressWarnings(
    get_other_labels(ts, preferred_language = NULL, other_text_types = "Q60_2")
  )
  db <- get_other_db(ts, tc, labs, preferred_language = NULL)

  expect_equal(db$option_other[db$name == "Q32_1"], "other")
  expect_equal(db$option_other[db$name == "Q45_3_1"], "other_service")
  expect_equal(db$option_other[db$name == "Q88_1"], "96")

  # the parent's own list and type follow the corrected ref_question
  expect_equal(db$list_name[db$name == "Q32_1"], "region")
  expect_equal(db$q_type[db$name == "Q86_b_1"], "select_multiple")

  # the "other" option is excluded from the recoding dropdown
  expect_equal(
    sort(strsplit(db$choices[db$name == "Q32_1"], ";;")[[1]]),
    c("Coast", "Nairobi")
  )
  expect_equal(
    sort(strsplit(db$choices[db$name == "Q88_1"], ";;")[[1]]),
    c("No", "Yes")
  )
})
