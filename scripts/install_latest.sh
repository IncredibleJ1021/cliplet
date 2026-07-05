#!/usr/bin/env bash
set -euo pipefail

REPO="IncredibleJ1021/cliplet"
APP_NAME="cliplet"
INSTALL_DIR="${CLIPLET_INSTALL_DIR:-/Applications}"

latest_tag() {
  if [[ -n "${CLIPLET_VERSION:-}" ]]; then
    printf '%s\n' "${CLIPLET_VERSION}"
    return
  fi

  local latest_url
  latest_url="$(curl -fsIL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
  printf '%s\n' "${latest_url##*/}"
}

copy_app() {
  local source_app="$1"
  local target_app="${INSTALL_DIR}/${APP_NAME}.app"

  if [[ ! -d "${INSTALL_DIR}" ]]; then
    echo "Install directory does not exist: ${INSTALL_DIR}" >&2
    exit 1
  fi

  if [[ -w "${INSTALL_DIR}" ]]; then
    rm -rf "${target_app}"
    ditto "${source_app}" "${target_app}"
  else
    echo "Installing to ${INSTALL_DIR} requires administrator privileges."
    sudo rm -rf "${target_app}"
    sudo ditto "${source_app}" "${target_app}"
  fi
}

TAG="$(latest_tag)"
ASSET_NAME="cliplet-macOS-${TAG}.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Downloading ${DOWNLOAD_URL}"
curl -fL "${DOWNLOAD_URL}" -o "${TMP_DIR}/${ASSET_NAME}"
unzip -q "${TMP_DIR}/${ASSET_NAME}" -d "${TMP_DIR}"

APP_PATH="$(find "${TMP_DIR}" -maxdepth 2 -type d -name "${APP_NAME}.app" -print -quit)"
if [[ -z "${APP_PATH}" ]]; then
  echo "Could not find ${APP_NAME}.app in downloaded archive." >&2
  exit 1
fi

copy_app "${APP_PATH}"

echo "Installed ${APP_NAME}.app to ${INSTALL_DIR}"
echo "If macOS blocks the first launch, open it once from Finder with Control-click > Open."
