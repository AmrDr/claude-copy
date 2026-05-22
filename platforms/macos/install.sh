#!/usr/bin/env bash
# install.sh - Claude Copy installer for macOS
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CFG_DIR="$HOME/.config/claude-copy"
HS_DIR="$HOME/.hammerspoon"

echo "Claude Copy - macOS installer"
echo

# 1. Hammerspoon
if [ ! -d "/Applications/Hammerspoon.app" ]; then
    if command -v brew >/dev/null 2>&1; then
        echo "Installing Hammerspoon via Homebrew..."
        brew install --cask hammerspoon
    else
        echo "ERROR: Hammerspoon is required." >&2
        echo "       Install Homebrew (https://brew.sh) and re-run this script," >&2
        echo "       or install Hammerspoon manually from https://www.hammerspoon.org/" >&2
        exit 1
    fi
fi

# 2. Python 3
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required (install via 'brew install python' or python.org)." >&2
    exit 1
fi

# 3. Optional: pyperclip (we fall back to pbcopy otherwise)
if ! python3 -c 'import pyperclip' >/dev/null 2>&1; then
    pip3 install --user --quiet pyperclip 2>/dev/null \
        || echo "INFO: pyperclip not installed; falling back to pbcopy."
fi

# 4. Lay down files
mkdir -p "$CFG_DIR" "$HS_DIR"
cp -f "$ROOT/core/claude_copy.py" "$CFG_DIR/claude_copy.py"
cp -f "$HERE/claude-copy.lua"     "$HS_DIR/claude-copy.lua"
if [ ! -f "$CFG_DIR/config.ini" ]; then
    cp "$ROOT/config.example.ini" "$CFG_DIR/config.ini"
    echo "Config created: $CFG_DIR/config.ini"
fi

# 5. Hook into ~/.hammerspoon/init.lua
INIT="$HS_DIR/init.lua"
LINE='require("claude-copy")'
touch "$INIT"
if ! grep -Fq "$LINE" "$INIT"; then
    printf '\n-- Claude Copy\n%s\n' "$LINE" >> "$INIT"
    echo "Hooked into   : $INIT"
fi

# 6. Reload Hammerspoon
osascript -e 'tell application "Hammerspoon" to reload config' >/dev/null 2>&1 || true

COMBO="$(awk -F= '/^[[:space:]]*combo[[:space:]]*=/ {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit}' "$CFG_DIR/config.ini")"
[ -n "$COMBO" ] || COMBO="ctrl+alt+c"

echo
echo "Done."
echo "Hotkey        : $COMBO"
echo "Config        : $CFG_DIR/config.ini"
echo
echo "First run: open Hammerspoon and grant Accessibility permission when prompted."
echo "Change hotkey: edit config.ini, then click the Hammerspoon menu bar icon -> Reload Config."
