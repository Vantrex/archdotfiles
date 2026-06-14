#!/usr/bin/env bash
# Toggle spicetify adaptive colors on/off, re-apply if turning on.
# Reads/writes waybar-settings.json (same file as wallpaperAdaptive).

set -euo pipefail

SETTINGS="$HOME/.config/waybar/waybar-settings.json"
SCRIPT="$HOME/.config/spicetify/scripts/wallpaper-colors.sh"

if [[ ! -f "$SETTINGS" ]]; then
    echo "spicetify-adaptive-toggle: settings file not found" >&2
    exit 1
fi

# Read current value (default true)
current=$(python3 -c "import json; s=json.load(open('$SETTINGS')); print(s.get('spicetifyAdaptive', True))")

if [[ "$current" == "True" ]]; then
    python3 -c "
import json
with open('$SETTINGS') as f: s = json.load(f)
s['spicetifyAdaptive'] = False
with open('$SETTINGS', 'w') as f: json.dump(s, f, indent=2)
print('off')
"
    # Reset color.ini to empty when turning off
    echo "[Marketplace]" > "$HOME/.config/spicetify/Themes/marketplace/color.ini"
else
    python3 -c "
import json
with open('$SETTINGS') as f: s = json.load(f)
s['spicetifyAdaptive'] = True
with open('$SETTINGS', 'w') as f: json.dump(s, f, indent=2)
print('on')
"
    # Apply immediately when turning on
    if [[ -x "$SCRIPT" ]]; then
        "$SCRIPT" 2>/dev/null || true
    fi
fi
