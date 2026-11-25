#!/usr/bin/env bash
set -euo pipefail

SERVICE_TARGET="system/me.wanghuan.refreshdns.helper"
PLIST_PATH="/Library/LaunchDaemons/me.wanghuan.refreshdns.helper.plist"
HELPER_PATH="/Library/PrivilegedHelperTools/me.wanghuan.refreshdns.helper"

WAKE_AGENT_TARGET="gui/$(id -u)/me.wanghuan.refreshdns.wakeagent"
WAKE_AGENT_PLIST="$HOME/Library/LaunchAgents/me.wanghuan.refreshdns.wakeagent.plist"
PREFS_PLIST="$HOME/Library/Preferences/me.wanghuan.refreshdns.plist"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "$SCRIPT_DIR" == *.app/Contents/Resources ]]; then
    APP_PATH="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
    APP_PATH="/Applications/RefreshDNS.app"
fi

echo "==> Uninstalling RefreshDNS wake agent, privileged helper, and app..."
if /bin/launchctl print "$WAKE_AGENT_TARGET" >/dev/null 2>&1; then
    /bin/launchctl bootout "$WAKE_AGENT_TARGET" || true
fi

if [[ -e "$WAKE_AGENT_PLIST" || -e "$PREFS_PLIST" ]]; then
    rm -f "$WAKE_AGENT_PLIST" "$PREFS_PLIST"
fi

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
