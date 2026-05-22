#!/usr/bin/env bash
# install.sh - Claude Copy installer for Linux
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CFG_DIR="$HOME/.config/claude-copy"
BIN_DIR="$HOME/.local/bin"

echo "Claude Copy - Linux installer"
echo

# 1. Required: python3
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required." >&2
    exit 1
fi

# 2. Clipboard tool (one of)
have_clip=""
for c in wl-copy xclip xsel; do
    command -v "$c" >/dev/null 2>&1 && have_clip="$c" && break
done
if [ -z "$have_clip" ]; then
    echo "ERROR: no clipboard tool found. Install one of: wl-clipboard, xclip, xsel." >&2
    exit 1
fi
echo "Clipboard     : $have_clip"

# 3. Window-title tool (optional but recommended)
have_title=""
for c in hyprctl swaymsg xdotool; do
    command -v "$c" >/dev/null 2>&1 && have_title="$c" && break
done
if [ -z "$have_title" ]; then
    echo "Window title  : none (install hyprctl/swaymsg/xdotool for session matching)"
else
    echo "Window title  : $have_title"
fi

# 4. Optional: pyperclip
if ! python3 -c 'import pyperclip' >/dev/null 2>&1; then
    pip3 install --user --quiet pyperclip 2>/dev/null || true
fi

# 5. Lay down files
mkdir -p "$CFG_DIR" "$BIN_DIR"
cp -f "$ROOT/core/claude_copy.py" "$CFG_DIR/claude_copy.py"
cp -f "$HERE/claude-copy.sh"      "$BIN_DIR/claude-copy"
chmod +x "$BIN_DIR/claude-copy"
if [ ! -f "$CFG_DIR/config.ini" ]; then
    cp "$ROOT/config.example.ini" "$CFG_DIR/config.ini"
    echo "Config created: $CFG_DIR/config.ini"
fi

# 6. PATH hint
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "NOTE: $BIN_DIR is not on your PATH. Add it to ~/.bashrc / ~/.zshrc:"
       echo "      export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

COMBO="$(awk -F= '/^[[:space:]]*combo[[:space:]]*=/ {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit}' "$CFG_DIR/config.ini")"
[ -n "$COMBO" ] || COMBO="ctrl+alt+c"

cat <<EOF

Done. Now bind your hotkey to:
    $BIN_DIR/claude-copy

Configured combo (informational): $COMBO
Edit $CFG_DIR/config.ini and re-bind in your DE/WM to change it.

How to bind, by environment:

  GNOME    Settings -> Keyboard -> View and Customize Shortcuts ->
           Custom Shortcuts -> Add:
               Name:     Claude Copy
               Command:  $BIN_DIR/claude-copy
               Shortcut: $COMBO

  KDE      System Settings -> Shortcuts -> Custom Shortcuts ->
           Edit -> New -> Global Shortcut -> Command/URL:
               Trigger: $COMBO
               Action:  $BIN_DIR/claude-copy

  Hyprland  (~/.config/hypr/hyprland.conf):
               bind = CTRL ALT, C, exec, $BIN_DIR/claude-copy

  Sway / i3 (config):
               bindsym Ctrl+Alt+c exec $BIN_DIR/claude-copy

  sxhkd     (~/.config/sxhkd/sxhkdrc):
               ctrl + alt + c
                   $BIN_DIR/claude-copy

EOF
