#!/usr/bin/env bash

QUERY="$1"
SEARCH_SOURCE="$2"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CACHE_DIR="$HOME/.cache/wallpaper_picker"
SEARCH_DIR="$CACHE_DIR/search_thumbs"
MAP_FILE="$CACHE_DIR/search_map.txt"
CONTROL_FILE="/tmp/ddg_search_control"
LOG_FILE="/tmp/qs_ddg_downloader.log"

echo "=== Starting search for: $QUERY (source: $SEARCH_SOURCE) ===" > "$LOG_FILE"

mkdir -p "$SEARCH_DIR"

if [ "$SEARCH_SOURCE" = "pinterest" ]; then
    PYTHON_SCRIPT="$SCRIPT_DIR/pinterest_search.py"
elif [ "$SEARCH_SOURCE" = "moewalls" ]; then
    PYTHON_SCRIPT="$SCRIPT_DIR/moewalls_search.py"
elif [ "$SEARCH_SOURCE" = "pexels" ]; then
    PYTHON_SCRIPT="$SCRIPT_DIR/pexels_search.py"
else
    PYTHON_SCRIPT="$SCRIPT_DIR/get_ddg_links.py"
fi

python3 -u "$PYTHON_SCRIPT" "$QUERY" | {
first_line=""
while IFS= read -r line; do
    if [[ -z "$first_line" ]]; then
        first_line="$line"
        if [[ "$line" == "PEXELS_NO_KEY" ]]; then
            echo "PEXELS_NO_KEY" > "$SEARCH_DIR/../pexels_status.txt"
            exit 0
        fi
    fi
    printf '%s\n' "$line"
done
} | while IFS='|' read -r thumb_url full_url width height; do

    state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')

    if [[ "$state" == "stop" ]]; then
        echo "Stop signal received. Exiting." >> "$LOG_FILE"
        exit 0
    fi

    while [[ "$state" == "pause" ]]; do
        sleep 1
        state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    done

    if [ -z "$thumb_url" ] || [ -z "$full_url" ]; then continue; fi

    # Detect video URLs (moewalls and any other source returning mp4/webm)
    full_ext="${full_url##*.}"
    full_ext="${full_ext%%\?*}"
    full_ext=$(echo "$full_ext" | tr '[:upper:]' '[:lower:]')
    is_video_result=0
    if [[ "$full_ext" =~ ^(mp4|webm|mkv|mov)$ ]]; then
        is_video_result=1
    fi

    if [[ "$is_video_result" -eq 0 ]]; then
        target_headers=$(curl -s -I -L -m 3 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$full_url")
        target_type=$(echo "$target_headers" | grep -i "content-type:" | tail -n 1 | tr -d '\r')
        if [[ ! "$target_type" =~ "image/" ]]; then
            echo "Skip: Full URL is dead or HTML ($target_type) -> $full_url" >> "$LOG_FILE"
            continue
        fi
    fi

    uuid=$(date +%s%N)
    # Thumbnail is always an image; use jpg for video results
    if [[ "$is_video_result" -eq 1 ]]; then
        thumb_ext="jpg"
    else
        thumb_ext="${full_url##*.}"
        thumb_ext="${thumb_ext%%\?*}"
        thumb_ext=$(echo "$thumb_ext" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$thumb_ext" =~ ^(jpg|jpeg|png|webp|gif)$ ]]; then thumb_ext="jpg"; fi
    fi
    ext="$thumb_ext"

    is_webp=0
    if [[ "$ext" == "webp" ]]; then
        is_webp=1
        ext="jpg"
    fi

    filename="ddg_${uuid}.${ext}"
    filepath="$SEARCH_DIR/$filename"
    tmppath="${filepath}.tmp"

    # For GIFs: fetch the actual full GIF (up to 20 MB) so the thumbnail is animated.
    # For everything else: fetch the small static DDG thumbnail.
    if [[ "$ext" == "gif" ]]; then
        gif_size=$(echo "$target_headers" | grep -i "^content-length:" | tail -n 1 | tr -d '\r ' | cut -d: -f2)
        if [[ -n "$gif_size" && "$gif_size" -lt 20971520 ]]; then
            echo "Downloading full GIF: $full_url -> $filename" >> "$LOG_FILE"
            curl -s -L -m 60 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$full_url" -o "$tmppath"
        else
            echo "GIF too large or unknown size ($gif_size), falling back to thumb: $thumb_url" >> "$LOG_FILE"
            curl -s -L -m 5 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$thumb_url" -o "$tmppath"
        fi
    else
        echo "Downloading Thumb: $thumb_url -> $filename" >> "$LOG_FILE"
        curl -s -L -m 5 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$thumb_url" -o "$tmppath"
    fi

    state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    if [[ "$state" == "stop" ]]; then
        echo "Stop signal received during download. Discarding." >> "$LOG_FILE"
        rm -f "$tmppath"
        exit 0
    fi

    if [ -s "$tmppath" ]; then
        actual_mime=$(file -b --mime-type "$tmppath")

        if [[ ! "$actual_mime" =~ ^image/ ]]; then
            echo "ERROR: Thumb is not an image ($actual_mime). Discarding." >> "$LOG_FILE"
            rm -f "$tmppath"
        else
            if [[ "$ext" == "gif" && "$actual_mime" == "image/gif" ]]; then
                # Resize GIF preserving all frames for animated thumbnail
                magick "$tmppath" -resize x420 "$filepath" 2>/dev/null || mv "$tmppath" "$filepath"
                rm -f "$tmppath"
            elif [[ "$actual_mime" == "image/webp" ]] || [ $is_webp -eq 1 ]; then
                magick "$tmppath" "$filepath" 2>/dev/null || mv "$tmppath" "$filepath"
                rm -f "$tmppath"
            else
                mv "$tmppath" "$filepath"
            fi
            dimensions=""
            if [[ -n "$width" && -n "$height" ]]; then dimensions="${width}x${height}"; fi
            type_tag=""
            if [[ "$is_video_result" -eq 1 ]]; then type_tag="|video"; fi
            echo "$filename|$full_url|$dimensions${type_tag}" >> "$MAP_FILE"
            echo "Success: $filename saved." >> "$LOG_FILE"
        fi
    else
        echo "ERROR: Failed or empty download for $thumb_url" >> "$LOG_FILE"
        rm -f "$tmppath"
    fi
done

echo "=== Pipeline finished ===" >> "$LOG_FILE"
