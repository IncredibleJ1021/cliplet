#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /path/to/cliplet.app 0.4.1" >&2
  exit 1
fi

APP_DIR="$1"
EXPECTED_VERSION="$2"
INFO_PLIST="${APP_DIR}/Contents/Info.plist"
BINARY="${APP_DIR}/Contents/MacOS/cliplet"

if [[ ! "${EXPECTED_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected version must use MAJOR.MINOR.PATCH: ${EXPECTED_VERSION}" >&2
  exit 1
fi
if [[ ! -f "${INFO_PLIST}" || ! -x "${BINARY}" ]]; then
  echo "Incomplete app bundle: ${APP_DIR}" >&2
  exit 1
fi

ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "${INFO_PLIST}")"
if [[ "${ACTUAL_VERSION}" != "${EXPECTED_VERSION}" ]]; then
  echo "Version mismatch: expected ${EXPECTED_VERSION}, got ${ACTUAL_VERSION}" >&2
  exit 1
fi

ARCHS="$(lipo -archs "${BINARY}")"
for ARCH in arm64 x86_64; do
  if [[ " ${ARCHS} " != *" ${ARCH} "* ]]; then
    echo "Missing architecture ${ARCH}: ${ARCHS}" >&2
    exit 1
  fi
done

for ARCH in arm64 x86_64; do
  MIN_OS="$(vtool -arch "${ARCH}" -show-build "${BINARY}" | awk '$1 == "minos" { print $2 }')"
  if [[ "${MIN_OS}" != "13.0" ]]; then
    echo "Unexpected ${ARCH} deployment target: ${MIN_OS}" >&2
    exit 1
  fi
done

codesign --verify --deep --strict "${APP_DIR}"
echo "Verified ${APP_DIR}: version=${ACTUAL_VERSION} archs=${ARCHS} minos=13.0"
