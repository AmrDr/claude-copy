#!/usr/bin/env bash
# uninstall.sh - remove Claude Copy from Linux
set -euo pipefail

CFG_DIR="$HOME/.config/claude-copy"
BIN_DIR="$HOME/.local/bin"

rm -f "$BIN_DIR/claude-copy"
rm -rf "$CFG_DIR"

echo "Claude Copy removed."
echo "Don't forget to remove the hotkey binding from your DE/WM."
