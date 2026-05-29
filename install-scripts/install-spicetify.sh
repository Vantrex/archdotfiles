#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Install Spicetify if missing
if ! command -v spicetify >/dev/null 2>&1; then
  yay -S --needed --noconfirm spicetify-cli
else
  echo "Spicetify already installed, skipping package install."
fi

# Copy config from repo to ~/.config/spicetify/
SPICE_DIR="$HOME/.config/spicetify"
REPO_CONFIG="$REPO_ROOT/.config/spicetify"

# Preserve existing config-xpui.ini (Spicetify writes version info here)
if [ -f "$SPICE_DIR/config-xpui.ini" ]; then
  echo "Spicetify config already exists, copying themes/extensions/apps on top."
else
  cp "$REPO_CONFIG/config-xpui.ini" "$SPICE_DIR/"
fi

# Copy themes, extensions, custom apps, and scripts
cp -r "$REPO_CONFIG/Themes/"* "$SPICE_DIR/Themes/" 2>/dev/null || true
cp -r "$REPO_CONFIG/Extensions/"* "$SPICE_DIR/Extensions/" 2>/dev/null || true
cp -r "$REPO_CONFIG/CustomApps/"* "$SPICE_DIR/CustomApps/" 2>/dev/null || true
cp -r "$REPO_CONFIG/scripts/"* "$SPICE_DIR/scripts/" 2>/dev/null || true

# Apply Spicetify config
spicetify apply
