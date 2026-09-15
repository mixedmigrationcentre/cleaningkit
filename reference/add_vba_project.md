# Turn a saved .xlsx into a macro-enabled .xlsm

Adds a pre-built VBA project to a workbook that openxlsx has already
written, by patching the OPC package directly.

## Usage

``` r
add_vba_project(xlsx_path, xlsm_path, vba_project = NULL, overwrite = TRUE)
```

## Arguments

- xlsx_path:

  Path to the `.xlsx` file to convert.

- xlsm_path:

  Path the macro-enabled workbook is written to.

- vba_project:

  Path to a `vbaProject.bin`. Defaults to the one shipped with the
  package.

- overwrite:

  Logical. Overwrite `xlsm_path` if it exists.

## Value

`xlsm_path`, invisibly.

## Details

openxlsx can carry a VBA project, but only half-way: `saveWorkbook()`
copies `wb$vbaProject` into the package, yet the content-type fix-up
happens only inside `loadWorkbook()`. Worse, `genBaseContent_Type()`
registers `<Default Extension="bin">` as *printer settings*, so a
`vbaProject.bin` added without an explicit override is mis-typed and
Excel offers to repair the file. openxlsx also drops per-sheet VBA code
names: its `sheetPr` field is only ever populated from `tabColour`, and
`loadWorkbook()` never reads `sheetPr` back from the source.

This function therefore does all five things the package needs:

1.  rewrites the `workbook.xml` content type to
    `application/vnd.ms-excel.sheet.macroEnabled.main+xml` and adds an
    explicit override for `/xl/vbaProject.bin`;

2.  adds the `vbaProject` relationship to `workbook.xml.rels`;

3.  sets `codeName="ThisWorkbook"` on `<workbookPr>`;

4.  sets `<sheetPr codeName="SheetN"/>` on every worksheet, in sheet
    order;

5.  drops the VBA project in and rezips.

Because all of the macro's code lives in `ThisWorkbook` and a standard
module, and sheets are addressed by display name, the code names only
have to be present and unique - they are not referenced by the macro
itself.

## Examples

``` r
if (FALSE) { # \dontrun{
add_vba_project("log.xlsx", "log.xlsm")
} # }
```
