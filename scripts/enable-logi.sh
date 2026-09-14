#!/usr/bin/env bash
set -e

echo "==> Loading Logi Options+ LaunchAgent..."
launchctl bootstrap "gui/$(id -u)" /Library/LaunchAgents/com.logi.optionsplus.plist 2>/dev/null || \
launchctl load /Library/LaunchAgents/com.logi.optionsplus.plist 2>/dev/null || true

echo "==> Logi Options+ re-enabled."

