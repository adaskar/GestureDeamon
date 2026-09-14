#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="GestureDaemon"
INSTALL_BIN="/usr/local/bin/${TARGET}"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
AGENT_PLIST="${REPO_DIR}/scripts/com.user.gesturedaemon.plist"
CONFIG_DIR="${HOME}/.config/GestureDaemon"
CONFIG_FILE="${CONFIG_DIR}/config.plist"

cd "${REPO_DIR}"

if [ ! -f "${REPO_DIR}/build/${TARGET}" ]; then
    echo "==> Binary not found in build directory. Building first..."
    make build
fi

echo "==> Installing binary to ${INSTALL_BIN} (may prompt for sudo password)..."
sudo install -m 755 "${REPO_DIR}/build/${TARGET}" "${INSTALL_BIN}"

mkdir -p "${CONFIG_DIR}"
if [ ! -f "${CONFIG_FILE}" ]; then
    cp "${REPO_DIR}/GestureDaemon/Configuration/config.plist" "${CONFIG_FILE}"
    chmod 600 "${CONFIG_FILE}"
    echo "==> Default config written to ${CONFIG_FILE} (permissions set to 600)"
else
    chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    echo "==> Existing config preserved at ${CONFIG_FILE}"
fi

mkdir -p "${LAUNCH_AGENT_DIR}"
cp "${AGENT_PLIST}" "${LAUNCH_AGENT_DIR}/com.user.gesturedaemon.plist"

echo "==> Loading LaunchAgent in user session..."
launchctl unload "${LAUNCH_AGENT_DIR}/com.user.gesturedaemon.plist" 2>/dev/null || true
launchctl load "${LAUNCH_AGENT_DIR}/com.user.gesturedaemon.plist"

echo "==> GestureDaemon successfully installed and loaded."

