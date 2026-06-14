#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing starship prompt..."

if command -v starship &>/dev/null; then
  echo "    starship is already installed, skipping."
else
  curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

echo "    starship install done."
