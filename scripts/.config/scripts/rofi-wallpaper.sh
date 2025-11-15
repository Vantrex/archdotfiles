#!/usr/bin/env bash
set -euo pipefail

# Base directory for wallpapers (can be overridden with first argument)
WALL_DIR="${1:-$HOME/work/walls}"

if ! command -v rofi >/dev/null 2>&1; then
  echo "rofi not found in PATH" >&2
  exit 1
fi

if ! command -v awww >/dev/null 2>&1; then
  echo "awww not found in PATH" >&2
  exit 1
fi

if [ ! -d "$WALL_DIR" ]; then
  echo "Wallpaper directory not found: $WALL_DIR" >&2
  exit 1
fi

# Build rofi input:
# Each line:  <relative-name>\0icon\x1fthumbnail://<absolute-path>\n
selection="$(
  find "$WALL_DIR" -type f \( \
      -iname '*.png'  -o \
      -iname '*.jpg'  -o \
      -iname '*.jpeg' -o \
      -iname '*.webp' -o \
      -iname '*.bmp' \
    \) -print0 \
  | while IFS= read -r -d '' file; do
      rel="${file#$WALL_DIR/}"
      printf '%s\0icon\x1fthumbnail://%s\n' "$rel" "$file"
    done \
  | sort \
  | rofi \
      -dmenu \
      -i \
      -matching fuzzy \
      -show-icons \
      -theme ~/.config/rofi/wallpaper_grid_dark.rasi \
      -p "Wallpaper" \
      2>/dev/null
)"

# User cancelled
if [ -z "${selection:-}" ]; then
  exit 0
fi

full_path="$WALL_DIR/$selection"

if [ ! -f "$full_path" ]; then
  echo "Selected file does not exist anymore: $full_path" >&2
  exit 1
fi

# Set wallpaper via aww
awww img "$full_path"

