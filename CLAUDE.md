# cleaningkit

R package that cleans and validates Mixed Migration Centre 4Mi survey
data (KoboToolbox exports): `validate_*()` checks produce cleaning logs,
reviewers fill them in Excel,
[`apply_cleaning_log()`](reference/apply_cleaning_log.md) applies them.
Sister package: `analysiskit` (DesktopKit) consumes the cleaned data.

## Environment

- Windows. `Rscript` is **not on PATH**; call it as
  `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe"` from Bash.
- Some features drive Excel through COM (`RDCOMClient`, MMC fork
  `iAthmanMMC/RDCOMClient`). They need Excel installed; don’t try to run
  them in a headless check.

## Dev loop

- Full cycle: `Rscript dev/setup.R` (attachment updates DESCRIPTION
  Imports, then `devtools::document()`, then
  `devtools::check(vignettes = FALSE)`).
- Quick: `Rscript -e "devtools::document()"` and
  `Rscript -e "devtools::test(filter = 'other_db')"` (filter = test file
  stem).
- Tests: testthat 3e in `tests/testthat/`. Add or update a test with any
  behaviour change; use `withr` for temp files and options.

## Generated files: do not edit by hand

A PreToolUse hook blocks these; edit the source instead.

| Generated | Source | Rebuild |
|----|----|----|
| `man/*.Rd`, `NAMESPACE` | roxygen `#'` comments in `R/` | `devtools::document()` |
| `README.md` | `README.Rmd` | `devtools::build_readme()` |
| `docs/` | everything (pkgdown) | [`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html); CI also builds it |
| `inst/extdata/cleaningkit_vba.bin` | `inst/vba/Module1.bas`, `ThisWorkbook.cls` | `dev/build_vba_bin.R` in Excel; ask the user, see `inst/vba/README.md` |

Any change to `inst/vba/*.bas|*.cls` means the `.bin` must be rebuilt by
the user; say so explicitly.

## Conventions

- Formatting: a PostToolUse hook runs `air format` on each `.R` file
  Claude edits. Don’t fight it.
- Pipes: this package uses magrittr `%>%`; keep it consistent within a
  file.
- Errors with base [`stop()`](https://rdrr.io/r/base/stop.html) (no
  cli/rlang); console colour with `crayon`.
- Exported helpers that expose defaults are prefixed `ck_`
  (e.g. [`ck_flag_column_names()`](reference/ck_flag_column_names.md));
  internal helpers are `.dot_prefixed` and tagged `@keywords internal`
  or `@noRd`.
- Always call other packages with `pkg::fn()`; new dependencies get
  picked up by `attachment` in `dev/setup.R`.
- 4Mi specifics: question codes like `Q47`, “other” choice codes such as
  `197`/`297`, None = `996`. Don’t hard-code a new question set without
  a `ck_*()` default the user can override.

## Versioning and NEWS

- CalVer in DESCRIPTION: `YYYY.MM.patch` (e.g. `2026.08.0`).
- Every user-visible change gets a `NEWS.md` entry under
  `# cleaningkit (development version)`: a `##` heading per theme,
  bullets that lead with the **bolded function** and explain the
  behaviour and why, in plain prose. Mark bug fixes with “**Fixed:**”.

## Data

Survey data is personal data about people on the move. Never commit real
datasets, cleaning logs or exports; scratch outputs go in
`Claude outputs/` (git-ignored). Use the example scripts in
`inst/examples/` as the reference workflow.
