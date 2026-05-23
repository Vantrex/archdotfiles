#!/usr/bin/env bash
# Cycle to the next dark variant in the active theme family.
# Light variants are reachable only through the quickshell config panel.

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
SETTINGS="$CONFIG_DIR/waybar-settings.json"

read -r FAMILY NEXT_VARIANT < <(python3 - "$SETTINGS" "$CONFIG_DIR/themes" <<'PY'
import json, sys
from pathlib import Path

settings_path, themes_dir = sys.argv[1], Path(sys.argv[2])
with open(settings_path) as f:
    s = json.load(f)

family = s.get("themeFamily", "tokyo-night")
current = s.get("themeVariant", "")

manifest_path = themes_dir / family / "family.json"
with open(manifest_path) as f:
    manifest = json.load(f)

dark_variants = [v["id"] for v in manifest["variants"] if v.get("mode") == "dark"]
if not dark_variants:
    print(f"{family} {current}")
    sys.exit(0)

if current in dark_variants:
    idx = (dark_variants.index(current) + 1) % len(dark_variants)
else:
    idx = 0

print(f"{family} {dark_variants[idx]}")
PY
)

exec "$CONFIG_DIR/scripts/theme-set.sh" "$FAMILY" "$NEXT_VARIANT"
