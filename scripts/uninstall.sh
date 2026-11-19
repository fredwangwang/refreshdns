#!/usr/bin/env bash
set -euo pipefail

SERVICE_TARGET="system/me.wanghuan.refreshdns.helper"
PLIST_PATH="/Library/LaunchDaemons/me.wanghuan.refreshdns.helper.plist"
HELPER_PATH="/Library/PrivilegedHelperTools/me.wanghuan.refreshdns.helper"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "$SCRIPT_DIR" == *.app/Contents/Resources ]]; then
    APP_PATH="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
    APP_PATH="/Applications/RefreshDNS.app"
fi

echo "==> Uninstalling RefreshDNS privileged helper and app..."
if /bin/launchctl print "$SERVICE_TARGET" >/dev/null 2>&1; then
    sudo /bin/launchctl bootout "$SERVICE_TARGET" || true
fi

if [[ -e "$PLIST_PATH" || -e "$HELPER_PATH" ]]; then
    sudo rm -f "$PLIST_PATH" "$HELPER_PATH"
fi

if [[ -d "$APP_PATH" ]]; then
    echo "==> Removing $APP_PATH..."
    rm -rf "$APP_PATH" 2>/dev/null || sudo rm -rf "$APP_PATH"
fi

echo "==> Uninstall complete."
