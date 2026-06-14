#!/usr/bin/env bash

# Apply Hyprland border colors from Nord + matugen blend
if [[ -x "$HOME/.config/hypr/scripts/apply-border-colors.sh" ]]; then
    "$HOME/.config/hypr/scripts/apply-border-colors.sh" 2>/dev/null || true
fi

# Reload Kitty instances
if command -v kitty &> /dev/null; then
    killall -USR1 .kitty-wrapped 2>/dev/null || true
fi

# Re-blend waybar adaptive palette (no-op when wallpaperAdaptive is disabled)
if [[ -x "$HOME/.config/waybar/scripts/wallpaper-adapt.sh" ]]; then
    "$HOME/.config/waybar/scripts/wallpaper-adapt.sh" 2>/dev/null || true
fi

# Re-generate spicetify marketplace colors from matugen (no-op when disabled)
if [[ -x "$HOME/.config/spicetify/scripts/wallpaper-colors.sh" ]]; then
    "$HOME/.config/spicetify/scripts/wallpaper-colors.sh" 2>/dev/null || true
fi

# Reload CAVA
if pgrep -x "cava" > /dev/null; then
    cat ~/.config/cava/config_base ~/.config/cava/colors > ~/.config/cava/config 2>/dev/null || true
    killall -USR1 cava 2>/dev/null || true
fi

# Reload SwayNC CSS styling dynamically without killing the daemon
if command -v swaync-client &> /dev/null; then
    swaync-client -rs 2>/dev/null || true
fi

# Restarting swayosd.service is currently the only way to reload its CSS.
if systemctl --user is-active --quiet swayosd.service 2>/dev/null; then
    systemctl --user restart swayosd.service &
fi

# GTK Live-Reload Hack
if command -v gsettings &> /dev/null; then
    current_gtk3=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo "''")
    current_scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo "'default'")

    if [[ "$current_gtk3" == "'Adwaita'" ]]; then
        gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
    else
        gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
        sleep 0.05
        gsettings set org.gnome.desktop.interface gtk-theme "$current_gtk3"
    fi

    if [[ "$current_scheme" == "'default'" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'default'
    else
        gsettings set org.gnome.desktop.interface color-scheme 'default'
        sleep 0.05
        gsettings set org.gnome.desktop.interface color-scheme "$current_scheme"
    fi
fi

wait
