#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${REPO_DIR}/build"
APP_PATH="${BUILD_DIR}/GestureDaemon.app"
DMG_PATH="${BUILD_DIR}/GestureDaemon.dmg"
STAGING_DIR="${BUILD_DIR}/dmg_staging"

if [ ! -d "${APP_PATH}" ]; then
    echo "==> GestureDaemon.app not found. Building app first..."
    make app
fi

echo "==> Preparing DMG staging directory..."
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

echo "==> Copying GestureDaemon.app to staging..."
cp -R "${APP_PATH}" "${STAGING_DIR}/"

echo "==> Creating /Applications symlink..."
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> Packaging GestureDaemon.dmg..."
hdiutil create \
    -volname "GestureDaemon" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

rm -rf "${STAGING_DIR}"
echo "==> Distributable DMG successfully created at ${DMG_PATH}"

