#!/usr/bin/env bash
set -euo pipefail

WALLS_DIR="${WALLPAPER_DIR:-$HOME/work/walls}"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
unresolved=0

shopt -s nullglob
for image in "$WALLS_DIR"/ddg_* "$WALLS_DIR"/pinterest_*; do
  [[ -f "$image" ]] || continue
  name="$(basename "$image")"
  classify_out="$("$SCRIPT_DIR/classify_wallpaper.sh" "$image" "$WALLS_DIR" "" "$name" || true)"
  category="$(printf '%s' "$classify_out" | cut -d'|' -f1)"
  suggested="$(printf '%s' "$classify_out" | cut -s -d'|' -f2)"

  if [[ -z "$category" ]]; then
    printf 'NEED_CATEGORY|%s\n' "$name"
    unresolved=1
    continue
  fi

  mkdir -p "$WALLS_DIR/$category"

  ext="${name##*.}"
  if [[ -n "$suggested" && "$ext" != "$name" ]]; then
    dest_name="${suggested}.${ext}"
  else
    dest_name="$name"
  fi

  mv "$image" "$WALLS_DIR/$category/$dest_name"
  printf 'MOVED|%s → %s/%s\n' "$name" "$category" "$dest_name"
done

exit "$unresolved"
