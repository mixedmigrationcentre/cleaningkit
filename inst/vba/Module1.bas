Attribute VB_Name = "Module1"
Option Explicit

'======================================================================
' cleaningkit - cleaning log change capture (helpers and state)
'
' Companion to ThisWorkbook.cls. Together they let a reviewer edit the
' `dataset` sheet of a cleaning log workbook produced by
' cleaningkit::create_cleaning_log_vba() and have every edit
' appended automatically to the bottom of the cleaning log sheet.
'
' Design notes
' ------------
' * Nothing is hard-coded. Sheet names, key columns and action codes are
'   read from the very-hidden `_ck_config` sheet written by R, so one
'   compiled vbaProject.bin serves every log the package generates.
' * `_ck_ledger` (very hidden) remembers, per uuid + question, the
'   original raw value, the most recent value and how many times the
'   cell has been edited. It survives save/reopen, which is what makes
'   the chained "Old value" correct across sessions.
' * Every edit appends a NEW row. The Nth edit of a cell is written with
'   Issue = "<prefix>_00N", so that uuid + question + issue stays unique
'   and read_cleaning_log() keeps all of them rather than collapsing
'   them to the first.
' * Late binding (CreateObject) is used throughout so the VBA project
'   carries no external references.
'======================================================================

Public Const CK_CONFIG_SHEET As String = "_ck_config"
Public Const CK_LEDGER_SHEET As String = "_ck_ledger"

' Soft ceiling on a single edit (paste / fill). Above this the user is asked
' to confirm, because logging is O(cells) and a stray paste can be huge.
Public Const CK_CONFIRM_ABOVE As Long = 500

' Hard ceiling. A single edit above this is refused outright rather than
' attempting to allocate a buffer for it.
Public Const CK_REFUSE_ABOVE As Long = 50000

' Re-entrancy guard. Also settable from the Immediate window to silence the
' handler temporarily: gCkBusy = True
Public gCkBusy As Boolean

' Pre-edit snapshot of the current selection, used to recover the old value
' of a cell that has not been edited before.
Public gCkCacheAddr As String
Public gCkCacheSheet As String
Public gCkCacheVals As Variant

Private mConfig As Object      ' key -> value, from _ck_config
Private mLedgerIdx As Object   ' "uuid|question" -> ledger row number
Private mWarnedNoOld As Boolean


'----------------------------------------------------------------------
' Configuration
'----------------------------------------------------------------------

' Read a single value from the _ck_config sheet. Returns vbNullString when
' the key is absent, so callers can supply their own default.
Public Function CkConfig(ByVal keyName As String) As String
    Dim ws As Worksheet, lastRow As Long, i As Long

    If mConfig Is Nothing Then
        Set mConfig = CreateObject("Scripting.Dictionary")
        mConfig.CompareMode = 1                       ' vbTextCompare
        Set ws = CkSheet(CK_CONFIG_SHEET)
        If Not ws Is Nothing Then
            lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
            For i = 1 To lastRow
                If Len(Trim$(CStr(ws.Cells(i, 1).Value))) > 0 Then
                    mConfig(Trim$(CStr(ws.Cells(i, 1).Value))) = _
                        CStr(ws.Cells(i, 2).Value)
                End If
            Next i
        End If
    End If

    If mConfig.Exists(keyName) Then
        CkConfig = mConfig(keyName)
    Else
        CkConfig = vbNullString
    End If
End Function

Public Function CkConfigOr(ByVal keyName As String, ByVal fallback As String) As String
    Dim v As String
    v = CkConfig(keyName)
    If Len(v) = 0 Then v = fallback
    CkConfigOr = v
End Function

Public Function CkConfigLong(ByVal keyName As String, ByVal fallback As Long) As Long
    Dim v As String
    v = CkConfig(keyName)
    If Len(v) = 0 Then
        CkConfigLong = fallback
    ElseIf IsNumeric(v) Then
        CkConfigLong = CLng(v)
    Else
        CkConfigLong = fallback
    End If
End Function

' Drop cached config / ledger index. Called from Workbook_Open.
Public Sub CkReset()
    Set mConfig = Nothing
    Set mLedgerIdx = Nothing
    mWarnedNoOld = False
    gCkBusy = False
    gCkCacheAddr = vbNullString
    gCkCacheSheet = vbNullString
    gCkCacheVals = Empty
End Sub


'----------------------------------------------------------------------
' Sheet helpers
'----------------------------------------------------------------------

