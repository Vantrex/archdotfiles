#!/bin/bash
dir="$HOME/Pictures/screenshots"

file="$dir/$(date +%s.png)"

grim -g "$(slurp)" - | tee "$file" | wl-copy --type image/png
