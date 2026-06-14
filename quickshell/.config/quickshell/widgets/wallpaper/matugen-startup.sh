#!/usr/bin/env bash

VIDEO_STATE="$HOME/.cache/wallpaper_picker/last_video_wallpaper.txt"
REGION_SCRIPT="$HOME/.config/quickshell/widgets/wallpaper/generate-region-palettes.sh"

# If a video wallpaper was last set, restore it with mpvpaper before awww runs.
if [[ -f "$VIDEO_STATE" ]]; then
    video=$(cat "$VIDEO_STATE")
    if [[ -f "$video" ]]; then
        pkill -x mpvpaper 2>/dev/null || true
        mpvpaper -o "--loop-file=inf" '*' "$video" &
        # Regenerate matugen palette from a still frame of the video.
        still=$(mktemp --suffix=.jpg)
        ffmpegthumbnailer -i "$video" -o "$still" -s 0 -q 10 2>/dev/null || \
            ffmpeg -y -i "$video" -vframes 1 "$still" 2>/dev/null || true
        if [[ -f "$still" && -s "$still" ]]; then
            matugen --mode dark --source-color-index 0 image "$still" || true
            bash "$REGION_SCRIPT" "$still" || true
            bash "$HOME/.config/quickshell/widgets/wallpaper/matugen_reload.sh" || true
        fi
        rm -f "$still"
        exit 0
    fi
fi

# /tmp is cleared on reboot. Wait for awww to restore its wallpaper, then
# regenerate the shared Matugen palette once for Quickshell and other consumers.
for _ in {1..60}; do
    wallpaper=$(awww query 2>/dev/null |
        sed -n 's/.*currently displaying: image: //p' |
        head -n 1)

    if [[ -n "$wallpaper" && -f "$wallpaper" ]]; then
        matugen --mode dark --source-color-index 0 image "$wallpaper" || true
        bash "$REGION_SCRIPT" "$wallpaper" || true
        bash "$HOME/.config/quickshell/widgets/wallpaper/matugen_reload.sh" || true
        exit 0
    fi

    sleep 1
done

exit 0
