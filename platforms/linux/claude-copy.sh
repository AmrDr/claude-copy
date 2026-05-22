#!/usr/bin/env bash
# claude-copy - get active window title, invoke claude_copy.py.
# Bind this to a hotkey in your desktop environment / window manager.
set -euo pipefail

CORE="${CLAUDE_COPY_CORE:-$HOME/.config/claude-copy/claude_copy.py}"

get_title() {
    # Hyprland
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
        hyprctl activewindow -j 2>/dev/null | \
            python3 -c "import sys,json
try: print(json.load(sys.stdin).get('title',''))
except: pass" 2>/dev/null
        return
    fi
    # Sway
    if [ -n "${SWAYSOCK:-}" ] && command -v swaymsg >/dev/null 2>&1; then
        swaymsg -t get_tree 2>/dev/null | \
            python3 -c "import sys,json
def walk(n):
    if n.get('focused'):
        print(n.get('name','')); return True
    for c in n.get('nodes',[]) + n.get('floating_nodes',[]):
        if walk(c): return True
    return False
try: walk(json.load(sys.stdin))
except: pass" 2>/dev/null
        return
    fi
    # X11
    if command -v xdotool >/dev/null 2>&1; then
        xdotool getactivewindow getwindowname 2>/dev/null || true
        return
    fi
    echo ""
}

TITLE="$(get_title || true)"
exec python3 "$CORE" --window-title "$TITLE" "$@"
