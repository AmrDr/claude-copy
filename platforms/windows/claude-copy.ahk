#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  Claude Copy  -  copy Claude Code's last answer
;  ------------------------------------------------------------
;  Hotkey is read from:
;    %LOCALAPPDATA%\ClaudeCopy\config.ini   ([hotkey] combo = ...)
;
;  Default: ctrl+alt+c. Edit the file and restart this script
;  (or re-run install.ps1) to change it.
; ============================================================

scriptPath := A_ScriptDir . "\copy-last-answer.ps1"
configFile := EnvGet("LOCALAPPDATA") . "\ClaudeCopy\config.ini"
statusFile := A_Temp . "\claude-copy-status.txt"
titleFile  := A_Temp . "\claude-copy-title.txt"

gLastTermTitle := ""    ; title of the most recently focused terminal

; ---- Read hotkey from config ----
hotkeyCombo := "ctrl+alt+c"
try {
    v := IniRead(configFile, "hotkey", "combo", "")
    if (v != "")
        hotkeyCombo := v
} catch {
}
ahkHotkey := ToAhkHotkey(hotkeyCombo)

A_IconTip := "Claude Copy  -  " . hotkeyCombo
TrayTip("Hotkey: " . hotkeyCombo, "Claude Copy active", 1)

; ---- Bind hotkey dynamically (with a clear error if it's invalid) ----
try {
    Hotkey(ahkHotkey, (*) => CopyClaudeAnswer())
} catch as e {
    MsgBox(
        "Claude Copy could not register hotkey '" . hotkeyCombo . "'"
        . " (AHK form: '" . ahkHotkey . "').`n`n"
        . "Error: " . e.Message . "`n`n"
        . "Edit " . configFile . " and reload this script.",
        "Claude Copy", "Iconx")
    ExitApp(1)
}

; Track the most recently focused terminal window.
SetTimer(TrackTerminal, 300)

; ---- Translate "ctrl+alt+c" -> AHK syntax "^!c" ----
ToAhkHotkey(s) {
    s := StrLower(s)
    mods := Map(
        "ctrl",    "^", "control", "^",
        "alt",     "!", "option",  "!",
        "shift",   "+",
        "win",     "#", "super",   "#", "cmd", "#", "command", "#", "meta", "#")
    out := ""
    base := ""
    for i, raw in StrSplit(s, "+") {
        k := Trim(raw, " `t")
        if mods.Has(k)
            out .= mods[k]
        else if (k != "")
            base := k
    }
    return out . base
}

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
    }
}

CopyClaudeAnswer() {
    global scriptPath, statusFile, titleFile, gLastTermTitle

    ; Active (or last active) terminal window title.
    title := ""
    try {
        if IsTerminalProc(WinGetProcessName("A"))
            title := WinGetTitle("A")
    } catch {
    }
    if (title = "")
        title := gLastTermTitle

    ; Hand the title to PowerShell via a temp file (UTF-8, no BOM).
    try {
        f := FileOpen(titleFile, "w", "UTF-8-RAW")
        if f {
            f.Write(title)
            f.Close()
        }
    } catch {
    }
    try {
        if FileExist(statusFile)
            FileDelete(statusFile)
    } catch {
    }

    args := '-NoProfile -ExecutionPolicy Bypass -File "' . scriptPath . '" "' . statusFile . '" "' . titleFile . '"'

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

Toast(text) {
    ToolTip(text)
    SetTimer(() => ToolTip(), -2500)
}
