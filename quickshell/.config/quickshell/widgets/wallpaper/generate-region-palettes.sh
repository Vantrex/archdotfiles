#!/usr/bin/env bash

set -euo pipefail

IMAGE="${1:-}"
WAYBAR_OUT="/tmp/qs_waybar_colors.json"
DOCK_OUT="/tmp/qs_dock_colors.json"

if [[ -z "$IMAGE" || ! -f "$IMAGE" ]]; then
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

dims="$(magick identify -format '%w %h' "$IMAGE" 2>/dev/null || true)"
read -r width height <<<"${dims:-0 0}"
if (( width <= 0 || height <= 0 )); then
    exit 0
fi

waybar_h=35
dock_h=86
dock_w=$(( width * 35 / 100 ))

(( waybar_h > height )) && waybar_h="$height"
(( dock_h > height )) && dock_h="$height"
(( dock_w < 360 )) && dock_w=360
(( dock_w > width )) && dock_w="$width"

dock_x=$(( (width - dock_w) / 2 ))
dock_y=$(( height - dock_h ))

waybar_crop="$tmpdir/waybar.png"
dock_crop="$tmpdir/dock.png"

magick "$IMAGE" -crop "${width}x${waybar_h}+0+0" +repage "$waybar_crop"
magick "$IMAGE" -crop "${dock_w}x${dock_h}+${dock_x}+${dock_y}" +repage "$dock_crop"

render_palette() {
    local crop="$1"
    local out="$2"
    local raw="$tmpdir/raw.json"
    local average_hex

    matugen --dry-run --mode dark --source-color-index 0 --json hex image "$crop" >"$raw" 2>/dev/null || return 0
    average_hex="$(magick "$crop" -resize '1x1!' -format '%[hex:p{0,0}]' info: 2>/dev/null | cut -c1-6 || true)"

    python3 - "$raw" "$out" "$average_hex" <<'PY'
import json
import sys

raw_path, out_path, average_hex = sys.argv[1:4]

try:
    with open(raw_path) as f:
        data = json.load(f)
except Exception:
    raise SystemExit(0)

colors = data.get("colors", {})

def color(name):
    value = colors.get(name, {}).get("default", {}).get("color")
    return value if isinstance(value, str) and value.startswith("#") else None

def parse_hex(value):
    value = (value or "").strip().lstrip("#")
    if len(value) < 6:
        return None
    try:
        return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return None

def rgb_to_hex(rgb):
    return "#{:02x}{:02x}{:02x}".format(*[max(0, min(255, int(round(c)))) for c in rgb])

def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))

avg = parse_hex(average_hex)
if avg is None:
    avg = parse_hex(color("surface")) or (30, 30, 36)

white = (255, 255, 255)
black = (0, 0, 0)
luma = (0.2126 * avg[0] + 0.7152 * avg[1] + 0.0722 * avg[2]) / 255
is_light = luma >= 0.5

base = avg
mantle = mix(avg, black if is_light else white, 0.08)
crust = mix(avg, black if is_light else white, 0.16)
surface0 = mix(avg, black if is_light else white, 0.04)
surface1 = mix(avg, black if is_light else white, 0.14)
surface2 = mix(avg, black if is_light else white, 0.24)
text = (22, 24, 30) if is_light else (238, 238, 244)
subtext = (62, 64, 72) if is_light else (198, 200, 210)
overlay = (104, 106, 116) if is_light else (142, 144, 154)

palette = {
    "base": rgb_to_hex(base),
    "mantle": rgb_to_hex(mantle),
    "crust": rgb_to_hex(crust),
    "surface0": rgb_to_hex(surface0),
    "surface1": rgb_to_hex(surface1),
    "surface2": rgb_to_hex(surface2),
    "text": rgb_to_hex(text),
    "subtext0": rgb_to_hex(subtext),
    "subtext1": rgb_to_hex(subtext),
    "overlay0": rgb_to_hex(overlay),
    "overlay1": rgb_to_hex(mix(overlay, avg, 0.55)),
    "overlay2": rgb_to_hex(mix(overlay, avg, 0.4)),
    "blue": color("primary"),
    "sapphire": color("primary"),
    "mauve": color("secondary"),
    "pink": color("secondary"),
    "teal": color("secondary"),
    "green": color("tertiary"),
    "yellow": color("tertiary"),
    "peach": color("error"),
    "red": color("error"),
    "maroon": color("error"),
}

palette = {k: v for k, v in palette.items() if v}
if palette:
    with open(out_path, "w") as f:
        json.dump(palette, f, indent=2)
        f.write("\n")
PY
}

render_palette "$waybar_crop" "$WAYBAR_OUT"
render_palette "$dock_crop" "$DOCK_OUT"
