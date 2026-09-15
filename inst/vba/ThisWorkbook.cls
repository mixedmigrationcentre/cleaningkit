'======================================================================
' cleaningkit - cleaning log change capture (workbook events)
'
' NOTE ON IMPORTING
' -----------------
' ThisWorkbook is a *document* module: it cannot be imported as a new
' component. This file therefore carries no "Attribute VB_Name" header -
' its contents are inserted into the existing ThisWorkbook module with
' CodeModule.AddFromString. dev/build_vba_bin.R does that for you.
'
' WHAT IT DOES
' ------------
' Watches the `dataset` sheet of a cleaning log workbook. Every edit a
' reviewer makes there is appended as a new row at the bottom of the
' cleaning log sheet, so the reviewer never has to leave the workbook to
' record a change.
'
' Repeat edits: editing the same cell again appends ANOTHER row rather
' than overwriting the first, giving a full audit trail. Each row's
' "Old value" is the value immediately before that edit, so the rows
' chain raw -> A -> B, and the Issue column carries a per-cell sequence
' number (manual_edit_001, manual_edit_002, ...) which keeps
' uuid + question + issue unique through read_cleaning_log().
'
' Appended rows are written with formatting cleared, so none of the
' create_formated_wb() row colours carry down onto them.
'======================================================================

Option Explicit


Private Sub Workbook_Open()
    CkReset
End Sub


' Snapshot the selection before it is edited. This is how the first edit
' of a cell recovers its old value; later edits read the ledger instead.
Private Sub Workbook_SheetSelectionChange(ByVal Sh As Object, ByVal Target As Range)
    If gCkBusy Then Exit Sub
    If StrComp(Sh.Name, CkConfig("dataset_sheet"), vbTextCompare) <> 0 Then Exit Sub
    CkCacheSelection Sh, Target
End Sub


Private Sub Workbook_SheetChange(ByVal Sh As Object, ByVal Target As Range)
    Dim dsName As String, logName As String
    Dim firstDataRow As Long, headerRow As Long, labelRow As Long
    Dim ds As Worksheet, lg As Worksheet
    Dim scope As Range, c As Range
    Dim nCells As Long

    If gCkBusy Then Exit Sub

    dsName = CkConfig("dataset_sheet")
    If Len(dsName) = 0 Then Exit Sub
    If StrComp(Sh.Name, dsName, vbTextCompare) <> 0 Then Exit Sub

    logName = CkConfig("log_sheet")
    If Len(logName) = 0 Then Exit Sub

    Set ds = CkSheet(dsName)
    Set lg = CkSheet(logName)
    If ds Is Nothing Or lg Is Nothing Then Exit Sub

    headerRow = CkConfigLong("header_row", 1)
    labelRow = CkConfigLong("label_row", 2)
    firstDataRow = CkConfigLong("first_data_row", 3)

    ' Only cells inside the written block are of interest.
    On Error Resume Next
    Set scope = Application.Intersect(Target, ds.UsedRange)
    On Error GoTo 0
    If scope Is Nothing Then Exit Sub

    ' --- protect the header and label rows -------------------------------
    ' Editing them would break every question code in the log, so put them
    ' back from the selection snapshot rather than trying Application.Undo,
    ' which is unreliable inside a change event.
    If scope.Row < firstDataRow Then
        CkRestoreProtectedRows scope, headerRow, labelRow, firstDataRow
        Exit Sub
    End If

    If scope.Cells.CountLarge > CK_REFUSE_ABOVE Then
        MsgBox "This edit touches " & scope.Cells.CountLarge & " cells, which is more than " & _
               "cleaningkit will log in one go (" & CK_REFUSE_ABOVE & ")." & vbCrLf & vbCrLf & _
               "Nothing has been written to the cleaning log. Please undo (Ctrl+Z) and make the " & _
               "change in smaller blocks, or record it by hand.", vbExclamation, "cleaningkit"
        Exit Sub
    End If

    nCells = CLng(scope.Cells.CountLarge)
    If nCells > CK_CONFIRM_ABOVE Then
        If MsgBox("This edit touches " & nCells & " cells." & vbCrLf & vbCrLf & _
                  "Logging them all may take a moment. Continue?", _
                  vbQuestion + vbYesNo, "cleaningkit") = vbNo Then
            Exit Sub
        End If
    End If

    CkLogEdits ds, lg, scope, firstDataRow
