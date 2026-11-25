#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/RefreshDNS.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPER_DIR="$CONTENTS_DIR/Library/HelperTools"
DAEMONS_DIR="$CONTENTS_DIR/Library/LaunchDaemons"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
TMP_BIN_DIR="$BUILD_DIR/tmp-arch"

UNIVERSAL="${UNIVERSAL:-1}"
MIN_MACOS="13.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

compile_universal() {
    local output_path="$1"
    shift
    if [[ "$UNIVERSAL" == "1" ]]; then
        local base_name
        base_name="$(basename "$output_path")"
        swiftc -O -target "arm64-apple-macosx${MIN_MACOS}" "$@" -o "$TMP_BIN_DIR/${base_name}.arm64"
        swiftc -O -target "x86_64-apple-macosx${MIN_MACOS}" "$@" -o "$TMP_BIN_DIR/${base_name}.x86_64"
        lipo -create -output "$output_path" \
            "$TMP_BIN_DIR/${base_name}.arm64" \
            "$TMP_BIN_DIR/${base_name}.x86_64"
    else
        local arch
        arch="$(uname -m)"
        swiftc -O -target "${arch}-apple-macosx${MIN_MACOS}" "$@" -o "$output_path"
    fi
}

echo "==> Cleaning previous build..."
rm -rf "$APP_BUNDLE" "$ICONSET_DIR" "$TMP_BIN_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HELPER_DIR" "$DAEMONS_DIR" "$TMP_BIN_DIR"

echo "==> Compiling privileged helper (me.wanghuan.refreshdns.helper)..."
compile_universal "$HELPER_DIR/me.wanghuan.refreshdns.helper" \
    -framework Foundation \
    "$ROOT_DIR/Sources/Shared/RefreshDNSProtocol.swift" \
    "$ROOT_DIR/Sources/Helper/main.swift"

echo "==> Compiling wake listener agent (me.wanghuan.refreshdns.wakeagent)..."
compile_universal "$HELPER_DIR/me.wanghuan.refreshdns.wakeagent" \
    -framework Foundation \
    -framework IOKit \
    "$ROOT_DIR/Sources/Shared/RefreshDNSProtocol.swift" \
    "$ROOT_DIR/Sources/WakeAgent/main.swift"

echo "==> Compiling RefreshDNS app..."
compile_universal "$MACOS_DIR/RefreshDNS" \
    -framework Foundation \
    -framework AppKit \
    -framework QuartzCore \
    "$ROOT_DIR/Sources/Shared/RefreshDNSProtocol.swift" \
    "$ROOT_DIR/Sources/App/Localization.swift" \
    "$ROOT_DIR/Sources/App/HelperClient.swift" \
    "$ROOT_DIR/Sources/App/WakeAgentManager.swift" \
    "$ROOT_DIR/Sources/App/HUDWindow.swift" \
    "$ROOT_DIR/Sources/App/OptionsWindow.swift" \
    "$ROOT_DIR/Sources/App/main.swift"

rm -rf "$TMP_BIN_DIR"

echo "==> Copying plists, localizations, and uninstall script..."
cp "$ROOT_DIR/Resources/App-Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/me.wanghuan.refreshdns.helper.plist" "$DAEMONS_DIR/me.wanghuan.refreshdns.helper.plist"
cp "$ROOT_DIR/scripts/uninstall.sh" "$RESOURCES_DIR/uninstall.sh"
chmod 755 "$RESOURCES_DIR/uninstall.sh"
for lproj in "$ROOT_DIR"/Resources/*.lproj; do
    plutil -lint "$lproj/Localizable.strings" >/dev/null
    cp -R "$lproj" "$RESOURCES_DIR/"
done

echo "==> Generating AppIcon.icns..."
swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

echo "==> Signing helpers and app bundle (identity: $SIGN_IDENTITY)..."
codesign --force --sign "$SIGN_IDENTITY" "$HELPER_DIR/me.wanghuan.refreshdns.helper"
codesign --force --sign "$SIGN_IDENTITY" "$HELPER_DIR/me.wanghuan.refreshdns.wakeagent"
codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo "==> Built successfully: $APP_BUNDLE"
