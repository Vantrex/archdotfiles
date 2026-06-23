#!/bin/bash
set -euo pipefail

FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

install_font() {
  local name="$1" url="$2" dest="$3"
  echo "Installing $name..."

  local file="$TMPDIR_WORK/$name"
  curl -fsSL -o "$file" "$url"

  local extracted="$TMPDIR_WORK/$name-extracted"
  mkdir -p "$extracted"

  # Handle archive formats; direct .ttf/.otf fall through with no extraction
  case "$file" in
    *.zip)     unzip -q "$file" -d "$extracted" ;;
    *.tar.gz)  tar xzf "$file" -C "$extracted" ;;
    *.tgz)     tar xzf "$file" -C "$extracted" ;;
    *.tar.xz)  tar xJf "$file" -C "$extracted" ;;
    *.tar.bz2) tar xjf "$file" -C "$extracted" ;;
  esac

  mkdir -p "$FONT_DIR/$dest"

  find "$extracted" -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) \
    -exec cp {} "$FONT_DIR/$dest/" \;

  echo "  -> $FONT_DIR/$dest/"
}

# JetBrains Mono — resolve latest version from GitHub API, then download release zip
if command -v jq >/dev/null 2>&1; then
  JETBRAINS_VERSION="$(curl -fsSL https://api.github.com/repos/JetBrains/JetBrainsMono/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
else
  JETBRAINS_VERSION="$(curl -fsSL https://api.github.com/repos/JetBrains/JetBrainsMono/releases/latest | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')"
fi
install_font "JetBrainsMono" \
  "https://github.com/JetBrains/JetBrainsMono/releases/download/v${JETBRAINS_VERSION}/JetBrainsMono-${JETBRAINS_VERSION}.zip" \
  "JetBrainsMono"

# Maple Mono Nerd Font variant
install_font "MapleMono-NF" \
  "https://github.com/subframe7536/maple-font/releases/latest/download/MapleMono-NF.zip" \
  "MapleMono"

# Mononoki Nerd Font
install_font "MononokiNerd" \
  "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Mononoki.tar.xz" \
  "MononokiNerd"

# Material Design Icons — direct .ttf (no archive)
echo "Installing MaterialDesign..."
mkdir -p "$FONT_DIR/MaterialDesign"
curl -fsSL -o "$FONT_DIR/MaterialDesign/materialdesignicons-webfont.ttf" \
  "https://raw.githubusercontent.com/Templarian/MaterialDesign-Webfont/master/fonts/materialdesignicons-webfont.ttf"
echo "  -> $FONT_DIR/MaterialDesign/"

# Noto Sans CJK (tagged release — no /latest/ endpoint)
install_font "NotoSansCJK" \
  "https://github.com/googlefonts/noto-cjk/releases/download/Sans2.004/00_NotoSansCJK.ttc.zip" \
  "NotoSansCJK"

# Cascadia Code Nerd Font (includes Caskaydia Cove variants)
install_font "CascadiaCode" \
  "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.tar.xz" \
  "CascadiaCode"

fc-cache -f "$FONT_DIR"
echo "All fonts installed."
