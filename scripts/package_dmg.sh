#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="cliplet"
VERSION="${VERSION:-}"

if [[ -z "${VERSION}" ]]; then
  VERSION="$(git -C "${ROOT_DIR}" describe --tags --always --dirty 2>/dev/null || echo "0.1.0")"
fi

APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
if [[ ! -d "${APP_DIR}" ]]; then
  echo "Missing ${APP_DIR}; run ./scripts/package_app.sh first." >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d)"
DMG_PATH="${ROOT_DIR}/dist/${APP_NAME}-macOS-${VERSION}.dmg"

trap 'rm -rf "${STAGING_DIR}"' EXIT

cp -R "${APP_DIR}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${DMG_PATH}"

if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from \
    --format UDZO \
    --volumeName "${APP_NAME} ${VERSION}" \
    "${STAGING_DIR}" \
    "${DMG_PATH}"
else
  hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"
fi

echo "Packaged ${DMG_PATH}"
