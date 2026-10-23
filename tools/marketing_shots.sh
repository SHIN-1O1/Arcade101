#!/usr/bin/env bash
# Renders Play Store screenshots into store/screenshots/ (1080x1920, 9:16 portrait phone).
# Needs: Godot 4.x on PATH (or GODOT=/path/to/godot) and xvfb. On Windows run it in WSL,
# or open the project and run tools/marketing_shots.gd with Godot's own window instead.
# The save file is redirected to a temp folder so your real progress is never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_DATA_HOME="$TMP/data"
"$GODOT" --headless --import >/dev/null 2>&1 || true
xvfb-run -a -s "-screen 0 1280x2000x24" "$GODOT" --rendering-driver opengl3 \
  --resolution 1080x1920 -s res://tools/marketing_shots.gd
