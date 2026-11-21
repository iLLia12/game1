#!/bin/sh
# Raw animation export -> game-ready hero sheet. Options: see tools/normalize_sheet.gd
# Usage: tools/normalize.sh <input.png> <output.png> [options]
#   e.g. tools/normalize.sh art_raw/idle_with_gun.png assets/sprites/hero/states/idel/idel_with_gun.png
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." || exit 1
"$GODOT" --headless --path . -s tools/normalize_sheet.gd -- "$@" 2>&1 | grep -v -e '^Godot Engine' -e '^$' || true
"$GODOT" --headless --path . --import >/dev/null 2>&1
