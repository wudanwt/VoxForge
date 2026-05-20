#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="VoxForge"
APP_DISPLAY_NAME="VoxForge 声铸"
BUILD_PRODUCT_NAME="TypeMore"
BUNDLE_ID="com.voxforge.app"
APP_VERSION="1.0.1"
APP_BUILD="2"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SHERPA_RUNTIME_DIR="$ROOT_DIR/Vendor/SherpaRuntime"
APP_ICON="$ROOT_DIR/Assets/VoxForge.icns"
APP_ICON_FILE="VoxForge.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "$BUILD_PRODUCT_NAME" >/dev/null 2>&1 || true

swift build
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$BUILD_PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

find "$BUILD_DIR" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP_RESOURCES/" \;

if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP_RESOURCES/$APP_ICON_FILE"
fi

if [[ -d "$SHERPA_RUNTIME_DIR" ]]; then
  find "$SHERPA_RUNTIME_DIR" -maxdepth 1 -name "*.dylib" -exec cp {} "$APP_FRAMEWORKS/" \;
  for dylib in "$APP_FRAMEWORKS"/*.dylib; do
    install_name_tool -add_rpath "@loader_path" "$dylib" >/dev/null 2>&1 || true
  done
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_FILE</string>
  <key>CFBundleIconName</key>
  <string>VoxForge</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>VoxForge 声铸会在本机录制你的语音，用于转写并输入到当前应用。</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>VoxForge 声铸可能需要自动化权限来配合当前应用完成输入。</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  if compgen -G "$APP_FRAMEWORKS/*.dylib" >/dev/null; then
    for dylib in "$APP_FRAMEWORKS"/*.dylib; do
      codesign --force --sign - "$dylib"
    done
  fi
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BINARY"
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --package|package)
    echo "packaged: $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
