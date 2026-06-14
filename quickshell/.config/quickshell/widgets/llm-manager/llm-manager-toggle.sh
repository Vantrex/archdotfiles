#!/usr/bin/env bash
# Toggle the Quickshell LLM manager on the active monitor.

STATE_FILE="/tmp/qs_llm_manager_state"

ACTIVE=$(hyprctl activeworkspace 2>/dev/null | head -1 | sed -n 's/.*on monitor \([^:]*\):.*/\1/p')
if [ -z "$ACTIVE" ]; then
    ACTIVE=$(hyprctl monitors 2>/dev/null | awk '/^Monitor / {print $2; exit}')
fi

TARGET="llm-manager-toggle-$ACTIVE"

if [ "$(cat "$STATE_FILE" 2>/dev/null)" = "visible" ]; then
    qs ipc show 2>/dev/null | grep "target llm-manager-toggle-" | while read -r _ target_name; do
        qs ipc call "$target_name" setVisible false
    done
    echo "hidden" > "$STATE_FILE"
else
    qs ipc call "$TARGET" setVisible true
    echo "visible" > "$STATE_FILE"
fi