' Worksheet by name, or Nothing. Never raises.
Public Function CkSheet(ByVal sheetName As String) As Worksheet
    Dim ws As Worksheet
    If Len(sheetName) = 0 Then Exit Function
    For Each ws In ThisWorkbook.Worksheets
        If StrComp(ws.Name, sheetName, vbTextCompare) = 0 Then
            Set CkSheet = ws
            Exit Function
        End If
    Next ws
End Function

' Map header text -> column number for one header row of a sheet.
Public Function CkHeaderMap(ByVal ws As Worksheet, ByVal headerRow As Long) As Object
    Dim d As Object, lastCol As Long, c As Long, nm As String
    Set d = CreateObject("Scripting.Dictionary")
    d.CompareMode = 1                                 ' vbTextCompare
    lastCol = ws.Cells(headerRow, ws.Columns.Count).End(xlToLeft).Column
    For c = 1 To lastCol
        nm = Trim$(CStr(ws.Cells(headerRow, c).Value))
        If Len(nm) > 0 Then
            If Not d.Exists(nm) Then d(nm) = c
        End If
    Next c
    Set CkHeaderMap = d
End Function

' Column number for a header name, or 0.
Public Function CkCol(ByVal map As Object, ByVal headerName As String) As Long
    If map Is Nothing Then Exit Function
    If map.Exists(headerName) Then CkCol = map(headerName)
End Function


'----------------------------------------------------------------------
' Ledger
'----------------------------------------------------------------------

' The very-hidden ledger sheet, created on first use.
'   A key ("uuid|question")   B original value
'   C last value              D edit count
Public Function CkLedger() As Worksheet
    Dim ws As Worksheet
    Set ws = CkSheet(CK_LEDGER_SHEET)
    If ws Is Nothing Then
        Set ws = ThisWorkbook.Worksheets.Add( _
            After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        ws.Name = CK_LEDGER_SHEET
        ws.Range("A1").Value = "key"
        ws.Range("B1").Value = "original_value"
        ws.Range("C1").Value = "last_value"
        ws.Range("D1").Value = "edit_count"
        ws.Visible = xlSheetVeryHidden
    End If
    Set CkLedger = ws
End Function

Private Sub CkBuildLedgerIndex()
    Dim ws As Worksheet, lastRow As Long, i As Long, k As String
    Set mLedgerIdx = CreateObject("Scripting.Dictionary")
    mLedgerIdx.CompareMode = 0                        ' vbBinaryCompare - keys are exact
    Set ws = CkLedger()
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
    For i = 2 To lastRow
        k = CStr(ws.Cells(i, 1).Value)
        If Len(k) > 0 Then mLedgerIdx(k) = i
    Next i
End Sub

Public Function CkLedgerKey(ByVal uuid As String, ByVal question As String) As String
    CkLedgerKey = uuid & "|" & question
End Function

' Look up a cell's ledger entry.
'   found        - whether the cell has been edited before
'   lastValue    - the value as of the previous edit (the new row's "Old value")
'   editCount    - how many times it has been edited so far
Public Sub CkLedgerGet(ByVal ledgerKey As String, ByRef found As Boolean, _
                       ByRef lastValue As String, ByRef editCount As Long)
    Dim ws As Worksheet, r As Long
    found = False: lastValue = vbNullString: editCount = 0
    If mLedgerIdx Is Nothing Then CkBuildLedgerIndex
    If Not mLedgerIdx.Exists(ledgerKey) Then Exit Sub
    Set ws = CkLedger()
    r = mLedgerIdx(ledgerKey)
    found = True
    lastValue = CStr(ws.Cells(r, 3).Value)
    editCount = CLng(Val(ws.Cells(r, 4).Value))
End Sub

' Record an edit. Returns the new edit count (1 for a cell's first edit).
Public Function CkLedgerPut(ByVal ledgerKey As String, ByVal originalValue As String, _
                            ByVal newValue As String) As Long
    Dim ws As Worksheet, r As Long, n As Long
    If mLedgerIdx Is Nothing Then CkBuildLedgerIndex
    Set ws = CkLedger()

    If mLedgerIdx.Exists(ledgerKey) Then
        r = mLedgerIdx(ledgerKey)
        n = CLng(Val(ws.Cells(r, 4).Value)) + 1
    Else
        r = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1
        If r < 2 Then r = 2
        n = 1
        ws.Cells(r, 1).Value = ledgerKey
        ws.Cells(r, 2).Value = originalValue
        mLedgerIdx(ledgerKey) = r
    End If

    ws.Cells(r, 3).Value = newValue
    ws.Cells(r, 4).Value = n
    CkLedgerPut = n
