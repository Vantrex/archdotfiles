#!/bin/bash
set -euo pipefail

WALLS_DIR="$HOME/work/walls"

mkdir -p "$HOME/work"

if [[ -d "$WALLS_DIR/.git" ]]; then
  echo "Wallpaper repository already exists at $WALLS_DIR; leaving it untouched."
  exit 0
fi

if [[ -e "$WALLS_DIR" ]]; then
  echo "Refusing to overwrite non-Git path: $WALLS_DIR" >&2
  exit 1
fi

git clone git@github.com:dharmx/walls.git "$WALLS_DIR"

