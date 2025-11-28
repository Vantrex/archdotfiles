#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$REPO_ROOT/install-scripts"

# Ensure yay is available first
bash "$SCRIPT_DIR/install-yay.sh"

# Install Hyprland core stack early (before the rest)
bash "$SCRIPT_DIR/install-hyprland.sh"

# Run every installer script (yay already handled above)
for script in "$SCRIPT_DIR"/install-*.sh; do
  [ -f "$script" ] || continue
  case "$(basename "$script")" in
    install-yay.sh|install-hyprland.sh)
      # Already handled these above.
      continue
      ;;
  esac
  echo "Running $(basename "$script")"
  bash "$script"
done
