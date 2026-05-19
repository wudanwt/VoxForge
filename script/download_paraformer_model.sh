#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME="sherpa-onnx-streaming-paraformer-bilingual-zh-en"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${MODEL_NAME}.tar.bz2"
MODEL_BASE="${HOME}/Library/Application Support/TypeMore/Models"
ARCHIVE_PATH="${MODEL_BASE}/${MODEL_NAME}.tar.bz2"

mkdir -p "$MODEL_BASE"

echo "Downloading ${MODEL_NAME}"
echo "Target: ${ARCHIVE_PATH}"
curl -L \
  --fail \
  --retry 8 \
  --retry-delay 3 \
  --connect-timeout 20 \
  --continue-at - \
  --output "$ARCHIVE_PATH" \
  "$MODEL_URL"

echo "Extracting to ${MODEL_BASE}"
tar -xjf "$ARCHIVE_PATH" -C "$MODEL_BASE"

echo "Done: ${MODEL_BASE}/${MODEL_NAME}"
