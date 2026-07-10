#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="release"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
  shift
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [--check] v0.1.0" >&2
  exit 1
fi

TAG="$1"
TEST_GATE="${CLIPLET_TEST_GATE:-local}"
cd "${ROOT_DIR}"

if [[ ! "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Tag must look like v0.1.0" >&2
  exit 1
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "Release must run from main" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "Release requires a clean worktree" >&2
  exit 1
fi

git fetch origin main --tags
HEAD_SHA="$(git rev-parse HEAD)"
UPSTREAM_SHA="$(git rev-parse origin/main)"
if [[ "${HEAD_SHA}" != "${UPSTREAM_SHA}" ]]; then
  echo "HEAD must equal origin/main" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "Tag already exists locally: ${TAG}" >&2
  exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "Tag already exists on origin: ${TAG}" >&2
  exit 1
fi

if [[ "${MODE}" == "check" ]]; then
  echo "Release preflight passed for ${TAG} at ${HEAD_SHA}"
  exit 0
fi

case "${TEST_GATE}" in
  local)
    swift test
    ;;
  github)
    if ! command -v gh >/dev/null 2>&1; then
      echo "GitHub test gate requires gh" >&2
      exit 1
    fi
    CI_RESULT="$(gh run list --workflow CI --commit "${HEAD_SHA}" --limit 1 --json headSha,status,conclusion --jq '.[0] | "\(.headSha) \(.status) \(.conclusion)"')"
    if [[ "${CI_RESULT}" != "${HEAD_SHA} completed success" ]]; then
      echo "Exact HEAD has no successful completed CI run: ${CI_RESULT}" >&2
      exit 1
    fi
    ;;
  *)
    echo "CLIPLET_TEST_GATE must be local or github" >&2
    exit 1
    ;;
esac

VERSION="${TAG#v}" ./scripts/package_app.sh
VERSION="${TAG}" ./scripts/package_dmg.sh
git tag -a "${TAG}" -m "Release ${TAG}"
git push origin main
git push origin "${TAG}"
