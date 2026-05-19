#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT_DIR/.build/sherpa-onnx-src"
BUILD_DIR="$ROOT_DIR/.build/sherpa-onnx-build"
RUNTIME_DIR="$ROOT_DIR/Vendor/SherpaRuntime"

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required to build sherpa-onnx runtime. Install it first, for example: brew install cmake" >&2
  exit 1
fi

if [[ ! -d "$SRC_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/k2-fsa/sherpa-onnx.git "$SRC_DIR"
fi

cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DBUILD_SHARED_LIBS=ON \
  -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
  -DSHERPA_ONNX_ENABLE_TESTS=OFF \
  -DSHERPA_ONNX_ENABLE_CHECK=OFF \
  -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
  -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF

cmake --build "$BUILD_DIR" --config Release --parallel

mkdir -p "$RUNTIME_DIR"
find "$BUILD_DIR" -name "*.dylib" -exec cp {} "$RUNTIME_DIR/" \;

for dylib in "$RUNTIME_DIR"/*.dylib; do
  install_name_tool -add_rpath "@loader_path" "$dylib" >/dev/null 2>&1 || true
done

echo "Sherpa runtime libraries copied to $RUNTIME_DIR"
