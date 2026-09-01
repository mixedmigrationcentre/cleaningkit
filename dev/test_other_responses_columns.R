################################################################################
# dev/test_other_responses_columns.R
#
# Standalone check of the other-responses workbook. It runs on a tiny built-in
# fixture, so no project data, tool or export is needed.
#
# What it checks:
#   1. the SOURCE files in this folder produce exactly ONE "EXISTING other"
#      column (named "EXISTING other (select the most appropriate choice)")
#   2. the saved .xlsx really has that single column in its header row
#   3. the MMC colours: MMC blue header, no fill on uuid -> response_en,
#      tinted reviewer columns
#   4. the `file_name` argument
#   5. what the INSTALLED cleaningkit package produces, for comparison
#
# Run it from the package root:
#   source("dev/test_other_responses_columns.R")
#
# NOTE: if step 5 reports three "EXISTING other" columns while step 1 reports
# one, R is running the INSTALLED package, not these source files. Re-install
# (or devtools::load_all(".")) before running the real pipeline.
################################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(stringi)
  library(openxlsx)
})

if (!file.exists("R/save_other_responses.R")) {
  stop(
    "R/save_other_responses.R not found - run this from the package root, ",
    "e.g. open cleaningkit.Rproj first. Current wd: ",
    getwd()
  )
}

# ---------------------------------------------------------------------------
# 1. load the source files in THIS folder
# ---------------------------------------------------------------------------
source("R/utils.R")
source("R/save_other_responses.R")

cat("--------------------------------------------------------------\n")
cat("1. source files loaded from", normalizePath("R"), "\n")

# ---------------------------------------------------------------------------
# fixture: three "other" questions - select_one, select_multiple and text
# ---------------------------------------------------------------------------
other_db <- data.frame(
  check.names = FALSE,
  stringsAsFactors = FALSE,
  name = c("Q31_2", "Q78_1", "Q99_1"),
  ref_question = c("Q31", "Q78", "Q99"),
  full_label = c(
    "Q31. Country of nationality - other",
    "Q78. Reasons for leaving - other",
    "Q99. Anything else - other"
  ),
  list_name = c("nationality", "reasons", NA),
  q_type = c("select_one", "select_multiple", "text"),
  option_other = c("other", "other", NA),
  choices = c(
    "Somalia;;Ethiopia;;Kenya",
    "Natural disaster or environmental factors;;Conflict;;Economic reasons",
    NA
  ),
  num_choices = c(3, 3, NA)
)

tool_choices <- data.frame(
  check.names = FALSE,
  stringsAsFactors = FALSE,
  list_name = c(rep("nationality", 4), rep("reasons", 4)),
  name = c(
    "somalia", "ethiopia", "kenya", "other",
    "natural_disaster", "conflict", "economic", "other"
  ),
  label = c(
    "Somalia", "Ethiopia", "Kenya", "Other",
    "Natural disaster or environmental factors", "Conflict",
    "Economic reasons", "Other"
  )
)

# row 1 is the ONA label/description row, exactly as an export arrives
raw_data <- data.frame(
  check.names = FALSE,
  stringsAsFactors = FALSE,
  "_uuid" = c("uuid label row", "u1", "u2", "u3"),
  "username" = c("enumerator label row", "enum_a", "enum_b", "enum_a"),
  "Q31" = c("nationality label", "other", "somalia", "other"),
  "Q31_2" = c("other text label", "Somaliland", NA, "Puntland"),
  "Q78" = c("reasons label", "conflict other", NA, "natural_disaster other"),
  "Q78_1" = c("other text label", "War in my area", NA, "Floods on my farm"),
  "Q99_1" = c("free text label", NA, "nothing else to add", NA)
)

# ---------------------------------------------------------------------------
# 2. prepare the dataframe and check the reviewer columns
# ---------------------------------------------------------------------------
df <- prepare_other_responses(
  raw_data = raw_data,
  other_db = other_db,
  tool_choices = tool_choices,
  extra_columns = c("username"),
  uuid_column = "_uuid"
)

exist_cols <- grep("^EXISTING other", names(df), value = TRUE)

cat("\n2. prepare_other_responses(): ", nrow(df), " rows, ", ncol(df),
    " columns\n", sep = "")
cat("   columns:\n")
cat(paste0("     ", seq_along(names(df)), ". ", names(df), collapse = "\n"), "\n")
cat("   EXISTING other columns:", length(exist_cols), "->",
    paste(exist_cols, collapse = " | "), "\n")

stopifnot(
  "expected exactly one 'EXISTING other' column" = length(exist_cols) == 1,
  "the column should be 'EXISTING other (select the most appropriate choice)'" =
    identical(exist_cols, "EXISTING other (select the most appropriate choice)"),
  "no numbered 'EXISTING other 1/2/3' columns should remain" =
    !any(grepl("^EXISTING other [0-9]", names(df)))
)
cat("   PASS: one EXISTING other column, correctly named.\n")

