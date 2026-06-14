#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?image path required}"
WALLS_DIR="${2:?wallpaper directory required}"
STATUS_FILE="${3:-}"
ORIGINAL_NAME="${4:-}"
SEARCH_QUERY="${5:-}"
SEARCH_SOURCE="${6:-}"
CACHE_DIR="$HOME/.cache/wallpaper_picker"
SERVER_BIN="$HOME/work/llm/llama.cpp/build/bin/llama-server"
MODEL_PATH="$HOME/.cache/huggingface/hub/models--bartowski--google_gemma-3-4b-it-GGUF/blobs/google_gemma-3-4b-it-Q4_K_M.gguf"
MMPROJ_PATH="$HOME/.cache/huggingface/hub/models--bartowski--google_gemma-3-4b-it-GGUF/blobs/mmproj-google_gemma-3-4b-it-f16.gguf"
OWN_PORT=18081
OWN_PID_FILE="$CACHE_DIR/classifier-server.pid"
OWN_STAMP_FILE="$CACHE_DIR/classifier-server.stamp"
START_LOCK="$CACHE_DIR/.classifier-start.lock"
LOG_FILE="$CACHE_DIR/classifier-server.log"

mkdir -p "$CACHE_DIR"

set_status() {
  [[ -n "$STATUS_FILE" ]] && printf '%s\n' "$1" > "$STATUS_FILE" || true
}

# Returns true when the filename looks like a download hash/timestamp with no
# human-readable meaning (e.g. ddg_1777850217237195326.jpg, abc123def456.png).
needs_rename() {
  local base="${1%.*}"
  [[ "$base" =~ ^(ddg|pinterest|img|image|photo|screenshot|download|wp|wall)_[0-9] ]] ||
  [[ "$base" =~ ^[0-9a-f]{16,}$ ]] ||
  [[ "$base" =~ ^[0-9]{8,}$ ]]
}

DO_NAME=false
[[ -n "$ORIGINAL_NAME" ]] && needs_rename "$ORIGINAL_NAME" && DO_NAME=true

mapfile -t CATEGORIES < <(
  find "$WALLS_DIR" -mindepth 1 -maxdepth 1 -type d \
    ! -name '.*' -printf '%f\n' | sort
)

if (( ${#CATEGORIES[@]} == 0 )); then
  echo "No wallpaper categories found in $WALLS_DIR" >&2
  exit 1
fi

CATEGORY_LIST="$(printf '%s\n' "${CATEGORIES[@]}")"

# Context hints for the prompts.
CONTEXT_HINT=""
[[ -n "$SEARCH_QUERY"  ]] && CONTEXT_HINT+=$'\n'"Scrape metadata: ${SEARCH_QUERY}"
if [[ -n "$SEARCH_SOURCE" ]]; then
  case "$SEARCH_SOURCE" in
    moewalls) CONTEXT_HINT+=$'\n'"Source: MoeWalls (anime/gaming animated wallpaper site — content is almost certainly anime or gaming related)" ;;
    pexels)   CONTEXT_HINT+=$'\n'"Source: Pexels (stock video/photo library — content is real-world: nature, cities, abstract, etc.)" ;;
    ddg)      CONTEXT_HINT+=$'\n'"Source: DuckDuckGo image search" ;;
    pinterest)CONTEXT_HINT+=$'\n'"Source: Pinterest image search" ;;
  esac
fi

# Prompts — classify-only (no renaming) and classify+suggestions.
PROMPT_CLASSIFY="Classify the attached wallpaper into exactly one of these existing categories:
$CATEGORY_LIST
${CONTEXT_HINT}
Return only the category name. Do not explain your answer and do not add punctuation."

PROMPT_COMBINED="Suggest the 5 best matching categories for this wallpaper, sorted from most likely to least likely. Then suggest 5 short descriptive filenames, also sorted from most likely to least likely.

