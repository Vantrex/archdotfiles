#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:?action required}"
NAME="${2:?search thumbnail name required}"
CATEGORY="${3:-}"
SEARCH_QUERY="${4:-}"
PRESET_NAME="${5:-}"
SEARCH_SOURCE="${6:-}"
CACHE_DIR="$HOME/.cache/wallpaper_picker"
SEARCH_MAP="$CACHE_DIR/search_map.txt"
FULL_DIR="$CACHE_DIR/online_full"
DIMENSIONS_FILE="$CACHE_DIR/online_dimensions.txt"
STATUS_FILE="$CACHE_DIR/download_status.txt"
WALLS_DIR="${WALLPAPER_DIR:-$HOME/work/walls}"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

case "$NAME" in
  */*|''|.*) echo "Invalid wallpaper name" >&2; exit 1 ;;
esac

mkdir -p "$FULL_DIR"

set_status() {
  printf '%s\n' "$1" > "$STATUS_FILE"
}

URL="$(awk -F'|' -v name="$NAME" '$1 == name { print $2; exit }' "$SEARCH_MAP")"
[[ -n "$URL" ]] || { echo "Search URL not found for $NAME" >&2; exit 1; }

# Determine actual full-file path — video URLs use the video extension, not the thumb extension.
URL_EXT="${URL##*.}"
URL_EXT="${URL_EXT%%\?*}"
URL_EXT="$(echo "$URL_EXT" | tr '[:upper:]' '[:lower:]')"
if [[ "$URL_EXT" =~ ^(mp4|webm|mkv|mov)$ ]]; then
  IS_VIDEO=1
  FULL_FILE="$FULL_DIR/${NAME%.*}.${URL_EXT}"
else
  IS_VIDEO=0
  FULL_FILE="$FULL_DIR/$NAME"
fi

record_dimensions() {
  [[ "$IS_VIDEO" -eq 1 ]] && return 0  # skip dimension recording for video
  local dimensions tmp
  dimensions="$(magick identify -format '%wx%h' "$FULL_FILE[0]" 2>/dev/null || true)"
  [[ -n "$dimensions" ]] || return 0
  tmp="$DIMENSIONS_FILE.tmp"
  { grep -Fv "$NAME|" "$DIMENSIONS_FILE" 2>/dev/null || true; printf '%s|%s\n' "$NAME" "$dimensions"; } > "$tmp"
  mv "$tmp" "$DIMENSIONS_FILE"
}

fetch_full() {
  local tmp mime
  if [[ -s "$FULL_FILE" ]]; then
    set_status "Using cached wallpaper..."
    record_dimensions
    return 0
  fi

  tmp="$FULL_FILE.tmp"
  if [[ "$IS_VIDEO" -eq 1 ]]; then
    set_status "Fetching video wallpaper..."
    curl -fsSL --max-time 300 -A 'Mozilla/5.0' "$URL" -o "$tmp"
    mime="$(file -b --mime-type "$tmp")"
    [[ "$mime" == video/* || "$mime" == application/octet-stream ]] || { rm -f "$tmp"; echo "Downloaded file is not a video ($mime)" >&2; exit 1; }
    mv "$tmp" "$FULL_FILE"
  else
    set_status "Fetching full-resolution image..."
    curl -fsSL --max-time 90 -A 'Mozilla/5.0' "$URL" -o "$tmp"
    mime="$(file -b --mime-type "$tmp")"
    [[ "$mime" == image/* ]] || { rm -f "$tmp"; echo "Downloaded file is not an image" >&2; exit 1; }
    if [[ "$mime" == "image/webp" && "$NAME" != *.webp ]]; then
      set_status "Converting image..."
      magick "$tmp" "$FULL_FILE"
      rm -f "$tmp"
    else
      mv "$tmp" "$FULL_FILE"
    fi
    record_dimensions
  fi
}

validate_category() {
  [[ -n "$CATEGORY" && "$CATEGORY" != .* && "$CATEGORY" != */* ]]
}

