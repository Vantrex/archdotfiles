#!/bin/bash

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/.mc_attack_toggle"

# ydotoold daemon: you started it with --socket-path="$HOME/.ydotool_socket"
export YDOTOOL_SOCKET="$HOME/.ydotool_socket"

# Linux input keycode for KEY_F6 is 64 (see input-event-codes.h). :contentReference[oaicite:0]{index=0}
KEYCODE=64   # F6

if [[ -f "$STATE_FILE" ]]; then
  # Currently ON -> release the key
  ydotool key ${KEYCODE}:0     # key up
  rm -f "$STATE_FILE"
else
  # Currently OFF -> press and hold the key
  ydotool key ${KEYCODE}:1     # key down (no release here!)
  touch "$STATE_FILE"
fi

