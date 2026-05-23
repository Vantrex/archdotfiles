#!/usr/bin/env bash
# Show spicetify adaptive status icon for waybar.
# Output format: {"text":"icon","class":"on"|"off"}

SETTINGS="$HOME/.config/waybar/waybar-settings.json"

if [[ ! -f "$SETTINGS" ]]; then
    echo '{"text":"󰏗","class":"off"}'
    exit 0
fi

state=$(python3 -c "import json; print(json.load(open('$SETTINGS')).get('spicetifyAdaptive', True))")

if [[ "$state" == "True" ]]; then
    echo '{"text":"󰏖","class":"on"}'
else
    echo '{"text":"󰏗","class":"off"}'
fi
