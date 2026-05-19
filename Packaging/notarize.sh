#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-dist/VoxForge.app}"
DMG_PATH="${2:-dist/VoxForge.dmg}"
BUNDLE_ID="com.voxforge.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "missing app bundle: $APP_PATH" >&2
  exit 2
fi

mkdir -p dist
hdiutil create -volname VoxForge -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl -a -vv "$APP_PATH" || true

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "Set NOTARY_PROFILE to an xcrun notarytool keychain profile before submitting." >&2
  exit 0
fi

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
echo "notarized: $DMG_PATH"
