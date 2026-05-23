#!/usr/bin/env bash
# Set the active waybar theme to <family> <variant>.
# Updates waybar-settings.json, repoints themes/active.css symlink,
# and re-applies settings (which touches style.css for hot-reload).

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: theme-set.sh <family> <variant>" >&2
    exit 2
fi

FAMILY="$1"
VARIANT="$2"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
SETTINGS="$CONFIG_DIR/waybar-settings.json"
THEME_FILE="$CONFIG_DIR/themes/$FAMILY/$VARIANT.css"
ACTIVE_LINK="$CONFIG_DIR/themes/active.css"

if [[ ! -f "$THEME_FILE" ]]; then
    echo "theme-set: $THEME_FILE does not exist" >&2
    exit 1
fi

# Update settings.json (preserve all other keys)
python3 - "$SETTINGS" "$FAMILY" "$VARIANT" <<'PY'
import json, sys
path, family, variant = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    s = json.load(f)
s["themeFamily"] = family
s["themeVariant"] = variant
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
PY

# Repoint active.css symlink (atomic: ln -sfT to a relative target)
ln -sfT "$FAMILY/$VARIANT.css" "$ACTIVE_LINK"

# Apply (regenerates cache files based on new state and triggers reload)
"$CONFIG_DIR/scripts/settings-apply.sh"
