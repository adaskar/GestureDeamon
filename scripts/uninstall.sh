#!/usr/bin/env bash
set -e

TARGET="GestureDaemon"
INSTALL_BIN="/usr/local/bin/${TARGET}"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
AGENT_PLIST="${LAUNCH_AGENT_DIR}/com.user.gesturedaemon.plist"

echo "==> Unloading LaunchAgent..."
launchctl unload "${AGENT_PLIST}" 2>/dev/null || true
rm -f "${AGENT_PLIST}"

echo "==> Removing binary from ${INSTALL_BIN} (may prompt for sudo password)..."
sudo rm -f "${INSTALL_BIN}"

echo "==> Binary removed. Configuration preserved at ~/.config/GestureDaemon"

