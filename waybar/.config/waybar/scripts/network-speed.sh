#!/usr/bin/env bash
# Output network rx/tx speeds for waybar custom module (JSON).
# Uses /proc/net/dev deltas across the polling interval (waybar respawns the
# script every `interval` seconds, so we sample twice 1s apart inside).

set -euo pipefail

read_bytes() {
    awk '
        /^[[:space:]]*lo:/ { next }
        /:/ {
            sub(":", "")
            rx += $2
            tx += $10
        }
        END { print rx, tx }
    ' /proc/net/dev
}

read -r rx1 tx1 < <(read_bytes)
sleep 1
read -r rx2 tx2 < <(read_bytes)

drx=$((rx2 - rx1))
dtx=$((tx2 - tx1))

human() {
    local n=$1
    if   (( n > 1073741824 )); then awk -v n=$n 'BEGIN{printf "%.1fG", n/1073741824}'
    elif (( n > 1048576    )); then awk -v n=$n 'BEGIN{printf "%.1fM", n/1048576}'
    elif (( n > 1024       )); then awk -v n=$n 'BEGIN{printf "%.1fK", n/1024}'
    else                            printf '%dB' "$n"
    fi
}

down=$(human $drx)
up=$(human $dtx)

printf '{"text":"  %s   %s","tooltip":"Down: %s/s\\nUp: %s/s"}\n' "$down" "$up" "$down" "$up"
