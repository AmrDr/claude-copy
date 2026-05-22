#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
claude_copy.py - core of "Claude Copy".

Reads Claude Code's transcripts under ~/.claude/projects/, finds the session
matching the given window title via the transcript's ai-title entry, extracts
the last response turn, and copies it to the system clipboard.

Used by the macOS (Hammerspoon) and Linux (shell wrapper) adapters. The
Windows adapter uses copy-last-answer.ps1 instead.

Usage:
    python3 claude_copy.py [--window-title TITLE] [--mode MODE] [--max-output-chars N]

Exit code 0 on success, 1 on error.
Stdout: "OK <chars> chars - active window|newest transcript" or "ERR <msg>".
"""

from __future__ import annotations

import argparse
import configparser
import json
import os
import platform
import subprocess
import sys
from pathlib import Path
from shutil import which


# ---------------------------------------------------------------------------
# Config

VALID_MODES = ("text", "text+code", "everything")

DEFAULTS = {
    "mode": "text",
    "max_tool_output_chars": 0,
}


def load_config_defaults() -> dict:
    """Read mode + max_tool_output_chars from config.ini if present."""
    out = dict(DEFAULTS)

    candidates = [
        Path(__file__).parent / "config.ini",
        Path.home() / ".config" / "claude-copy" / "config.ini",
    ]
    localappdata = os.environ.get("LOCALAPPDATA")
    if localappdata:
        candidates.append(Path(localappdata) / "ClaudeCopy" / "config.ini")

    cfg = configparser.ConfigParser()
    for c in candidates:
        if c.is_file():
            try:
                cfg.read(c, encoding="utf-8")
                break
            except Exception:
                pass

    if cfg.has_section("copy"):
        m = cfg.get("copy", "mode", fallback="").strip().lower()
        if m in VALID_MODES:
            out["mode"] = m
        try:
            out["max_tool_output_chars"] = max(0, cfg.getint("copy", "max_tool_output_chars", fallback=0))
        except (ValueError, configparser.Error):
            pass
    return out


# ---------------------------------------------------------------------------
# Transcript discovery + ai-title

def find_transcripts() -> list[Path]:
    """Newest .jsonl per project folder under ~/.claude/projects/."""
    base = Path.home() / ".claude" / "projects"
    if not base.is_dir():
        return []
    found: list[Path] = []
    for folder in base.iterdir():
        if not folder.is_dir():
            continue
        jsonls = sorted(folder.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
        if jsonls:
            found.append(jsonls[0])
    return found


def get_ai_title(path: Path) -> str:
    """Latest aiTitle in the last ~800 lines of a transcript, or ''."""
    try:
        with path.open(encoding="utf-8", errors="ignore") as f:
            tail = f.readlines()[-800:]
    except OSError:
        return ""
    for line in reversed(tail):
        if '"type":"ai-title"' not in line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        title = obj.get("aiTitle")
        if title:
            return str(title)
    return ""


# ---------------------------------------------------------------------------
# Turn extraction

def is_real_prompt(obj: dict) -> bool:
    """True if this transcript entry is a real user prompt (= turn boundary)."""
    if obj.get("type") != "user":
        return False
    msg = obj.get("message") or {}
    if msg.get("role") != "user":
        return False
    if obj.get("isMeta") is True:
        return False
    c = msg.get("content")
    if isinstance(c, str):
        return bool(c.strip())
    if not c:
        return False
    has_text = False
    is_tool_result = False
    for b in c:
        if not isinstance(b, dict):
            continue
        t = b.get("type")
        if t == "tool_result":
            is_tool_result = True
        elif t == "text" and (b.get("text") or "").strip():
            has_text = True
    return has_text and not is_tool_result


def format_tool_use(b: dict) -> str:
    name = str(b.get("name", ""))
    inp = b.get("input") or {}
    if inp.get("command") is not None:
        return ">>> Command ({name}):\n{cmd}".format(name=name, cmd=inp["command"])
    if inp.get("content") is not None and inp.get("file_path") is not None:
        return ">>> Wrote file: {p}\n{c}".format(p=inp["file_path"], c=inp["content"])
    if inp.get("file_path") is not None and (
        inp.get("old_string") is not None or inp.get("new_string") is not None
    ):
        return (
            ">>> Edited file: {p}\n"
            "--- before ---\n{old}\n"
            "--- after ---\n{new}"
        ).format(p=inp["file_path"], old=inp.get("old_string", ""), new=inp.get("new_string", ""))
    try:
        j = json.dumps(inp, ensure_ascii=False, separators=(",", ":"))
    except (TypeError, ValueError):
        j = str(inp)
    return ">>> Tool ({name}): {j}".format(name=name, j=j)


def format_tool_result(b: dict, max_chars: int) -> str:
    c = b.get("content")
    if isinstance(c, str):
        txt = c
    elif isinstance(c, list):
        parts: list[str] = []
        for p in c:
            if isinstance(p, str):
                parts.append(p)
            elif isinstance(p, dict) and p.get("text") is not None:
                parts.append(str(p["text"]))
        txt = "\n".join(parts)
    else:
        txt = ""
    if max_chars and len(txt) > max_chars:
        txt = txt[:max_chars] + "\n... [truncated]"
    label = "<<< Output (error):" if b.get("is_error") else "<<< Output:"
    return label + "\n" + txt


def extract_last_answer(path: Path, mode: str, max_chars: int) -> str:
    include_tools = mode in ("text+code", "everything")
    include_output = mode == "everything"

    try:
        with path.open(encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except OSError:
        return ""

    parsed: list[dict | None] = [None] * len(lines)

    def get(i: int) -> dict | None:
        if parsed[i] is not None:
            return parsed[i]
        s = lines[i].strip()
        if not s:
            return None
        try:
            o = json.loads(s)
        except json.JSONDecodeError:
            return None
        parsed[i] = o
        return o

    # Phase A: last 'assistant' line.
    last_asst = -1
    for i in range(len(lines) - 1, -1, -1):
        o = get(i)
        if o is None:
            continue
        if o.get("type") == "assistant" and (o.get("message") or {}).get("role") == "assistant":
            last_asst = i
            break
    if last_asst < 0:
        return ""

    # Phase B: turn start = line after the most recent real user prompt.
    turn_start = 0
    for i in range(last_asst, -1, -1):
        o = get(i)
        if o is None:
            continue
        if is_real_prompt(o):
            turn_start = i + 1
            break

    # Phase C: forward through the turn, collect parts in order.
    parts: list[str] = []
    for i in range(turn_start, last_asst + 1):
        o = get(i)
        if o is None:
            continue
        t = o.get("type")
        msg = o.get("message") or {}
        if t == "assistant" and msg.get("role") == "assistant":
            c = msg.get("content")
            if isinstance(c, str):
                if c.strip():
                    parts.append(c)
            elif isinstance(c, list):
                for b in c:
                    if not isinstance(b, dict):
                        continue
                    bt = b.get("type")
                    if bt == "text":
                        txt = b.get("text") or ""
                        if txt.strip():
                            parts.append(str(txt))
                    elif bt == "tool_use" and include_tools:
                        parts.append(format_tool_use(b))
                    # 'thinking' blocks are always skipped
        elif include_output and t == "user" and msg.get("role") == "user":
            c = msg.get("content")
            if isinstance(c, list):
                for b in c:
                    if isinstance(b, dict) and b.get("type") == "tool_result":
                        parts.append(format_tool_result(b, max_chars))

    if not parts:
        return ""
    text = "\n\n".join(parts).strip()
    # Normalise line endings to the platform's convention.
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if platform.system() == "Windows":
        text = text.replace("\n", "\r\n")
    return text


# ---------------------------------------------------------------------------
# Clipboard

def copy_to_clipboard(text: str) -> None:
    """Set the system clipboard. pyperclip first, then OS-native tools."""
    try:
        import pyperclip  # type: ignore
        pyperclip.copy(text)
        return
    except Exception:
        pass

    import platform
    sysname = platform.system()
    if sysname == "Darwin":
        cmds = [["pbcopy"]]
    elif sysname == "Windows":
        cmds = [["clip"]]
    else:
        cmds = [
            ["wl-copy"],
            ["xclip", "-selection", "clipboard"],
            ["xsel", "--clipboard", "--input"],
        ]
    last_err = None
    for cmd in cmds:
        if not which(cmd[0]):
            continue
        try:
            p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
            p.communicate(input=text.encode("utf-8"))
            if p.returncode == 0:
                return
            last_err = "%s exited %d" % (cmd[0], p.returncode)
        except OSError as e:
            last_err = "%s: %s" % (cmd[0], e)
    raise RuntimeError(
        "No working clipboard tool found "
        "(install pyperclip, or one of: wl-clipboard, xclip, xsel). "
        "Last error: %s" % (last_err or "none")
    )


# ---------------------------------------------------------------------------
# Main

def main() -> int:
    defaults = load_config_defaults()

    p = argparse.ArgumentParser(
        description="Copy Claude Code's last answer to the clipboard."
    )
    p.add_argument("--window-title", default="",
                   help="Title of the active terminal window (used to pick the session).")
    p.add_argument("--mode", default=defaults["mode"], choices=list(VALID_MODES),
                   help="What to copy. Default from config.ini.")
    p.add_argument("--max-output-chars", type=int,
                   default=defaults["max_tool_output_chars"],
                   help="Truncate each tool output. 0 = no limit. Default from config.ini.")
    args = p.parse_args()

    transcripts = find_transcripts()
    if not transcripts:
        print("ERR No transcript found")
        return 1

    target: Path | None = None
    how = "newest transcript"
    win = (args.window_title or "").strip()
    if len(win) >= 3:
        win_cf = win.casefold()
        hits: list[tuple[int, float, Path]] = []
        for t in transcripts:
            ai = get_ai_title(t)
            if len(ai) >= 3 and ai.casefold() in win_cf:
                hits.append((len(ai), t.stat().st_mtime, t))
        if hits:
            hits.sort(key=lambda h: (h[0], h[1]), reverse=True)
            target = hits[0][2]
            how = "active window"

    if target is None:
        target = max(transcripts, key=lambda t: t.stat().st_mtime)

    answer = extract_last_answer(target, args.mode, args.max_output_chars)
    if not answer.strip():
        print("ERR No answer found in transcript")
        return 1

    try:
        copy_to_clipboard(answer)
    except Exception as e:
        print("ERR Clipboard: %s" % e)
        return 1

    print("OK %d chars - %s" % (len(answer), how))
    return 0


if __name__ == "__main__":
    sys.exit(main())
