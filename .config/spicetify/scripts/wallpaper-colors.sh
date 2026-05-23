#!/usr/bin/env bash
# Generate spicetify Marketplace theme colors from the current wallpaper.
# Writes [Base] section with keys that spicetify recognizes (text, main, sidebar, etc.).
# Also writes to color_scheme config for CSS variable access.
# When disabled in waybar-settings.json, restores empty [Marketplace].

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
COLORS="/tmp/qs_colors.json"
SETTINGS="$CONFIG_DIR/waybar/waybar-settings.json"
THEME_DIR="$CONFIG_DIR/spicetify/Themes/marketplace"
OUT="$THEME_DIR/color.ini"
SPICE_CFG="$CONFIG_DIR/spicetify/config-xpui.ini"

mkdir -p "$THEME_DIR"

if [[ ! -f "$SETTINGS" ]]; then
    echo "[Marketplace]" > "$OUT"
    exit 0
fi

# Get current wallpaper from awww
WALLPAPER=""
if command -v awww &> /dev/null; then
    WALLPAPER=$(awww query 2>/dev/null | grep 'currently displaying: image:' | head -1 | sed 's/.*image: //')
fi

# Try matugen first (with explicit flags since we're non-interactive)
if [[ -n "$WALLPAPER" && -f "$WALLPAPER" ]] && command -v matugen &> /dev/null; then
    if matugen --mode dark --prefer=darkness image "$WALLPAPER" 2>/dev/null; then
        : # matugen may have written to COLORS or not (4.x changed behavior)
    fi
fi

if [[ ! -f "$SETTINGS" ]]; then
    echo "[Marketplace]" > "$OUT"
    exit 0
fi

python3 - "$SETTINGS" "$COLORS" "$WALLPAPER" "$THEME_DIR" <<'PY'
import json, os, re, sys, subprocess

settings_path, colors_path, wallpaper, theme_dir = sys.argv[1:5]

with open(settings_path) as f:
    s = json.load(f)

if not s.get("spicetifyAdaptive", False):
    with open(os.path.join(theme_dir, "color.ini"), "w") as f:
        f.write("[Marketplace]\n")
    sys.exit(0)

mat = {}  # Catppuccin-style color map

# Try to load matugen output (Catppuccin keys from /tmp/qs_colors.json)
if os.path.isfile(colors_path):
    try:
        with open(colors_path) as f:
            raw = json.load(f)
        for k in ["base","mantle","crust","text","subtext0","subtext1",
                   "surface0","surface1","surface2","overlay0","overlay1","overlay2",
                   "blue","sapphire","peach","green","red","mauve","pink","yellow","maroon","teal"]:
            if k in raw:
                mat[k] = str(raw[k])
        # base16 format — map to Catppuccin equivalents (dark theme)
        if not mat and "base16" in raw:
            b16 = raw["base16"]
            dark_colors = {}
            for name, vals in b16.items():
                if isinstance(vals, dict):
                    c = vals.get("dark", vals.get("default", "#000000"))
                    hex_val = c.get("color", c) if isinstance(c, dict) else str(c)
                    dark_colors[name] = hex_val
            mapping = {
                "base00": "crust",   "base01": "mantle",  "base02": "surface0",
                "base03": "overlay0","base04": "subtext1","base05": "text",
                "base06": "surface1","base07": "overlay2"
            }
            for b16_name, cat_name in mapping.items():
                if b16_name in dark_colors:
                    mat[cat_name] = str(dark_colors[b16_name])
            accent_keys = ["blue","sapphire","peach","green","red","mauve","pink","yellow","maroon","teal"]
            for i, akey in enumerate(accent_keys):
                b16_key = f"base{8 + i}"
                if b16_key in dark_colors:
                    mat[akey] = str(dark_colors[b16_key])
    except Exception:
        pass

