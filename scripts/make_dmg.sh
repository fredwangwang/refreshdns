#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/RefreshDNS.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
    "$ROOT_DIR/scripts/build.sh"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
DMG_NAME="RefreshDNS-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
STAGING_DIR="$BUILD_DIR/dmg-staging"

echo "==> Packaging $DMG_NAME..."
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/RefreshDNS.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "RefreshDNS" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "==> Created DMG: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
