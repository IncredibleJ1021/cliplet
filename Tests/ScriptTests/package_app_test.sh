#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_SCRIPT="${ROOT_DIR}/scripts/package_app.sh"
VERIFY_SCRIPT="${ROOT_DIR}/scripts/verify_app.sh"

if VERSION=not-semver "${PACKAGE_SCRIPT}" >/tmp/cliplet-package-invalid.out 2>&1; then
  echo "package_app.sh accepted an invalid version" >&2
  exit 1
fi
grep -q "VERSION must use MAJOR.MINOR.PATCH" /tmp/cliplet-package-invalid.out

grep -q 'swift build' "${PACKAGE_SCRIPT}"
! grep -q 'swiftc' "${PACKAGE_SCRIPT}"
grep -q 'verify_app.sh' "${PACKAGE_SCRIPT}"
grep -q 'arm64-apple-macosx13.0' "${PACKAGE_SCRIPT}"
grep -q 'x86_64-apple-macosx13.0' "${PACKAGE_SCRIPT}"

if "${VERIFY_SCRIPT}" >/tmp/cliplet-verify-usage.out 2>&1; then
  echo "verify_app.sh accepted missing arguments" >&2
  exit 1
fi
grep -q "Usage:" /tmp/cliplet-verify-usage.out

echo "package app script checks passed"