Available categories:
$CATEGORY_LIST
${CONTEXT_HINT}
Each filename must use 2-4 words in snake_case (no extension, lowercase, underscores only).
Use the scrape metadata and source website as clues. When supported by those clues and the visible image, identify what is shown as specifically as possible: for example a city, landmark, anime, movie, game, franchise, or character. Include the likely identifying name in the filename suggestions. Prefer recognizable names over generic words such as city, anime, or movie.
Do not invent a specific identity when the clues are weak or conflicting. In that case, use an accurate descriptive filename.

Reply in this EXACT format — 10 pipe-separated values, nothing else:
<best_category>|<second_category>|<third_category>|<fourth_category>|<fifth_category>|<best_name>|<second_name>|<third_name>|<fourth_name>|<fifth_name>

Example: anime|dreamcore|weirdcore|gaming|cyberpunk|girl_rooftop_city_night|anime_city_rooftop|night_city_girl|rooftop_skyline_anime|city_lights_rooftop"

valid_category() {
  local answer="$1"
  local category
  while IFS= read -r category; do
    [[ "$answer" == "$category" ]] && return 0
  done <<< "$CATEGORY_LIST"
  return 1
}

extract_category() {
  local raw="$1"
  local category
  while IFS= read -r category; do
    if grep -Fqx "$category" <<< "$raw"; then
      printf '%s\n' "$category"
      return 0
    fi
  done <<< "$CATEGORY_LIST"
  return 1
}

