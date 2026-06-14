#!/usr/bin/env bash
# Toggle Quickshell dock overlay on the active monitor only.

STATE_FILE="/tmp/qs_dock_state"

# Active monitor name from Hyprland (the monitor hosting the focused workspace).
ACTIVE=$(hyprctl activeworkspace 2>/dev/null | head -1 | sed -n 's/.*on monitor \([^:]*\):.*/\1/p')
if [ -z "$ACTIVE" ]; then
    ACTIVE=$(hyprctl monitors 2>/dev/null | awk '/^Monitor / {print $2; exit}')
fi

TARGET="dock-toggle-$ACTIVE"

if [ -z "$ACTIVE" ]; then
    echo "hidden" > "$STATE_FILE"
    exit 1
fi

ANY_VISIBLE=false
for target_name in $(qs ipc show 2>/dev/null | awk '/target dock-toggle-/ {print $2}'); do
    if [ "$(qs ipc call "$target_name" getVisible 2>/dev/null)" = "true" ]; then
        ANY_VISIBLE=true
        break
    fi
done

if [ "$ANY_VISIBLE" = "true" ]; then
    for target_name in $(qs ipc show 2>/dev/null | awk '/target dock-toggle-/ {print $2}'); do
        qs ipc call "$target_name" setVisible false >/dev/null 2>&1
    done
    echo "hidden" > "$STATE_FILE"
else
    if qs ipc call "$TARGET" setVisible true >/dev/null 2>&1; then
        echo "visible" > "$STATE_FILE"
    else
        echo "hidden" > "$STATE_FILE"
        exit 1
    fi
fi
