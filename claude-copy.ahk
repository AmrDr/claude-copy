#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  Claude Copy  -  copy Claude Code's last answer
;  ------------------------------------------------------------
;  Hotkey:  Ctrl + Alt + C
;
;  Reads the title of the active terminal window and passes it to
;  copy-last-answer.ps1, which finds the matching Claude session
;  and copies its last answer to the clipboard.
;
;  Change the hotkey: edit the  ^!c::  line below.
;     ^ = Ctrl    ! = Alt    + = Shift    # = Windows key
;  Examples:  ^+y::  (Ctrl+Shift+Y)     #c::  (Win+C)
; ============================================================

scriptPath := A_ScriptDir . "\copy-last-answer.ps1"
statusFile := A_Temp . "\claude-copy-status.txt"
titleFile  := A_Temp . "\claude-copy-title.txt"

gLastTermTitle := ""   ; title of the most recently focused terminal

A_IconTip := "Claude Copy  -  Ctrl+Alt+C copies the active terminal's last answer"
TrayTip("Ctrl + Alt + C  copies Claude's last answer", "Claude Copy active", 1)

; Remember the active terminal window, so the hotkey still targets
; the right session even if you already switched to another app.
SetTimer(TrackTerminal, 300)

; ---- The hotkey ----
^!c:: CopyClaudeAnswer()

; Window classes / processes treated as terminals. Add yours if needed.
IsTerminalProc(proc) {
    static known := Map(
        "WindowsTerminal.exe", 1, "WindowsTerminalPreview.exe", 1,
        "OpenConsole.exe", 1, "conhost.exe", 1,
        "powershell.exe", 1, "pwsh.exe", 1, "cmd.exe", 1,
        "wezterm-gui.exe", 1, "alacritty.exe", 1, "Hyper.exe", 1,
        "mintty.exe", 1, "Tabby.exe", 1)
    return known.Has(proc)
}

TrackTerminal() {
    global gLastTermTitle
    try {
        if IsTerminalProc(WinGetProcessName("A")) {
            tt := WinGetTitle("A")
            if (tt != "")
                gLastTermTitle := tt
        }
    } catch {
        ; active window not queryable right now - ignore
    }
}

CopyClaudeAnswer() {
    global scriptPath, statusFile, titleFile, gLastTermTitle

    ; Title of the active (else the last active) terminal window.
    title := ""
    try {
        if IsTerminalProc(WinGetProcessName("A"))
            title := WinGetTitle("A")
    } catch {
    }
    if (title = "")
        title := gLastTermTitle

    ; Write the title to a file (UTF-8, no BOM).
    try {
        f := FileOpen(titleFile, "w", "UTF-8-RAW")
        if f {
            f.Write(title)
            f.Close()
        }
    } catch {
    }

    ; Remove the stale status file.
    try {
        if FileExist(statusFile)
            FileDelete(statusFile)
    } catch {
    }

    args := '-NoProfile -ExecutionPolicy Bypass -File "' . scriptPath . '" "' . statusFile . '" "' . titleFile . '"'

    ; Prefer pwsh (PowerShell 7), fall back to Windows PowerShell.
    launched := false
    for i, exe in ["pwsh.exe", "powershell.exe"] {
        try {
            RunWait(exe . " " . args, , "Hide")
            launched := true
            break
        } catch {
            continue
        }
    }
    if !launched {
        Toast("PowerShell not found")
        return
    }

    status := ""
    if FileExist(statusFile) {
        try {
            status := Trim(FileRead(statusFile, "UTF-8"), " `t`r`n")
        } catch {
            status := ""
        }
    }

    if (SubStr(status, 1, 3) = "OK ") {
        Toast("Copied: " . SubStr(status, 4))
    } else if (SubStr(status, 1, 4) = "ERR ") {
        Toast("Error: " . SubStr(status, 5))
    } else {
        Toast("Could not read the answer")
    }
}

; Short, self-dismissing tooltip near the mouse cursor.
Toast(text) {
    ToolTip(text)
    SetTimer(() => ToolTip(), -2500)
}
