#!/bin/bash
set -euo pipefail

# Install Firefox
sudo pacman -Sy --needed --noconfirm firefox

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Find the active Firefox profile directory
PROFILE_INI="$HOME/.mozilla/firefox/profiles.ini"
if [ ! -f "$PROFILE_INI" ]; then
  echo "No profiles.ini found, skipping Firefox config deploy."
  exit 0
fi

# Extract the default profile path from profiles.ini
PROFILE_DIR=$(grep -A1 '\[Profile0\]' "$PROFILE_INI" | grep 'Path=' | cut -d'/' -f3)
if [ -z "$PROFILE_DIR" ]; then
  echo "Could not find default profile, skipping."
  exit 0
fi

FIREFOX_PROFILE="$HOME/.mozilla/firefox/$PROFILE_DIR"

# Deploy userChrome.css
mkdir -p "$FIREFOX_PROFILE/chrome"
cp "$REPO_ROOT/firefox/chrome/userChrome.css" "$FIREFOX_PROFILE/chrome/"

# Deploy user.js
cp "$REPO_ROOT/firefox/user.js" "$FIREFOX_PROFILE/"

echo "Firefox config deployed to $FIREFOX_PROFILE"
