#!/bin/bash
set -euo pipefail

LLAMA_DIR="$HOME/work/llm/llama.cpp"
LLAMA_SERVER="$LLAMA_DIR/build/bin/llama-server"

if [[ -x "$LLAMA_SERVER" ]]; then
  echo "llama.cpp server already exists at $LLAMA_SERVER; leaving the existing build untouched."
  exit 0
fi

mkdir -p "$HOME/work/llm"

if [[ -e "$LLAMA_DIR" && ! -d "$LLAMA_DIR/.git" ]]; then
  echo "Refusing to overwrite non-Git path: $LLAMA_DIR" >&2
  exit 1
fi

if [[ ! -d "$LLAMA_DIR/.git" ]]; then
  git clone https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
fi

cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON
cmake --build "$LLAMA_DIR/build" --config Release -j"$(nproc)" --target llama-server