# Outputs "CATEGORY" or "SUGGEST|cat...|NAMES|name..." depending on $DO_NAME.
classify_with_server() {
  local port="$1"
  local mime payload response raw category suggested
  mime="$(file -b --mime-type "$IMAGE")"
  payload="$(mktemp)"

  if [[ "$DO_NAME" == true ]]; then
    local prompt="$PROMPT_COMBINED"
    local max_tokens=160
  else
    local prompt="$PROMPT_CLASSIFY"
    local max_tokens=32
  fi

  python3 - "$prompt" "$mime" "$IMAGE" "$max_tokens" > "$payload" <<'PY'
import base64, json, sys
prompt, mime, image_path, max_tok = sys.argv[1:]
with open(image_path, "rb") as f:
    encoded = base64.b64encode(f.read()).decode("ascii")
json.dump({
    "messages": [
        {"role": "system", "content": "Follow the output format exactly."},
        {"role": "user", "content": [
            {"type": "text", "text": prompt},
            {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{encoded}"}},
        ]},
    ],
    "temperature": 0,
    "max_tokens": int(max_tok),
}, sys.stdout)
PY

  response="$(curl -fsS --max-time 120 \
    -H 'Content-Type: application/json' \
    --data-binary "@$payload" "http://127.0.0.1:$port/v1/chat/completions" 2>/dev/null)" || {
      rm -f "$payload"
      return 1
    }
  rm -f "$payload"

  raw="$(jq -r '.choices[0].message.content // empty' <<< "$response" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  if [[ "$DO_NAME" == true ]]; then
    # Expect five ordered categories followed by five ordered names.
    local -a fields categories names
    local field cleaned joined_categories joined_names
    IFS='|' read -r -a fields <<< "$raw"
    (( ${#fields[@]} >= 10 )) || return 1

    for field in "${fields[@]:0:5}"; do
      cleaned="$(printf '%s' "$field" | tr -d '[:space:]')"
      valid_category "$cleaned" || continue
      [[ " ${categories[*]:-} " == *" $cleaned "* ]] || categories+=("$cleaned")
    done
    (( ${#categories[@]} > 0 )) || return 1

    for field in "${fields[@]:5:5}"; do
      cleaned="$(printf '%s' "$field" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:] ' '[:lower:]_' | tr -cd 'a-z0-9_')"
      [[ -n "$cleaned" ]] || continue
      [[ " ${names[*]:-} " == *" $cleaned "* ]] || names+=("$cleaned")
    done
    (( ${#names[@]} > 0 )) || return 1

    joined_categories="$(IFS='|'; printf '%s' "${categories[*]}")"
    joined_names="$(IFS='|'; printf '%s' "${names[*]}")"
    printf 'SUGGEST|%s|NAMES|%s\n' "$joined_categories" "$joined_names"
  else
    valid_category "$raw" || return 1
    printf '%s\n' "$raw"
  fi
}

server_ready() {
  curl -fsS --max-time 2 "http://127.0.0.1:$1/health" >/dev/null 2>&1
}

start_idle_watchdog() {
  (
    sleep 300
    [[ -f "$OWN_PID_FILE" && -f "$OWN_STAMP_FILE" ]] || exit 0
    if (( $(date +%s) - $(stat -c %Y "$OWN_STAMP_FILE") >= 300 )); then
      pid="$(cat "$OWN_PID_FILE" 2>/dev/null || true)"
      [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
      rm -f "$OWN_PID_FILE" "$OWN_STAMP_FILE"
    fi
  ) >/dev/null 2>&1 &
}

touch_owned_server() {
  touch "$OWN_STAMP_FILE"
  start_idle_watchdog
}

mapfile -t SERVER_PORTS < <(
  {
    printf '%s\n' 8080 "$OWN_PORT"
    pgrep -af '[l]lama-server' 2>/dev/null |
      sed -nE 's/.*--port([ =]+)([0-9]+).*/\2/p'
  } | awk '!seen[$0]++'
)

for port in "${SERVER_PORTS[@]}"; do
  if server_ready "$port"; then
    set_status "Classifying wallpaper..."
    if answer="$(classify_with_server "$port")"; then
      [[ "$port" == "$OWN_PORT" ]] && touch_owned_server
      printf '%s\n' "$answer"
      exit 0
    fi
  fi
done

if [[ -x "$SERVER_BIN" && -f "$MODEL_PATH" && -f "$MMPROJ_PATH" ]]; then
  owns_start_lock=false
  if [[ -d "$START_LOCK" ]] && find "$START_LOCK" -maxdepth 0 -mmin +10 -print -quit | grep -q .; then
    rmdir "$START_LOCK" 2>/dev/null || true
  fi

  if ! server_ready "$OWN_PORT" && mkdir "$START_LOCK" 2>/dev/null; then
    owns_start_lock=true
    set_status "Starting local classifier..."
    nohup "$SERVER_BIN" \
      --model "$MODEL_PATH" --mmproj "$MMPROJ_PATH" \
      --host 127.0.0.1 --port "$OWN_PORT" \
      -ngl 0 --no-mmproj-offload \
      >"$LOG_FILE" 2>&1 &
    printf '%s\n' "$!" > "$OWN_PID_FILE"
  fi

  for _ in $(seq 1 180); do
    if server_ready "$OWN_PORT"; then
      set_status "Classifying wallpaper..."
      if answer="$(classify_with_server "$OWN_PORT")"; then
        [[ "$owns_start_lock" == true ]] && rmdir "$START_LOCK" 2>/dev/null || true
        touch_owned_server
        printf '%s\n' "$answer"
        exit 0
      fi
      break
    fi
    sleep 2
  done
  [[ "$owns_start_lock" == true ]] && rmdir "$START_LOCK" 2>/dev/null || true
fi

if command -v codex >/dev/null 2>&1; then
  set_status "Trying Codex classifier..."
  OUTPUT_FILE="$(mktemp)"
  trap 'rm -f "$OUTPUT_FILE"' EXIT
  if codex exec --ephemeral --skip-git-repo-check \
      --sandbox read-only --ask-for-approval never \
      -i "$IMAGE" -o "$OUTPUT_FILE" "$PROMPT_CLASSIFY" >/dev/null 2>&1; then
    if answer="$(extract_category "$(cat "$OUTPUT_FILE")")"; then
      printf '%s\n' "$answer"
      exit 0
    fi
  fi
fi

exit 1
