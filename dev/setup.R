# Setup Script for Package Development
# Automates updating dependencies in DESCRIPTION, documenting, and checking the package.

# 1. Amend DESCRIPTION with dependencies found in R files
if (requireNamespace("attachment", quietly = TRUE)) {
  message("--> Amending DESCRIPTION with attachment::att_amend_desc()...")
  attachment::att_amend_desc()
} else {
  warning("Package 'attachment' is not installed. Skipping DESCRIPTION amendment.")
}

# 2. Document the package (updates NAMESPACE and Rd files)
if (requireNamespace("devtools", quietly = TRUE)) {
  message("--> Documenting package with devtools::document()...")
  devtools::document()
} else {
  stop("Package 'devtools' is required but not installed.")
}

# 3. Check the package
if (requireNamespace("devtools", quietly = TRUE)) {
  message("--> Checking package with devtools::check(vignettes = FALSE)...")
  # Vignettes are skipped by default to avoid Pandoc path issues outside RStudio
  devtools::check(vignettes = FALSE, error_on = "error")
}
