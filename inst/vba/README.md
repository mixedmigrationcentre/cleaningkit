# The cleaning log change-capture macro

These are the sources for the VBA project injected into macro-enabled cleaning
logs by `create_cleaning_log(macro = TRUE)`.

| File | Module | Notes |
|---|---|---|
| `Module1.bas` | standard module | Config/ledger helpers and shared state. Imports normally. |
| `ThisWorkbook.cls` | document module | Workbook event handlers. **Cannot be imported** — its code is inserted into the existing `ThisWorkbook` module. |

`inst/extdata/cleaningkit_vba.bin` is the compiled project built from these two
files. It is a build output that happens to be committed, because R cannot
produce it: `vbaProject.bin` is an OLE compound file holding MS-OVBA-compressed
source plus a p-code cache, and the libraries that try to synthesise one are
immature and do not document Excel compatibility. The `.bas` / `.cls` text here
is the artefact to review and diff; the `.bin` is what ships.

## Building the .bin

### Automatic (preferred)

On Windows with Excel:

```r
source("dev/build_vba_bin.R")
build_vba_bin()
```

This needs **Excel > File > Options > Trust Center > Trust Center Settings >
Macro Settings > "Trust access to the VBA project object model"** ticked. It is
off by default and is often locked down centrally — if you cannot enable it, use
the manual route below, which produces an identical file.

### Manual (about five minutes)

1. Open Excel and create a **new blank workbook with exactly one worksheet**
   (File > Options > General > "Include this many sheets" = 1). One sheet
   matters: the VBA project records a document module per worksheet, and a
   project that declares more sheet modules than the generated workbook has
   leaves orphaned modules behind. Excel adds modules for the log's other sheets
   by itself on open.
2. `Alt` + `F11` to open the VBA editor.
3. **File > Import File…** and choose `inst/vba/Module1.bas`.
4. In the Project Explorer double-click **ThisWorkbook**, then paste the entire
   contents of `inst/vba/ThisWorkbook.cls` into the code pane. (Do not import
   it — document modules cannot be imported.)
5. **Debug > Compile VBAProject**. It must compile with no errors.
6. Save as `inst/vba/cleaningkit_vba_authoring.xlsm`
   (`Excel Macro-Enabled Workbook`).
7. Copy that file to `cleaningkit_vba_authoring.zip`, open the zip, and copy
   `xl/vbaProject.bin` to `inst/extdata/cleaningkit_vba.bin`.

Keep the authoring workbook: it is where the macro is debugged next time.

## Smoke test before it reaches reviewers

The R side is covered by `tests/testthat/test-create_cleaning_log_macro.R`, but
no R test can tell you whether Excel is happy. Run this once per rebuild:

1. `create_cleaning_log(write_list, macro = TRUE, output_path = "smoke.xlsm")`
2. Open `smoke.xlsm` in Excel. It must open **without** any "we found a problem
   with some content" repair prompt.
3. Enable macros, go to the `dataset` sheet, change one value. A new row must
   appear at the bottom of the cleaning log with the right uuid, question, old
   and new value — and **no fill colour**.
4. Change the same cell again. A **second** row must appear, with `Issue`
   `manual_edit_002` and `Old value` equal to the previous edit.
5. Try to edit a cell in rows 1–2, or in the uuid column: it must be put back
   with a warning.
6. Save, close, reopen, edit the same cell a third time: `manual_edit_003`, with
   the ledger still chaining correctly across the session boundary.

## Macro security

Macros are blocked by default in files carrying the Mark of the Web, and the
current banner is a red "SECURITY RISK" bar with no "Enable content" button.
Whether reviewers can run these logs at all depends on how they receive them:

* Opened via "Open in Desktop App" from SharePoint, or reached through the
  OneDrive sync client — no Mark of the Web, macros run.
* Downloaded through a browser or received by email — blocked.

Test this with a real reviewer on a real file before rolling the feature out. If
it is blocked, the fixes are central: a Trusted Location, adding the
SharePoint/OneDrive domains to the Trusted Sites zone by policy, or signing the
VBA project with a code-signing certificate. Signing survives injection intact,
because `add_vba_project()` copies the `.bin` byte for byte.
