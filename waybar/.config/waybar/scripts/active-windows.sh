#!/usr/bin/env bash
# Emit icons for windows in the active workspace of a specific monitor.
# Usage: active-windows.sh <monitor-name>   (e.g. DP-2, DP-3, HDMI-A-2)
# If no arg given, falls back to the focused monitor.
# Output is Pango markup suitable for a custom module with format "{}".

set -euo pipefail

MONITOR="${1:-}"

# Resolve the active theme's wb-comment colour so the leading separator
# matches the static custom/sep module exactly.
ACTIVE_CSS=$(readlink -f "$HOME/.config/waybar/themes/active.css" 2>/dev/null || true)
SEP_HEX=$(grep -oE '@define-color\s+wb-comment\s+#[0-9a-fA-F]{6}' "$ACTIVE_CSS" 2>/dev/null \
          | head -1 | grep -oE '#[0-9a-fA-F]{6}')
SEP_HEX="${SEP_HEX:-#565f89}"

python3 - "$MONITOR" "$SEP_HEX" <<'PY'
import json, subprocess, re, sys

def hctl(args):
    try:
        out = subprocess.check_output(["hyprctl", "-j", *args], text=True)
        return json.loads(out)
    except Exception:
        return None

target_monitor = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
sep_hex        = (sys.argv[2] if len(sys.argv) > 2 else "#565f89").strip()

monitors = hctl(["monitors"]) or []
active_ws_id = None
if target_monitor:
    for m in monitors:
        if m.get("name") == target_monitor:
            active_ws_id = m.get("activeWorkspace", {}).get("id")
            break
else:
    for m in monitors:
        if m.get("focused"):
            active_ws_id = m.get("activeWorkspace", {}).get("id")
            break

if active_ws_id is None:
    print("")
    raise SystemExit

clients = hctl(["clients"]) or []
windows = [c for c in clients if c.get("workspace", {}).get("id") == active_ws_id]

# Class -> icon glyph (Nerd Font codepoints).
# All glyphs are written as \u / \U escapes so the source file stays
# pure ASCII — any tool that strips non-ASCII can't break the icons.
ICONS = [
    # JetBrains family — specific patterns must come before the catch-all
    (r"^jetbrains-pycharm(-ce)?$",                         ""),       # python
    (r"^jetbrains-webstorm$",                              ""),       # javascript
    (r"^jetbrains-phpstorm$",                              ""),       # php
    (r"^jetbrains-goland$",                                ""),       # go
    (r"^jetbrains-rubymine$",                              ""),       # ruby
    (r"^jetbrains-clion$",                                 "\U000f0671"),   # cpp
    (r"^jetbrains-rider$",                                 "\U000f031b"),   # csharp
    (r"^jetbrains-datagrip$",                              "\U000f01bc"),   # database
    (r"^jetbrains-idea(-ce)?$",                            ""),       # jetbrains
    (r"^jetbrains-",                                       ""),       # any other JB app
    (r"^(Android ?Studio|android-studio)$",                ""),       # android

    # Browsers
    (r"^(firefox|librewolf|chromium|google-chrome|brave)", ""),
    # Terminals
    (r"(kitty|com\.mitchellh\.ghostty|alacritty|wezterm)", ""),
    # Editors / chat / etc.
    (r"^(code|code-oss|VSCodium)$",                        "\U000f089e"),
    (r"^(spotify|Spotify)$",                               ""),
    (r"^(discord|WebCord|Vesktop)$",                       "\U000f08af"),
    (r"^obsidian$",                                        ""),
    (r"[Tt]hunderbird",                                    "\U000f01ee"),
    (r"^(dolphin|nautilus|thunar|nemo)$",                  ""),
    (r"[Tt]elegram",                                       ""),
    (r"[Ss]team",                                          "\U000f04d3"),
]
DEFAULT_ICON = ""  # generic globe

def icon_for(cls):
    for pat, ic in ICONS:
        if re.search(pat, cls or ""):
            return ic
    return DEFAULT_ICON

# Sort by client `at` x-coordinate so icons match window order on screen
windows.sort(key=lambda w: (w.get("at", [0, 0]) or [0, 0])[0])

icons = " ".join(icon_for(w.get("class", "")) for w in windows)
if icons:
    print(f'<span foreground="{sep_hex}">│</span>  {icons}')
else:
    print("")
PY
