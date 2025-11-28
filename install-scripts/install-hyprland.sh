#!/bin/bash
set -euo pipefail

# Core Hyprland stack (without hyprpm)
sudo pacman -Sy --needed --noconfirm \
  hyprland \
  xorg-xwayland \
  xdg-desktop-portal-hyprland \
  wl-clipboard \
  qt5-wayland \
  qt6-wayland \
  polkit-gnome
