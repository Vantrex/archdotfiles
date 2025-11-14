#!/bin/bash
set -euo pipefail

# Directory containing your .tar.gz font files (default: current dir)
SRC_DIR="${1:-.}"

# Where user fonts are stored
FONT_DIR="${HOME}/.local/share/fonts"

# Temp directory for extraction
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$FONT_DIR"

# Allow patterns like *.tar.gz to expand to nothing without error
shopt -s nullglob

# Collect all archives
archives=("$SRC_DIR"/*.tar.gz "$SRC_DIR"/*.tgz)

if (( ${#archives[@]} == 0 )); then
  echo "No .tar.gz or .tgz font archives found in: $SRC_DIR" >&2
  exit 1
fi

for archive in "${archives[@]}"; do
  echo "Processing: $archive"

  # Name for subfolder (strip .tar.gz / .tgz)
  name="$(basename "$archive")"
  name="${name%.tar.gz}"
  name="${name%.tgz}"

  tmp_dir="$TMP_ROOT/$name"
  mkdir -p "$tmp_dir"

  # Extract archive
  tar -xvf "$archive" -C "$tmp_dir" >/dev/null

  # Destination folder for this font
  dest_dir="$FONT_DIR/$name"
  mkdir -p "$dest_dir"

  # Find font files
  mapfile -t font_files < <(find "$tmp_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \))

  if (( ${#font_files[@]} == 0 )); then
    echo "  -> No .ttf/.otf/.ttc files found, skipping."
    continue
  fi

  # Copy fonts
  for f in "${font_files[@]}"; do
    echo "  -> Installing $(basename "$f") to $dest_dir"
    cp -f "$f" "$dest_dir/"
  done
done

echo "Refreshing font cache..."
fc-cache -f "$FONT_DIR"

echo "Done. Fonts installed under: $FONT_DIR"
