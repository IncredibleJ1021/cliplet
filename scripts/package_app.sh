#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="cliplet"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

if [[ -z "${VERSION}" ]]; then
  VERSION="$(git -C "${ROOT_DIR}" describe --tags --always --dirty 2>/dev/null || echo "0.1.0")"
  VERSION="${VERSION#v}"
fi

if [[ -z "${BUILD_NUMBER}" ]]; then
  BUILD_NUMBER="$(git -C "${ROOT_DIR}" rev-list --count HEAD 2>/dev/null || echo "1")"
fi

build_with_swiftc() {
  local fallback_dir="${ROOT_DIR}/.build/fallback"
  mkdir -p "${fallback_dir}" "${ROOT_DIR}/.build/release"

  swiftc \
    -parse-as-library \
    -emit-library \
    -static \
    -module-name ClipletCore \
    "${ROOT_DIR}"/Sources/ClipletCore/*.swift \
    -emit-module-path "${fallback_dir}/ClipletCore.swiftmodule" \
    -o "${fallback_dir}/libClipletCore.a"

  swiftc \
    -I "${fallback_dir}" \
    "${fallback_dir}/libClipletCore.a" \
    "${ROOT_DIR}"/Sources/Cliplet/*.swift \
    -o "${ROOT_DIR}/.build/release/${APP_NAME}" \
    -framework AppKit \
    -framework Carbon
}

generate_app_icon() {
  local target_icns="$1"
  local source_png="${ROOT_DIR}/Resources/AppIcon.png"
  local icon_work_dir
  icon_work_dir="$(mktemp -d)"
  local iconset_dir="${icon_work_dir}/AppIcon.iconset"

  mkdir -p "${iconset_dir}"

  if [[ ! -f "${source_png}" ]]; then
    echo "Missing icon source: ${source_png}" >&2
    exit 1
  fi

  sips -z 16 16 "${source_png}" --out "${iconset_dir}/icon_16x16.png" >/dev/null
  sips -z 32 32 "${source_png}" --out "${iconset_dir}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "${source_png}" --out "${iconset_dir}/icon_32x32.png" >/dev/null
  sips -z 64 64 "${source_png}" --out "${iconset_dir}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${source_png}" --out "${iconset_dir}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${source_png}" --out "${iconset_dir}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${source_png}" --out "${iconset_dir}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${source_png}" --out "${iconset_dir}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "${source_png}" --out "${iconset_dir}/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "${source_png}" --out "${iconset_dir}/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "${iconset_dir}" -o "${target_icns}"
  rm -rf "${icon_work_dir}"
}

if ! swift build -c release --package-path "${ROOT_DIR}"; then
  echo "SwiftPM build failed; falling back to direct swiftc build." >&2
  build_with_swiftc
fi

APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${ROOT_DIR}/.build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

sed \
  -e "s/__VERSION__/${VERSION}/g" \
  -e "s/__BUILD__/${BUILD_NUMBER}/g" \
  "${ROOT_DIR}/Resources/Info.plist" > "${CONTENTS_DIR}/Info.plist"

generate_app_icon "${RESOURCES_DIR}/AppIcon.icns"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null
fi

echo "Packaged ${APP_DIR}"