# ---------------------------------------------------------------------------
# 3. save the workbook and read it back
# ---------------------------------------------------------------------------
out_dir <- file.path(tempdir(), "other_responses_test")
unlink(out_dir, recursive = TRUE)

save_other_responses(
  df = df,
  other_db = other_db,
  save_location = out_dir,
  enumerator_id = "username"
)

xlsx_path <- list.files(out_dir, pattern = "\\.xlsx$", full.names = TRUE)[1]
cat("\n3. workbook written to:\n   ", normalizePath(xlsx_path), "\n", sep = "")

header <- unlist(
  read.xlsx(xlsx_path, sheet = "Sheet1", colNames = FALSE, rows = 1),
  use.names = FALSE
)
cat("   header row in the file:\n")
cat(paste0("     ", seq_along(header), ". ", header, collapse = "\n"), "\n")

stopifnot(
  "the saved file should carry exactly one 'EXISTING other' column" =
    sum(grepl("^EXISTING other", header)) == 1
)
cat("   PASS: the saved .xlsx has one EXISTING other column.\n")

# ---------------------------------------------------------------------------
# 4. colours
# ---------------------------------------------------------------------------
wb <- loadWorkbook(xlsx_path)
cat("\n4. fills in the saved file (col -> fill):\n")
for (s in wb$styleObjects) {
  if (s$sheet != "Sheet1") next
  fill <- s$style$fill$fillFg
  cat(
    "     rows ",
    if (length(unique(s$rows)) > 2) {
      paste0(min(s$rows), "-", max(s$rows))
    } else {
      paste(unique(s$rows), collapse = ",")
    },
    " | cols ", paste(sort(unique(s$cols)), collapse = ","),
    " | ", if (is.null(fill)) "no fill (Excel white)" else paste(unlist(fill), collapse = "/"),
    "\n", sep = ""
  )
}
cat("   expected: header row = FF00A2A5, cols 1-7 = no fill,\n")
cat("             TRUE other = FFE4EFC8, EXISTING other = FFFFF1C4,\n")
cat("             INVALID other = FFFCD9D3, FOLLOW-UP/Explanation = FFE3D0DD\n")

# ---------------------------------------------------------------------------
# 5. file_name argument
# ---------------------------------------------------------------------------
save_other_responses(
  df = df,
  other_db = other_db,
  save_location = out_dir,
  enumerator_id = "username",
  file_name = "my_named_other_responses"
)
files <- basename(list.files(out_dir, pattern = "\\.xlsx$"))
cat("\n5. files in the output folder:\n")
cat(paste0("     ", files, collapse = "\n"), "\n")
stopifnot(
  "file_name should append .xlsx when it is missing" =
    "my_named_other_responses.xlsx" %in% files,
  "the default dated name should still be produced" =
    any(grepl("^\\d{4}-\\d{2}-\\d{2}_other_responses\\.xlsx$", files))
)
cat("   PASS: file_name honoured, default name unchanged.\n")

# ---------------------------------------------------------------------------
# 6. compare against the INSTALLED package
# ---------------------------------------------------------------------------
cat("\n6. installed cleaningkit package, for comparison:\n")
installed_path <- tryCatch(
  find.package("cleaningkit"),
  error = function(e) NULL
)
if (is.null(installed_path)) {
  cat("     not installed - nothing to compare.\n")
} else {
  cat("     installed at:", installed_path, "\n")
  installed_cols <- tryCatch(
    {
      d <- cleaningkit::prepare_other_responses(
        raw_data = raw_data,
        other_db = other_db,
        tool_choices = tool_choices,
        extra_columns = c("username"),
        uuid_column = "_uuid"
      )
      grep("^EXISTING other", names(d), value = TRUE)
    },
    error = function(e) paste("could not run:", conditionMessage(e))
  )
  cat("     EXISTING other columns from the installed copy:",
      length(installed_cols), "\n")
  cat(paste0("       - ", installed_cols, collapse = "\n"), "\n")
  if (length(installed_cols) != 1) {
    cat("\n     >>> The installed package is OUT OF DATE. Re-install it\n")
    cat("     >>> (or run devtools::load_all(\".\")) before using the real\n")
    cat("     >>> pipeline, otherwise the old three-column layout comes back.\n")
  } else {
    cat("     installed copy matches the source.\n")
  }
}

cat("\n--------------------------------------------------------------\n")
cat("All source-level checks passed. Open the workbook above to eyeball\n")
cat("the colours:\n   ", normalizePath(xlsx_path), "\n", sep = "")
cat("--------------------------------------------------------------\n")
