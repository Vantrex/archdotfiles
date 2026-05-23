#!/usr/bin/env bash
# Toggle Quickshell wallpaper picker overlay on the active monitor only.

STATE_FILE="/tmp/qs_wallpicker_state"

# Active monitor name from Hyprland (the monitor hosting the focused workspace).
# Output format: "workspace ID N (name) on monitor MONITOR-NAME:"
ACTIVE=$(hyprctl activeworkspace 2>/dev/null | head -1 | sed -n 's/.*on monitor \([^:]*\):.*/\1/p')

if [ -z "$ACTIVE" ]; then
    # Fallback: first monitor reported by hyprctl.
    ACTIVE=$(hyprctl monitors 2>/dev/null | awk '/^Monitor / {print $2; exit}')
fi

TARGET="wallpaper-toggle-$ACTIVE"

if [ "$(cat "$STATE_FILE" 2>/dev/null)" = "visible" ]; then
    # Hide on every monitor (in case it was opened on multiple before).
    qs ipc show 2>/dev/null | grep "target wallpaper-toggle-" | while read -r _ target_name; do
        qs ipc call "$target_name" setVisible false
    done
    echo "hidden" > "$STATE_FILE"
else
    qs ipc call "$TARGET" setVisible true
    echo "visible" > "$STATE_FILE"
fi