# Fallback: extract colors from wallpaper using ImageMagick magick command (IMv7)
if not mat and wallpaper and os.path.isfile(wallpaper):
    try:
        result = subprocess.run(
            ["magick", wallpaper, "-resize", "200x200", "-colors", "16",
             "-depth", "8", "txt:-"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            colors = {}
            for line in result.stdout.split('\n'):
                m = re.search(r'#([0-9a-fA-F]{6})\s+srgb\((\d+),(\d+),(\d+)\)', line)
                if m:
                    hex_val = '#' + m.group(1).lower()
                    r, g, b = int(m.group(2)), int(m.group(3)), int(m.group(4))
                    colors[(r, g, b)] = hex_val

            def brightness(c):
                return c[0]*0.299 + c[1]*0.587 + c[2]*0.114

            sorted_colors = sorted(colors.keys(), key=brightness, reverse=True)

            mat["crust"]     = sorted_colors[-1] if len(sorted_colors) >= 16 else "#11111b"
            mat["base"]      = sorted_colors[-3] if len(sorted_colors) >= 14 else "#1e1e2e"
            mat["mantle"]    = sorted_colors[-2] if len(sorted_colors) >= 15 else "#181825"

            accent_keys = ["blue","sapphire","peach","green","red","mauve","pink","yellow","maroon","teal"]
            for i, akey in enumerate(accent_keys):
                src_idx = min(i, len(sorted_colors) - 1) if sorted_colors else 0
                mat[akey] = colors.get(sorted_colors[src_idx], "#89b4fa")

            mat["surface0"]  = sorted_colors[-5] if len(sorted_colors) >= 12 else "#313244"
            mat["surface1"]  = sorted_colors[-6] if len(sorted_colors) >= 11 else "#45475a"

            mid_idx = max(0, min(len(sorted_colors)//2, 9))
            mat["text"]      = colors.get(sorted_colors[mid_idx], "#cdd6f4")
            mat["subtext1"]  = colors.get(sorted_colors[mid_idx + 1] if mid_idx + 1 < len(sorted_colors) else sorted_colors[-8], "#bac2de")
            mat["overlay0"]  = colors.get(sorted_colors[-9] if len(sorted_colors) >= 7 else "#6c7086", "#6c7086")
            mat["overlay1"]  = colors.get(sorted_colors[-10] if len(sorted_colors) >= 6 else "#7f849c", "#7f849c")
            mat["overlay2"]  = colors.get(sorted_colors[-11] if len(sorted_colors) >= 5 else "#9399b2", "#9399b2")

            # Ensure text is readable (if too dark, lighten it)
            t = mat.get("text", "")
            if t:
                h = t.lstrip("#")
                r_val, g_val, b_val = int(h[0:2],16), int(h[2:4],16), int(h[4:6],16)
                if brightness((r_val,g_val,b_val)) < 80:
                    mat["text"] = "#{:02x}{:02x}{:02x}".format(
                        min(255,r_val+140), min(255,g_val+140), min(255,b_val+140))
                mat["subtext1"] = "#{:02x}{:02x}{:02x}".format(
                    max(0,r_val-30), max(0,g_val-30), max(0,b_val-30))
    except Exception:
        pass

# If still no colors, use empty (spicetify defaults)
if not mat:
    with open(os.path.join(theme_dir, "color.ini"), "w") as f:
        f.write("[Marketplace]\n")
    sys.exit(0)

def clamp(v, lo=-64, hi=64):
    return max(lo, min(hi, v))

def adjust(hex_str, delta):
    h = hex_str.lstrip("#")
    r = int(h[0:2], 16) + clamp(delta)
    g = int(h[2:4], 16) + clamp(delta)
    b = int(h[4:6], 16) + clamp(delta)
    return "#{:02x}{:02x}{:02x}".format(r, g, b)

# Map matugen colors → spicetify theme color keys ([Base] section)
# These are the actual keys spicetify reads from color.ini
base_colors = {
    "text":         ("text",      0),   # primary text color
    "subtext":      ("subtext1",  0),   # secondary text (playlists, etc.)
    "main":         ("blue",     +5),   # accent/main brand color (green default)
    "sidebar":      ("base",      0),   # sidebar background
    "player":       ("mantle",    0),   # now-playing bar background
    "card":         ("surface1",  0),   # card/panel backgrounds
    "shadow":       ("crust",     0),   # shadow color
    "selected-row": ("blue",     -15),   # selected row highlight
    "button":       ("mauve",     0),   # button/accent color
    "button-active":("green",    +5),   # active button state
    "tab-active":   ("blue",      0),   # active tab indicator
    "notification": ("red",      -10),   # notification accent
}

lines = ["[Marketplace]"]
for key, (mat_key, delta) in base_colors.items():
    hex_val = mat.get(mat_key)
    if not isinstance(hex_val, str):
        continue
    h = hex_val.lstrip("#")
    if len(h) != 6:
        continue
    lines.append("{}               = {}".format(key, adjust(h, delta)))

with open(os.path.join(theme_dir, "color.ini"), "w") as f:
    f.write("\n".join(lines) + "\n")

# Also update color_scheme in config-xpui.ini for CSS variable access
cfg_path = os.path.join(os.path.dirname(theme_dir), "config-xpui.ini")
if os.path.isfile(cfg_path):
    import configparser
    cfg = configparser.ConfigParser()
    cfg.read(cfg_path)
    
    # Set color_scheme to our custom colors
    scheme_colors = {}
    for key, (mat_key, delta) in base_colors.items():
        hex_val = mat.get(mat_key)
        if isinstance(hex_val, str):
            h = hex_val.lstrip("#")
            if len(h) == 6:
                scheme_colors[key] = adjust(h, delta)
    
    # Write as color_scheme section
    cfg["color_scheme"] = {k: v for k, v in scheme_colors.items()}
    with open(cfg_path, "w") as f:
        cfg.write(f)

PY

# Reapply spicetify to pick up new colors
if command -v "$HOME/.spicetify/spicetify" &> /dev/null; then
    PATH="$HOME/.spicetify:$PATH" spicetify apply --quiet 2>/dev/null || true
fi