End Function


'----------------------------------------------------------------------
' Value helpers
'----------------------------------------------------------------------

' Cell value as the plain text the cleaning log should carry. Dates are
' reduced to YYYY-MM-DD so they match what create_cleaning_log() writes.
Public Function CkText(ByVal c As Range) As String
    Dim v As Variant
    v = c.Value
    If IsError(v) Then
        CkText = CStr(c.Text)
    ElseIf IsEmpty(v) Then
        CkText = vbNullString
    ElseIf IsDate(v) Then
        CkText = Format$(v, "yyyy-mm-dd")
    Else
        CkText = CStr(v)
    End If
End Function

Public Function CkVarText(ByVal v As Variant) As String
    If IsError(v) Then
        CkVarText = vbNullString
    ElseIf IsEmpty(v) Then
        CkVarText = vbNullString
    ElseIf IsNull(v) Then
        CkVarText = vbNullString
    ElseIf IsDate(v) Then
        CkVarText = Format$(v, "yyyy-mm-dd")
    Else
        CkVarText = CStr(v)
    End If
End Function

' Map an old/new pair onto the package's action codes.
Public Function CkAction(ByVal oldValue As String, ByVal newValue As String) As String
    If Len(oldValue) = 0 And Len(newValue) > 0 Then
        CkAction = CkConfigOr("action_addition", "addition")
    ElseIf Len(oldValue) > 0 And Len(newValue) = 0 Then
        CkAction = CkConfigOr("action_delete", "delete_data_point")
    Else
        CkAction = CkConfigOr("action_recoded", "recoded")
    End If
End Function


'----------------------------------------------------------------------
' Selection cache
'----------------------------------------------------------------------

' Snapshot the values of the selected range before it is edited. Only the
' dataset sheet is cached, and only up to a sane number of cells.
Public Sub CkCacheSelection(ByVal sh As Object, ByVal target As Range)
    Dim one(1 To 1, 1 To 1) As Variant

    On Error Resume Next
    gCkCacheSheet = sh.Name
    gCkCacheAddr = target.Address
    gCkCacheVals = Empty

    ' Multi-area selections (Ctrl+click) are not cached: the offset maths
    ' below only holds for a single rectangular block.
    If target.Areas.Count > 1 Then Exit Sub
    If target.Cells.CountLarge > 65536 Then Exit Sub

    If target.Cells.CountLarge = 1 Then
        one(1, 1) = target.Value
        gCkCacheVals = one
    Else
        gCkCacheVals = target.Value
    End If
    On Error GoTo 0
End Sub

' The pre-edit value of one cell, if it is inside the cached block.
Public Function CkCachedValue(ByVal sheetName As String, ByVal c As Range, _
                              ByRef found As Boolean) As String
    Dim base As Range, rOff As Long, cOff As Long
    found = False
    CkCachedValue = vbNullString
    If IsEmpty(gCkCacheVals) Then Exit Function
    If StrComp(sheetName, gCkCacheSheet, vbTextCompare) <> 0 Then Exit Function

    On Error GoTo Fail
    Set base = c.Worksheet.Range(gCkCacheAddr)
    If Intersect(base, c) Is Nothing Then Exit Function
    rOff = c.Row - base.Cells(1, 1).Row + 1
    cOff = c.Column - base.Cells(1, 1).Column + 1
    If rOff < LBound(gCkCacheVals, 1) Or rOff > UBound(gCkCacheVals, 1) Then Exit Function
    If cOff < LBound(gCkCacheVals, 2) Or cOff > UBound(gCkCacheVals, 2) Then Exit Function
    CkCachedValue = CkVarText(gCkCacheVals(rOff, cOff))
    found = True
    Exit Function
Fail:
End Function

Public Sub CkWarnNoOldValueOnce()
    If mWarnedNoOld Then Exit Sub
    mWarnedNoOld = True
    MsgBox "cleaningkit could not read the previous value of at least one edited cell." & vbCrLf & vbCrLf & _
           "This happens with Find & Replace All, or when a cell is changed without being selected first. " & _
           "The change has still been logged, but its 'Old value' is blank and the Comments column says so." & vbCrLf & vbCrLf & _
           "Please fill the Old value in by hand, or undo and redo the edit normally.", _
           vbExclamation, "cleaningkit"
End Sub
