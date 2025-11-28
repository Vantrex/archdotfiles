#!/bin/bash
set -euo pipefail

if command -v yay >/dev/null 2>&1; then
  echo "yay is already installed."
  exit 0
fi

sudo pacman -Sy --needed --noconfirm base-devel git

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

git clone https://aur.archlinux.org/yay.git "$TMP_DIR/yay"
cd "$TMP_DIR/yay"
makepkg -si --noconfirm
