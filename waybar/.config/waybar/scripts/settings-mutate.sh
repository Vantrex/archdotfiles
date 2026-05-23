#!/usr/bin/env bash
# Mutate a single key in waybar-settings.json by dotted path, then re-apply.
# Usage:  settings-mutate.sh <dotted.key> <json-value>
# Examples:
#   settings-mutate.sh transparency 0.75
#   settings-mutate.sh modules.cpu false
#   settings-mutate.sh themeFamily '"tokyo-night"'
#   settings-mutate.sh features.rainbowBorder true

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: settings-mutate.sh <dotted.key> <json-value>" >&2
    exit 2
fi

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
SETTINGS="$CONFIG_DIR/waybar-settings.json"

python3 - "$SETTINGS" "$1" "$2" <<'PY'
import json, sys
path, dotted, raw = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    value = json.loads(raw)
except json.JSONDecodeError:
    # Allow bare strings without quotes (convenience)
    value = raw
with open(path) as f:
    s = json.load(f)
keys = dotted.split(".")
node = s
for k in keys[:-1]:
    if k not in node or not isinstance(node[k], dict):
        node[k] = {}
    node = node[k]
node[keys[-1]] = value
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
PY

"$CONFIG_DIR/scripts/settings-apply.sh"
