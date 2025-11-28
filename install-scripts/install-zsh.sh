#!/bin/bash
set -euo pipefail

# Install zsh if missing
if ! command -v zsh >/dev/null 2>&1; then
  sudo pacman -Sy --needed --noconfirm zsh
else
  echo "zsh already installed, skipping package install."
fi

# Install Oh My Zsh only if not present
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "Oh My Zsh already installed, skipping."
fi

# Install fzf if missing
if ! command -v fzf >/dev/null 2>&1; then
  sudo pacman -Sy --needed --noconfirm fzf
else
  echo "fzf already installed, skipping."
fi
