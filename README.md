# Claude Copy

Copy [Claude Code](https://claude.com/claude-code)'s last answer to your clipboard with a single hotkey: **Ctrl + Alt + C**.

Running several Claude Code sessions side by side? Claude Copy copies from the
**window you are actually in** — not whichever session answered most recently.

> Windows only. Built with PowerShell + AutoHotkey v2. No dependencies to compile.

## Why

When Claude Code gives you something useful, getting that text out of the
terminal means selecting it by hand — awkward across long, wrapped, multi-step
answers. Claude Copy makes it one keypress.

## What gets copied

Claude Copy reads the **whole last response turn** — everything Claude wrote
since your last prompt. Three modes:

| Mode | Contents |
|------|----------|
| `text` (default) | Claude's answer text only (including ` ``` ` code blocks that are part of the answer). |
| `text+code` | Answer text **+** commands Claude ran **+** files it wrote / edited. |
| `everything` | All of the above **+** the output of every tool call. |

Internal "thinking" blocks, the previous turn, and anything you do *after* the
answer are always excluded.

## Requirements

- Windows 10 / 11
- [AutoHotkey v2](https://www.autohotkey.com/) — v2, not v1
- [Claude Code](https://claude.com/claude-code)
- PowerShell (ships with Windows; PowerShell 7 also works)

## Install

```powershell
git clone https://github.com/AmrDr/claude-copy.git
cd claude-copy
pwsh -ExecutionPolicy Bypass -File install.ps1
```

Then press **Ctrl + Alt + C** in a Claude Code terminal. The hotkey also starts
automatically at login. A small tooltip confirms each copy, e.g.
`Copied: 842 chars - active window`.

Options:

```powershell
pwsh -ExecutionPolicy Bypass -File install.ps1 -Mode everything   # copy more
pwsh -ExecutionPolicy Bypass -File install.ps1 -NoAutostart       # no login start
```

## How it works

Claude Code stores each session as a JSONL transcript under
`%USERPROFILE%\.claude\projects\`. It also writes `ai-title` entries into the
transcript — the same text it shows as the terminal window title.

When you press the hotkey:

1. AutoHotkey reads the title of the active terminal window.
2. `copy-last-answer.ps1` matches that title against every session's latest
   `ai-title` to find the right transcript.
3. It extracts the last response turn from that transcript and copies it.

If no match is found, it falls back to the most recently updated transcript.

## Configuration

- **Copy mode** — re-run `install.ps1 -Mode ...`, or edit `$CopyMode` near the
  top of `copy-last-answer.ps1` in the install folder (`%LOCALAPPDATA%\ClaudeCopy`).
- **Output size** — `$MaxToolOutputChars` in the same file truncates long tool
  output in `everything` mode (0 = no limit).
- **Hotkey** — edit the `^!c::` line in `claude-copy.ahk`
  (`^`=Ctrl, `!`=Alt, `+`=Shift, `#`=Win), then re-run `install.ps1`.
- **Terminal detection** — if your terminal isn't recognised, add its process
  name to `IsTerminalProc()` in `claude-copy.ahk`.

## Uninstall

```powershell
pwsh -ExecutionPolicy Bypass -File uninstall.ps1
```

Stops the hotkey, removes the autostart entry, and deletes the install folder.

## Limitations

- **Windows only.**
- Claude Copy relies on Claude Code's on-disk transcript format and its
  `ai-title` entries. These are **internal and undocumented** — a future Claude
  Code update could change them and require an update here.
- Sessions are told apart by window title. If two sessions show the exact same
  title, the more recently used one wins.
- The terminal must show Claude Code's title (the default). A custom shell
  prompt that overwrites the window title breaks session matching; it then
  falls back to the newest transcript.

## License

[MIT](LICENSE)