End Sub


'----------------------------------------------------------------------
' Put the header / label rows back after an accidental edit.
'----------------------------------------------------------------------
Private Sub CkRestoreProtectedRows(ByVal scope As Range, ByVal headerRow As Long, _
                                   ByVal labelRow As Long, ByVal firstDataRow As Long)
    Dim c As Range, old As String, found As Boolean, restored As Long

    gCkBusy = True
    Application.EnableEvents = False
    On Error GoTo Cleanup

    For Each c In scope.Cells
        If c.Row < firstDataRow Then
            old = CkCachedValue(c.Worksheet.Name, c, found)
            If found Then
                c.Value = old
                restored = restored + 1
            End If
        End If
    Next c

Cleanup:
    Application.EnableEvents = True
    gCkBusy = False

    If restored > 0 Then
        MsgBox "Rows " & headerRow & " and " & labelRow & " hold the question names and labels " & _
               "that the cleaning log refers to, so they cannot be edited." & vbCrLf & vbCrLf & _
               restored & " cell(s) have been restored.", vbExclamation, "cleaningkit"
    Else
        MsgBox "Rows " & headerRow & " and " & labelRow & " hold the question names and labels " & _
               "that the cleaning log refers to, and must not be edited." & vbCrLf & vbCrLf & _
               "The previous values could not be restored automatically - please undo (Ctrl+Z).", _
               vbExclamation, "cleaningkit"
    End If
End Sub


