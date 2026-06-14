#!/usr/bin/env bash
# Blend Nord palette with matugen wallpaper colors for Hyprland window borders.
# Reads waybar-settings.json for border settings, blends Nord base colors
# with /tmp/qs_colors.json (matugen output), applies via hyprctl eval.
# Falls back to pure Nord when matugen colors are unavailable.

set -euo pipefail

SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/waybar-settings.json"
COLORS="/tmp/qs_colors.json"

if [[ ! -f "$SETTINGS" ]]; then
    exit 0
fi

python3 - "$SETTINGS" "$COLORS" <<'PY'
import json, os, subprocess, sys

settings_path, colors_path = sys.argv[1:3]

with open(settings_path) as f:
    s = json.load(f)

border_adaptive = s.get("borderAdaptive", False)
if not border_adaptive:
    sys.exit(0)

ratio = float(s.get("borderBlendRatio", 0.3))
ratio = max(0.0, min(1.0, ratio))
border_vibrant = s.get("borderVibrant", False)
border_dominance = s.get("borderWallpaperDominance", False)
border_gradient = s.get("borderGradient", True)
border_inactive_adapt = s.get("borderInactiveAdapt", False)

# When dominance is OFF: pure Nord, no blending (ratio = 0)
# When dominance is ON: use slider ratio for wallpaper influence
if not border_dominance:
    ratio = 0.0

# Load matugen palette (optional — fall back to pure Nord if unavailable)
mat = {}
if os.path.isfile(colors_path):
    try:
        with open(colors_path) as f:
            mat = json.load(f)
    except Exception:
        pass
# When mat is empty, ratio effectively = 0 (pure Nord), so blend is a no-op.

# Nord palette — vibrant uses brighter, more saturated colors
if border_vibrant:
    NORD_ACTIVE1 = "5e81ac"   # Nord4 (frost blue)
    NORD_ACTIVE2 = "81a1c1"   # Nord11 (bright blue)
else:
    NORD_ACTIVE1 = "5e81ac"   # Nord4 (frost blue)
    NORD_ACTIVE2 = "88c0d0"   # Nord12 (frost cyan)
NORD_INACTIVE = "4c566a"     # Nord3
ALPHA = "cc"

def hex_to_rgb(h):
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgb_to_hex(rgb):
    return "{:02x}{:02x}{:02x}".format(*[max(0, min(255, int(round(c)))) for c in rgb])

def blend(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))

def safe_hex(val, default):
    if val is None:
        return default
    if isinstance(val, str):
        val = val.lstrip("#")
    return val if len(val) == 6 else default

# Active border: blend Nord4 with wallpaper's blue accent
mat_blue = safe_hex(mat.get("blue"), NORD_ACTIVE1)
blended_active = rgb_to_hex(blend(hex_to_rgb(NORD_ACTIVE1), hex_to_rgb(mat_blue), ratio))

# Gradient second color: blend Nord12 with wallpaper's green accent
if border_gradient:
    mat_green = safe_hex(mat.get("green"), NORD_ACTIVE2)
    blended_active2 = rgb_to_hex(blend(hex_to_rgb(NORD_ACTIVE2), hex_to_rgb(mat_green), ratio))
else:
    blended_active2 = None

# Inactive border
if border_inactive_adapt:
    mat_base = safe_hex(mat.get("base"), "1a1b26")
    blended_inactive = rgb_to_hex(blend(hex_to_rgb(NORD_INACTIVE), hex_to_rgb(mat_base), ratio * 0.5))
else:
    blended_inactive = NORD_INACTIVE

# Build Lua string for hyprctl eval
active_c1 = f"rgba({blended_active}{ALPHA})"
inactive_c = f"rgba({blended_inactive}{ALPHA})"

if border_gradient:
    active_c2 = f"rgba({blended_active2}{ALPHA})"
    active_lua = f'{{colors = {{"{active_c1}", "{active_c2}"}}, angle = 45}}'
else:
    active_lua = f'"{active_c1}"'

lua = f'hl.config({{general = {{["col.active_border"] = {active_lua}, ["col.inactive_border"] = "{inactive_c}"}}}})'

subprocess.run(["hyprctl", "eval", lua], check=False)
PY
