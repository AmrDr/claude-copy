# Claude Copy

Copy [Claude Code](https://claude.com/claude-code)'s last answer to your clipboard with a global hotkey.

Running several Claude Code sessions side by side? Claude Copy copies from the
**window you're actually in** — not whichever session answered most recently.

Works on **Windows, macOS, and Linux**. Hotkey is configurable.

> **Status:** Windows is fully tested. macOS and Linux code is written but
> **not yet verified on real hardware** — please try it, open issues, send PRs.

## What gets copied

The whole last response turn — everything Claude wrote since your last prompt.
Three modes (set in `config.ini`):

| Mode | Contents |
|------|----------|
| `text` (default) | Claude's answer text only (including ` ``` ` blocks in the answer). |
| `text+code` | + commands Claude ran + files it wrote / edited. |
| `everything` | + the output of every tool call. |

Internal "thinking" blocks, the previous turn, and anything you do *after*
the answer are always excluded.

---

## Windows

**Requirements:** Windows 10/11, [AutoHotkey v2](https://www.autohotkey.com/),
[Claude Code](https://claude.com/claude-code), PowerShell.

```powershell
git clone https://github.com/AmrDr/claude-copy.git
cd claude-copy\platforms\windows
pwsh -ExecutionPolicy Bypass -File install.ps1
```

Then press **Ctrl + Alt + C** in a Claude Code terminal. Autostart at login
is set up. A small tooltip confirms each copy.

Options:

```powershell
pwsh -ExecutionPolicy Bypass -File install.ps1 -Hotkey "ctrl+shift+y" -Mode everything
pwsh -ExecutionPolicy Bypass -File install.ps1 -NoAutostart
```

Re-running with no flags preserves your edits to `config.ini`.

**Uninstall:** `pwsh -ExecutionPolicy Bypass -File uninstall.ps1`

## macOS *(written, not yet tested)*

**Requirements:** [Homebrew](https://brew.sh) (for installing Hammerspoon
automatically), [Hammerspoon](https://www.hammerspoon.org/), Python 3,
[Claude Code](https://claude.com/claude-code).

```bash
git clone https://github.com/AmrDr/claude-copy.git
cd claude-copy/platforms/macos
bash install.sh
```

You'll need to grant Hammerspoon **Accessibility** permission on first run
(System Settings → Privacy & Security → Accessibility).

Change the hotkey or mode by editing `~/.config/claude-copy/config.ini`, then
reload Hammerspoon (menu-bar icon → Reload Config).

**Uninstall:** `bash uninstall.sh`

## Linux *(written, not yet tested)*

**Requirements:** Python 3, a clipboard tool (`wl-clipboard`, `xclip`, or
`xsel`), optionally a window-title tool (`hyprctl`, `swaymsg`, or `xdotool`)
for session matching, [Claude Code](https://claude.com/claude-code).

```bash
git clone https://github.com/AmrDr/claude-copy.git
cd claude-copy/platforms/linux
bash install.sh
```

The installer drops the wrapper at `~/.local/bin/claude-copy` and a config at
`~/.config/claude-copy/config.ini`. **You bind the hotkey yourself** in your
desktop environment / window manager — the installer prints copy-paste-ready
instructions for GNOME, KDE, Hyprland, Sway, i3, and sxhkd.

**Uninstall:** `bash uninstall.sh` (then unbind in your DE/WM).

---

## How it works

Claude Code stores each session as a JSONL transcript under
`~/.claude/projects/`. It also writes `ai-title` entries — the same text it
shows as the terminal window title.

When you press the hotkey:

1. The platform adapter (AutoHotkey on Windows, Hammerspoon on macOS, a shell
   wrapper on Linux) reads the title of the active terminal window.
2. The extractor (`copy-last-answer.ps1` on Windows, `claude_copy.py`
   elsewhere) matches that title against every session's latest `ai-title`
   to find the right transcript.
3. It walks back from the end of that transcript, collects the last response
   turn, and puts it in the clipboard.

If no title match is found, it falls back to the most recently updated transcript.

## Configuration

Single shared `config.ini` (see [`config.example.ini`](config.example.ini)):

```ini
[hotkey]
combo = ctrl+alt+c          ; ctrl, alt, shift, super combos

[copy]
mode = text                  ; text | text+code | everything
max_tool_output_chars = 0    ; 0 = no limit
```

## Limitations

- Claude Copy relies on Claude Code's on-disk transcript format and its
  `ai-title` entries. These are **internal and undocumented** — a future
  Claude Code update could change them and break this tool.
- Sessions are distinguished by window title. Two sessions with identical
  titles: the most recently used wins.
- The terminal must show Claude Code's title (the default). A custom shell
  prompt that overwrites the window title makes Claude Copy fall back to the
  newest transcript.
- **Linux Wayland**: window-title detection only works on compositors that
  expose it (Hyprland via `hyprctl`, Sway via `swaymsg`). Other compositors
  fall back to "newest transcript".
- **macOS** requires Accessibility permission for Hammerspoon to read window
  titles and register global hotkeys.

## Repository layout

```
claude-copy/
├── config.example.ini      template for the user-facing config
├── core/
│   └── claude_copy.py      extractor used by macOS & Linux adapters
└── platforms/
    ├── windows/            AutoHotkey + PowerShell (self-contained)
    ├── macos/              Hammerspoon Lua + install scripts
    └── linux/              shell wrapper + install scripts
```

## License

[MIT](LICENSE)
