#!/usr/bin/env bash
# Read waybar-settings.json and regenerate cache CSS files:
#   - transparency.css       window#waybar bg with alpha baked in
#   - module-visibility.css  hides modules user has disabled
#   - adaptive-colors.css    empty stub (populated by wallpaper-adapt.sh when enabled)
# Touches style.css at the end so waybar's reload_style_on_change picks it up.

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
SETTINGS="$CONFIG_DIR/waybar-settings.json"

mkdir -p "$CACHE_DIR"

if [[ ! -f "$SETTINGS" ]]; then
    echo "settings-apply: $SETTINGS missing, nothing to apply" >&2
    exit 0
fi

# Read settings via python3 (jq is not installed). Outputs three lines:
#   1: transparency value
#   2: rainbowBorder bool ("true"/"false")
#   3: wallpaperAdaptive bool
#   4..: <module-key> <true|false> for each module
read_settings() {
    python3 - "$SETTINGS" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    s = json.load(f)
print(s.get("transparency", 0.85))
print(str(s.get("features", {}).get("rainbowBorder", False)).lower())
print(str(s.get("wallpaperAdaptive", False)).lower())
for k, v in (s.get("modules") or {}).items():
    print(f"{k} {str(v).lower()}")
PY
}

mapfile -t LINES < <(read_settings)
ALPHA="${LINES[0]}"
RAINBOW="${LINES[1]}"
ADAPTIVE="${LINES[2]}"

# --- transparency.css -------------------------------------------------------
# Resolve the active variant's --wb-bg hex and emit rgba() directly. Some
# GTK3 builds don't honor alpha(@named, factor) reliably across @import.
ACTIVE_CSS=$(readlink -f "$CONFIG_DIR/themes/active.css" 2>/dev/null || echo "")
BG_HEX=$(grep -oE '@define-color\s+wb-bg\s+#[0-9a-fA-F]{6}' "$ACTIVE_CSS" 2>/dev/null \
         | head -1 | grep -oE '#[0-9a-fA-F]{6}' | tr 'A-F' 'a-f' || echo "")
RGB=$(python3 - "$BG_HEX" "$ALPHA" <<'PY' 2>/dev/null || echo "0,0,0,0.85"
import sys
h = (sys.argv[1] or "#1a1b26").lstrip("#")
a = float(sys.argv[2] or "0.85")
r, g, b = (int(h[i:i+2], 16) for i in (0, 2, 4))
print(f"{r},{g},{b},{a}")
PY
)
IFS=',' read -r R G B A <<<"$RGB"
cat >"$CACHE_DIR/transparency.css" <<EOF
window#waybar {
    background-color: rgba($R, $G, $B, $A);
}
EOF

# --- module-visibility.css --------------------------------------------------
declare -A MODULE_SEL=(
    [workspaces]="#workspaces"
    [window]="#window"
    [mpris]="#mpris"
    [privacy]="#privacy"
    [network]="#network"
    [pulseaudio]="#pulseaudio"
    [cpu]="#cpu"
    [memory]="#memory"
    [clock]="#clock"
    [battery]="#battery"
    [backlight]="#backlight"
    [notifications]="#custom-notification"
    [tray]="#tray"
    [networkSpeed]="#custom-network-speed"
    [hyprlandMode]="#custom-hyprland-mode"
)

VIS_FILE="$CACHE_DIR/module-visibility.css"
: >"$VIS_FILE"

# Lines 3+ are module entries
for line in "${LINES[@]:3}"; do
    key="${line% *}"
    val="${line#* }"
    sel="${MODULE_SEL[$key]:-}"
    if [[ -n "$sel" && "$val" == "false" ]]; then
        echo "$sel { opacity: 0; min-width: 0px; padding: 0px; margin: 0px; }" >>"$VIS_FILE"
    fi
done

if [[ "$RAINBOW" == "true" ]]; then
    cat >>"$VIS_FILE" <<'EOF'
#workspaces button.active {
    animation: rainbow-color 4s linear infinite;
}
#workspaces button.active label {
    animation: rainbow-color 4s linear infinite;
}
EOF
fi

# --- adaptive-colors.css ----------------------------------------------------
if [[ "$ADAPTIVE" == "true" && -x "$CONFIG_DIR/scripts/wallpaper-adapt.sh" ]]; then
    "$CONFIG_DIR/scripts/wallpaper-adapt.sh" || true
else
    : >"$CACHE_DIR/adaptive-colors.css"
fi
[[ -f "$CACHE_DIR/adaptive-colors.css" ]] || : >"$CACHE_DIR/adaptive-colors.css"

# --- trigger waybar reload --------------------------------------------------
# Full reload (re-reads config.jsonc + CSS). reload_style_on_change is unreliable
# across symlinked paths, so signal directly.
touch "$CONFIG_DIR/style.css" 2>/dev/null || true
if pgrep -x waybar >/dev/null; then
    pkill -SIGUSR2 -x waybar
fi
