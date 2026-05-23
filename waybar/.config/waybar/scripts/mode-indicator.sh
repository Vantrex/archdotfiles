#!/usr/bin/env bash
# Output the current Hyprland submap as plain text for waybar custom module.
# Empty submap (default) prints nothing so the module hides itself via `format`.

set -euo pipefail

submap=$(hyprctl activeworkspace -j 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
print(d.get("submap", "") or "")
' 2>/dev/null)

# activeworkspace doesn't carry submap on all versions; fall back to listing
if [[ -z "$submap" || "$submap" == "null" ]]; then
    submap=$(hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for m in d:
    if m.get("focused"):
        print(m.get("activeWorkspace", {}).get("submap", ""))
        break
' 2>/dev/null || echo "")
fi

# Final fallback: dispatcher submap query
if [[ -z "$submap" || "$submap" == "null" ]]; then
    submap=$(hyprctl dispatch submap 2>/dev/null | grep -oP "(?<=submap '?)[^'\"]*" | head -1 || true)
fi

if [[ -n "$submap" && "$submap" != "default" ]]; then
    printf '{"text":"%s","class":"active","alt":"%s","tooltip":"Hyprland submap: %s"}\n' "$submap" "$submap" "$submap"
else
    printf '{"text":"","class":"empty","alt":"","tooltip":""}\n'
fi
