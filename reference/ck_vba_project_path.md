# Path to the compiled VBA project

Locates `cleaningkit_vba.bin`, the compiled VBA project injected into
macro-enabled cleaning logs. Returns `""` when it cannot be found.

## Usage

``` r
ck_vba_project_path()
```

## Value

A file path, or `""` if the VBA project cannot be found.

## Details

The search order is:

1.  `getOption("cleaningkit.vba_project")`;

2.  the `CLEANINGKIT_VBA_PROJECT` environment variable;

3.  `inst/extdata` of the installed package;

4.  `inst/extdata/`, `resources/`, `functions/`, `dev/` and the working
    directory itself.

Steps 1 and 4 exist because these functions are often sourced straight
into an analysis project rather than used from the installed package. In
that situation
[`system.file()`](https://rdrr.io/r/base/system.file.html) returns
`""` - and it also returns `""` when the package *is* installed but was
installed before the binary was built, which is easy to miss. Dropping
the `.bin` into the project (`resources/` is a natural home) or setting
the option in a setup script both work:


    options(cleaningkit.vba_project = "C:/path/to/cleaningkit_vba.bin")

## Examples

``` r
if (FALSE) { # \dontrun{
ck_vba_project_path()
} # }
```
