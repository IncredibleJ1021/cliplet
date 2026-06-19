#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 v0.1.0" >&2
  exit 1
fi

TAG="$1"

if [[ ! "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Tag must look like v0.1.0" >&2
  exit 1
fi

git diff --quiet
git diff --cached --quiet
swift test
./scripts/package_app.sh
git tag -a "${TAG}" -m "Release ${TAG}"
git push origin main
git push origin "${TAG}"