'----------------------------------------------------------------------
' Append one cleaning log row per changed cell.
'----------------------------------------------------------------------
Private Sub CkLogEdits(ByVal ds As Worksheet, ByVal lg As Worksheet, _
                       ByVal scope As Range, ByVal firstDataRow As Long)

    Dim dsMap As Object, lgMap As Object
    Dim uuidCol As Long, dateCol As Long, enumCol As Long
    Dim nLogCols As Long, firstOut As Long, i As Long
    Dim rows() As Variant, nOut As Long
    Dim c As Range
    Dim uuid As String, question As String, questionText As String
    Dim oldVal As String, newVal As String, key As String
    Dim ledgerFound As Boolean, ledgerLast As String, ledgerCount As Long
    Dim originalVal As String, seq As Long, cachedVal As String, cacheFound As Boolean
    Dim prefix As String, issueText As String, actionText As String
    Dim noOldValue As Boolean, anyNoOldValue As Boolean, comment As String
    Dim prevScreen As Boolean, prevExtend As Boolean, prevCalc As Long
    Dim headerRow As Long, labelRow As Long
    Dim uuidEdited As Long, restoredUuid As Boolean

    headerRow = CkConfigLong("header_row", 1)
    labelRow = CkConfigLong("label_row", 2)
    prefix = CkConfigOr("issue_prefix", "manual_edit")

    Set dsMap = CkHeaderMap(ds, headerRow)
    Set lgMap = CkHeaderMap(lg, 1)

    uuidCol = CkCol(dsMap, CkConfigOr("uuid_column", "_uuid"))
    dateCol = CkCol(dsMap, CkConfigOr("date_column", "today"))
    enumCol = CkCol(dsMap, CkConfigOr("enumerator_column", "username"))

    If uuidCol = 0 Then
        MsgBox "cleaningkit could not find the column '" & CkConfigOr("uuid_column", "_uuid") & _
               "' on the " & ds.Name & " sheet, so this change was not logged.", _
               vbExclamation, "cleaningkit"
        Exit Sub
    End If

    nLogCols = lgMap.Count
    If nLogCols = 0 Then Exit Sub

    ReDim rows(1 To CLng(scope.Cells.CountLarge), 1 To nLogCols)
    nOut = 0

    gCkBusy = True
    prevScreen = Application.ScreenUpdating
    prevExtend = Application.ExtendList
    prevCalc = Application.Calculation
    Application.EnableEvents = False
    Application.ScreenUpdating = False
    Application.ExtendList = False                    ' stop Excel copying formats down
    Application.Calculation = xlCalculationManual
    On Error GoTo Cleanup

    For Each c In scope.Cells

        ' The uuid column is the link between the log and the raw data, so it
        ' is put back rather than logged.
        If c.Column = uuidCol And c.Row >= firstDataRow Then
            uuidEdited = uuidEdited + 1
            cachedVal = CkCachedValue(ds.Name, c, cacheFound)
            If cacheFound Then
                c.Value = cachedVal
                restoredUuid = True
            End If
        ElseIf c.Row >= firstDataRow Then

            question = Trim$(CStr(ds.Cells(headerRow, c.Column).Value))
            uuid = CkText(ds.Cells(c.Row, uuidCol))
            newVal = CkText(c)

            If Len(question) > 0 And Len(uuid) > 0 Then
                key = CkLedgerKey(uuid, question)
                CkLedgerGet key, ledgerFound, ledgerLast, ledgerCount

                noOldValue = False
                If ledgerFound Then
                    ' Chain from the previous edit of this same cell.
                    oldVal = ledgerLast
                    originalVal = vbNullString
                Else
                    ' First edit of this cell: recover the raw value from the
                    ' pre-edit snapshot of the selection.
                    cachedVal = CkCachedValue(ds.Name, c, cacheFound)
                    If cacheFound Then
                        oldVal = cachedVal
                    Else
                        oldVal = vbNullString
                        noOldValue = True
                        anyNoOldValue = True
                    End If
                    originalVal = oldVal
                End If

                If StrComp(oldVal, newVal, vbBinaryCompare) <> 0 Or noOldValue Then

                    seq = CkLedgerPut(key, originalVal, newVal)
                    issueText = prefix & "_" & Format$(seq, "000")
                    actionText = CkAction(oldVal, newVal)

                    questionText = vbNullString
                    If labelRow > 0 Then questionText = CkText(ds.Cells(labelRow, c.Column))

                    comment = vbNullString
                    If seq > 1 Then
                        comment = "Edit " & seq & " of this cell (previous value: " & oldVal & ")"
                    End If
                    If noOldValue Then
                        comment = Trim$(comment & " Old value could not be captured automatically.")
                    End If

                    nOut = nOut + 1
                    CkSetCell rows, nOut, lgMap, "Survey UUID", uuid
                    If dateCol > 0 Then CkSetCell rows, nOut, lgMap, "Date", CkText(ds.Cells(c.Row, dateCol))
                    If enumCol > 0 Then CkSetCell rows, nOut, lgMap, "Enumerator", CkText(ds.Cells(c.Row, enumCol))
                    CkSetCell rows, nOut, lgMap, "Question number", question
                    CkSetCell rows, nOut, lgMap, "Question text", questionText
                    CkSetCell rows, nOut, lgMap, "Issue", issueText
                    CkSetCell rows, nOut, lgMap, "Old value", oldVal
                    CkSetCell rows, nOut, lgMap, "Action taken", actionText
                    CkSetCell rows, nOut, lgMap, "New value", newVal
                    CkSetCell rows, nOut, lgMap, "Identified by", Application.UserName
                    CkSetCell rows, nOut, lgMap, "Comments", comment
                    CkSetCell rows, nOut, lgMap, "check_binding", prefix & " ~/~ " & uuid
                End If
            End If
        End If
    Next c

    If nOut > 0 Then
        firstOut = lg.Cells(lg.Rows.Count, 1).End(xlUp).Row + 1
        If firstOut < 2 Then firstOut = 2

        With lg.Range(lg.Cells(firstOut, 1), lg.Cells(firstOut + nOut - 1, nLogCols))
            ' Clear first: anything Excel may have extended downward goes now.
            .ClearFormats
            .Value = CkTrimRows(rows, nOut, nLogCols)
            .Interior.Pattern = xlNone
            .Font.Name = CkConfigOr("body_font", "Arial Narrow")
            .Font.Size = CkConfigLong("body_font_size", 11)
            .HorizontalAlignment = xlLeft
            .VerticalAlignment = xlCenter
        End With

        CkApplyActionValidation lg, lgMap, firstOut, nOut
    End If

