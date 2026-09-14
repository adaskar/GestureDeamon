#!/usr/bin/env bash
set -e

echo "==> Unloading Logi Options+ LaunchAgent..."
launchctl bootout "gui/$(id -u)" /Library/LaunchAgents/com.logi.optionsplus.plist 2>/dev/null || \
launchctl unload /Library/LaunchAgents/com.logi.optionsplus.plist 2>/dev/null || true

echo "==> Terminating running Logi Options+ processes..."
killall "logioptionsplus_agent" "logioptionsplus_updater" "Logi Options+" 2>/dev/null || true

echo "==> Logi Options+ temporarily disabled."