fetch_full

case "$ACTION" in
  fetch)
    printf '%s\n' "$FULL_FILE"
    ;;
  save)
    if [[ -z "$CATEGORY" ]]; then
      set_status "Preparing classifier..."
      # For video files extract a still frame so the vision model gets an image.
      CLASSIFY_FILE="$FULL_FILE"
      CLASSIFY_TMP=""
      if [[ "$IS_VIDEO" -eq 1 ]]; then
        CLASSIFY_TMP="$(mktemp --suffix=.jpg)"
        if ffmpeg -y -i "$FULL_FILE" -vframes 1 -q:v 2 "$CLASSIFY_TMP" 2>/dev/null && [[ -s "$CLASSIFY_TMP" ]]; then
          CLASSIFY_FILE="$CLASSIFY_TMP"
        else
          rm -f "$CLASSIFY_TMP"; CLASSIFY_TMP=""
        fi
      fi
      # Give the classifier source metadata so it can infer recognizable subjects
      # such as a city, anime, movie, game, or character when the URL supports it.
      URL_HOST="$(printf '%s' "$URL" | sed -nE 's#^[a-zA-Z]+://([^/]+).*#\1#p' | tr '[:upper:]' '[:lower:]')"
      URL_BASENAME="$(basename "$URL" | sed 's/\?.*//;s/%20/ /g;s/-/ /g;s/_/ /g;s/\.[^.]*$//' | tr '[:upper:]' '[:lower:]')"
      COMBINED_QUERY="User search: ${SEARCH_QUERY:-unknown}; scraped website: ${URL_HOST:-unknown}; scraped file/title hint: ${URL_BASENAME:-unknown}"
      classify_out="$("$SCRIPT_DIR/classify_wallpaper.sh" "$CLASSIFY_FILE" "$WALLS_DIR" "$STATUS_FILE" "$NAME" "$COMBINED_QUERY" "$SEARCH_SOURCE" || true)"
      [[ -n "$CLASSIFY_TMP" ]] && rm -f "$CLASSIFY_TMP" || true
      if [[ "$classify_out" == "SUGGEST|"* ]]; then
        # AI returned multiple suggestions — let the user choose in QML.
        set_status "Choose a category..."
        printf 'AI_SUGGEST|%s\n' "${classify_out#SUGGEST|}"
        exit 3
      fi
      CATEGORY="$(printf '%s' "$classify_out" | cut -d'|' -f1)"
      SUGGESTED_NAME="$(printf '%s' "$classify_out" | cut -s -d'|' -f2)"
    fi
    if ! validate_category; then
      set_status "Choose a category..."
      printf 'NEED_CATEGORY|%s\n' "$NAME"
      exit 3
    fi
    # PRESET_NAME overrides AI-suggested name (set when user picked from AI_SUGGEST dialog).
    [[ -n "$PRESET_NAME" ]] && SUGGESTED_NAME="$PRESET_NAME" || true
    # Extension comes from the actual downloaded file, not the thumbnail name.
    ACTUAL_EXT="${FULL_FILE##*.}"
    THUMB_EXT="${NAME##*.}"
    SAVE_EXT="${ACTUAL_EXT:-$THUMB_EXT}"
    BASE_NAME="${NAME%.*}"
    if [[ -n "${SUGGESTED_NAME:-}" ]]; then
      SAVE_NAME="${SUGGESTED_NAME}.${SAVE_EXT}"
    else
      SAVE_NAME="${BASE_NAME}.${SAVE_EXT}"
    fi
    set_status "Saving to $CATEGORY..."
    mkdir -p "$WALLS_DIR/$CATEGORY"
    cp "$FULL_FILE" "$WALLS_DIR/$CATEGORY/$SAVE_NAME"
    set_status "Saved to $CATEGORY"
    printf 'SAVED|%s|%s\n' "$CATEGORY" "$SAVE_NAME"
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    exit 1
    ;;
esac