Cleanup:
    Application.Calculation = prevCalc
    Application.ExtendList = prevExtend
    Application.ScreenUpdating = prevScreen
    Application.EnableEvents = True
    gCkBusy = False

    If Err.Number <> 0 Then
        MsgBox "cleaningkit could not finish logging this change." & vbCrLf & vbCrLf & _
               "Error " & Err.Number & ": " & Err.Description & vbCrLf & vbCrLf & _
               "Please record it in the cleaning log by hand.", vbExclamation, "cleaningkit"
        Err.Clear
        Exit Sub
    End If

    If uuidEdited > 0 Then
        If restoredUuid Then
            MsgBox "The " & CkConfigOr("uuid_column", "_uuid") & " column links the cleaning log to " & _
                   "the raw data and cannot be edited." & vbCrLf & vbCrLf & _
                   uuidEdited & " cell(s) have been restored.", vbExclamation, "cleaningkit"
        Else
            MsgBox "The " & CkConfigOr("uuid_column", "_uuid") & " column links the cleaning log to " & _
                   "the raw data and must not be edited." & vbCrLf & vbCrLf & _
                   "The previous value could not be restored automatically - please undo (Ctrl+Z).", _
                   vbExclamation, "cleaningkit"
        End If
    End If

    If anyNoOldValue Then CkWarnNoOldValueOnce
End Sub


' Write one field of the pending row, by log header name.
Private Sub CkSetCell(ByRef rows() As Variant, ByVal rowIx As Long, _
                      ByVal lgMap As Object, ByVal headerName As String, _
                      ByVal value As Variant)
    Dim col As Long
    col = CkCol(lgMap, headerName)
    If col > 0 Then rows(rowIx, col) = value
End Sub


' Cut the pre-allocated buffer down to the rows actually used.
Private Function CkTrimRows(ByRef rows() As Variant, ByVal nOut As Long, _
                            ByVal nCols As Long) As Variant
    Dim out() As Variant, i As Long, j As Long
    ReDim out(1 To nOut, 1 To nCols)
    For i = 1 To nOut
        For j = 1 To nCols
            out(i, j) = rows(i, j)
        Next j
    Next i
    CkTrimRows = out
End Function


' Give the appended rows the same Action taken drop-down as the rest of the
' log. The list is taken from config, so it never depends on the hidden
' validation_rules sheet still being present.
Private Sub CkApplyActionValidation(ByVal lg As Worksheet, ByVal lgMap As Object, _
                                    ByVal firstOut As Long, ByVal nOut As Long)
    Dim actionCol As Long, codes As String
    actionCol = CkCol(lgMap, "Action taken")
    If actionCol = 0 Then Exit Sub

    codes = CkConfig("action_codes")
    If Len(codes) = 0 Then Exit Sub

    On Error Resume Next
    With lg.Range(lg.Cells(firstOut, actionCol), lg.Cells(firstOut + nOut - 1, actionCol)).Validation
        .Delete
        .Add Type:=xlValidateList, AlertStyle:=xlValidAlertStop, _
             Operator:=xlBetween, Formula1:=codes
        .IgnoreBlank = True
        .InCellDropdown = True
    End With
    On Error GoTo 0
End Sub
