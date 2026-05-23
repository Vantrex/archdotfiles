# Screenshot Setup

This documents the screenshot toolchain used in this dotfiles setup (Hyprland on Wayland, Arch Linux).

## Tools

| Tool | Purpose |
|------|---------|
| `grim` | Wayland screenshot capture |
| `slurp` | Interactive region/output selection |
| `wl-clipboard` | Wayland clipboard (`wl-copy`) |
| `cliphist` | Clipboard history manager (stores screenshots too) |

## Installation

```bash
# Install screenshot tools
sudo pacman -S --needed --noconfirm grim slurp wl-clipboard

# Create screenshots directory
mkdir -p ~/Pictures/screenshots

# Install clipboard history manager
sudo pacman -S --needed --noconfirm cliphist
```

Or run the existing install scripts:

```bash
bash install-scripts/install-slurp-and-grim.sh
bash install-scripts/install-cliphist.sh
```

## Screenshot Script

**Location:** `scripts/.config/scripts/region-screenshot.sh`
**Deploy to:** `~/.config/scripts/region-screenshot.sh`

```bash
#!/bin/bash
dir="$HOME/Pictures/screenshots"

file="$dir/$(date +%s.png)"

grim -g "$(slurp)" - | tee "$file" | wl-copy --type image/png
```

What it does:
1. Opens an interactive crosshair with `slurp` to select a screen region
2. Captures the selection with `grim`
3. Saves it to `~/Pictures/screenshots/<unix-timestamp>.png`
4. Copies it to the clipboard so it can be pasted immediately

Make sure the script is executable:

```bash
chmod +x ~/.config/scripts/region-screenshot.sh
```

## Hyprland Keybinding

In `hyprland/.config/hypr/keybinds.conf`:

```
bind = , Insert, exec, sh -c '$HOME/.config/scripts/region-screenshot.sh'
```

**Key:** `Insert` (no modifier) triggers the region screenshot.

## Clipboard History (autostart)

In `hyprland/.config/hypr/autostart.conf`, `cliphist` is set up to track both text and images (including screenshots):

```
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
```

To browse clipboard history, the following keybind opens a rofi picker:

```
bind = SUPER, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy
```

**Key:** `Super + V`
