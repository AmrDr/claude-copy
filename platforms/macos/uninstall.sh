#!/usr/bin/env bash
# uninstall.sh - remove Claude Copy from macOS
set -euo pipefail

CFG_DIR="$HOME/.config/claude-copy"
HS_DIR="$HOME/.hammerspoon"

rm -f "$HS_DIR/claude-copy.lua"

if [ -f "$HS_DIR/init.lua" ]; then
    # remove our require line and the preceding "-- Claude Copy" marker
    sed -i.bak -e '/^require("claude-copy")$/d' -e '/^-- Claude Copy$/d' "$HS_DIR/init.lua"
    rm -f "$HS_DIR/init.lua.bak"
fi

rm -rf "$CFG_DIR"

osascript -e 'tell application "Hammerspoon" to reload config' >/dev/null 2>&1 || true
echo "Claude Copy removed."
