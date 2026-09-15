# Load Required Packages

This function installs (if necessary) and loads all packages required
for the cleaningkit package to run. It uses the `pak` package for
efficient installation and dependency management.

## Usage

``` r
load_packages(vba = FALSE)
```

## Arguments

- vba:

  Logical. If `TRUE`, additionally install the package needed to
  **build** the VBA project behind
  [`create_cleaning_log_vba`](create_cleaning_log_vba.md):
  `RDCOMClient`, which drives Excel through COM.

  It is installed from the MMC fork `iAthmanMMC/RDCOMClient` rather than
  the upstream omegahat package, which has an issue. It is Windows-only
  and is skipped with a message elsewhere.

  Default `FALSE`: it is needed once per macro rebuild
  (`dev/build_vba_bin.R`), not to run the cleaning pipeline, and not at
  all by reviewers opening a finished `.xlsm`.
