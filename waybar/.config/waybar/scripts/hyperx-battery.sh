#!/usr/bin/env bash
# Combined battery module — alternates between Logitech mouse and HyperX headset.
# Each device shows with its own icon (mouse / headset) + battery icon + percentage.

set -uo pipefail

STATE_FILE="/tmp/.waybar-battery-state"

# Nerd Font device icons
MOUSE_ICON=""
HEADSET_ICON=""

battery_icon() {
    local p=$1
    if   (( p <= 10 )); then echo "󰂎"
    elif (( p <= 20 )); then echo "󰂏"
    elif (( p <= 30 )); then echo "󰂐"
    elif (( p <= 40 )); then echo "󰂑"
    elif (( p <= 50 )); then echo "󰂒"
    elif (( p <= 60 )); then echo "󰂓"
    elif (( p <= 70 )); then echo "󰂔"
    elif (( p <= 80 )); then echo "󰂕"
    elif (( p <= 90 )); then echo "󰂖"
    else                     echo "󰁚"
    fi
}

# ---------- Read Logitech mouse (upower) ----------
read_mouse() {
    local pct state
    pct=$(upower -d 2>/dev/null \
        | awk '/^Device:.*battery_hidpp_battery_0/{found=1} found && /percentage:/{gsub(/%/,"",$2); print $2; exit}')
    state=$(upower -d 2>/dev/null \
        | awk '/^Device:.*battery_hidpp_battery_0/{found=1} found && /state:/{print $2; exit}')

    [ -z "$pct" ] && return 1
    echo "${pct}|${state:-unknown}"
}

# ---------- Read HyperX headset (HyperHeadset CLI) ----------
read_headset() {
    local output
    output=$(hyper_headset_cli --json 2>/dev/null)
    [ $? -ne 0 ] || [ -z "$output" ] && return 1

    local battery charging connected
    battery=$(echo "$output" | rg '"battery_level":\s*([0-9]+)' --replace '$1' -o | head -1)
    charging=$(echo "$output" | rg '"charging_status":\s*"([^"]+)"' --replace '$1' -o | head -1)
    connected=$(echo "$output" | rg '"connected":\s*(true|false)' --replace '$1' -o | head -1)

    [ -z "$battery" ] && return 1
    echo "${battery}|${charging}|${connected}"
}

# ---------- Determine which device to show ----------
last=${last:-0}
if [ -f "$STATE_FILE" ]; then
    last=$(cat "$STATE_FILE")
fi
next=$(( 1 - last ))
echo "$next" > "$STATE_FILE"

mouse_data=$(read_mouse 2>/dev/null || echo "")
headset_data=$(read_headset 2>/dev/null || echo "")

# Prefer the requested device; fall back to the other.
if [ "$next" -eq 0 ]; then
    # Show mouse
    if [ -n "$mouse_data" ]; then
        IFS='|' read -r pct state <<< "$mouse_data"
        bicon=$(battery_icon "$pct")
        if [ "$state" = "charging" ]; then
            bicon="<span color='#a6d189'>󱐋</span>"
        fi
        tooltip="Logitech PRO X (mouse) — ${pct}% — ${state}"
        printf '{"text":" %s %s %s%%","tooltip":"%s"}\n' "$MOUSE_ICON" "$bicon" "$pct" "$tooltip"
        exit 0
    fi
fi

if [ -n "$headset_data" ]; then
    IFS='|' read -r battery charging connected <<< "$headset_data"
    bicon=$(battery_icon "$battery")
    if [ "$charging" = "Charging" ]; then
        bicon="<span color='#a6d189'>󱐋</span>"
    fi
    tooltip="HyperX Cloud III S — ${battery}% — ${charging}\nConnected: ${connected}"
    printf '{"text":" %s %s %s%%","tooltip":"%s"}\n' "$HEADSET_ICON" "$bicon" "$battery" "$tooltip"
    exit 0
fi

if [ -n "$mouse_data" ]; then
    IFS='|' read -r pct state <<< "$mouse_data"
    bicon=$(battery_icon "$pct")
    if [ "$state" = "charging" ]; then
        bicon="<span color='#a6d189'>󱐋</span>"
    fi
    tooltip="Logitech PRO X (mouse) — ${pct}% — ${state}"
    printf '{"text":" %s %s %s%%","tooltip":"%s"}\n' "$MOUSE_ICON" "$bicon" "$pct" "$tooltip"
    exit 0
fi

printf '{"text":" 󰂎 ?","tooltip":"No battery devices detected"}\n'
