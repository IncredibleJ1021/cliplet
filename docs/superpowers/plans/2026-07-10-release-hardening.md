# Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and release one verifiable universal cliplet application without hiding SwiftPM failures.

**Architecture:** Build arm64 and x86_64 with separate SwiftPM scratch paths and explicit macOS 13 triples, combine them with `lipo`, then validate the assembled bundle through one reusable script. Release preflight becomes fail-closed and can accept either local XCTest success or a successful GitHub CI run for the exact HEAD commit.

**Tech Stack:** Bash, Swift Package Manager, lipo, vtool, plutil, codesign, GitHub Actions, GitHub CLI.

## Global Constraints

- Deployment target remains macOS 13.0 for both architectures.
- Release artifacts must contain arm64 and x86_64.
- SwiftPM is the only source build path; direct `swiftc` fallback is removed.
- CI and Release jobs use `macos-15`, not `macos-latest`.
- Ad-hoc signing remains explicit until Developer ID credentials are provided.
- No tag is created unless the exact main-branch commit has passed the configured test gate.

## File Structure

- Create `scripts/verify_app.sh`: validate bundle version, architectures, deployment targets, and signature.
- Modify `scripts/package_app.sh`: build two SwiftPM slices and assemble one universal executable.
- Modify `scripts/create_release_tag.sh`: enforce clean synchronized main and exact-commit test success.
- Create `Tests/ScriptTests/create_release_tag_test.sh`: exercise branch and cleanliness preflight in temporary repositories.
- Modify `.github/workflows/ci.yml`: pin runner and run engineering smoke checks.
- Modify `.github/workflows/release.yml`: pin runner and verify the packaged app before publishing.
- Modify `Makefile`: expose a local `verify` target.
- Modify `README.md` and `AGENTS.md`: document the fail-closed release path and CI test-gate fallback.

---

### Task 1: Build and Verify a Universal Application Bundle

**Files:**
- Create: `scripts/verify_app.sh`
- Modify: `scripts/package_app.sh`

**Interfaces:**
- Produces: `scripts/verify_app.sh dist/cliplet.app 0.4.1`
- Consumes: `SWIFT_BUILD_SYSTEM`, defaulting to `swiftbuild`
- Produces: `dist/cliplet.app/Contents/MacOS/cliplet` containing arm64 and x86_64

- [ ] **Step 1: Capture the current single-architecture failure**

Run the existing packager, then assert both architectures:

```bash
VERSION=0.4.1 ./scripts/package_app.sh
ARCHS="$(lipo -archs dist/cliplet.app/Contents/MacOS/cliplet)"
[[ " ${ARCHS} " == *" arm64 "* && " ${ARCHS} " == *" x86_64 "* ]]
```

Expected: the architecture assertion exits nonzero because the current script builds only the host architecture.

- [ ] **Step 2: Create the reusable bundle verifier**

Create `scripts/verify_app.sh`:

```bash
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
```

Make it executable:

```bash
chmod +x scripts/verify_app.sh
```

- [ ] **Step 3: Replace the direct-compiler fallback with two SwiftPM slices**

Remove the complete `build_with_swiftc` function and the conditional fallback block from `scripts/package_app.sh`.

Add these variables near the top:

```bash
SWIFT_BUILD_SYSTEM="${SWIFT_BUILD_SYSTEM:-swiftbuild}"
ARM64_SCRATCH="${ROOT_DIR}/.build/package-arm64"
X86_64_SCRATCH="${ROOT_DIR}/.build/package-x86_64"
UNIVERSAL_DIR="${ROOT_DIR}/.build/package-universal"
```

Replace default version discovery with a semver-only value:

```bash
if [[ -z "${VERSION}" ]]; then
  VERSION="$(git -C "${ROOT_DIR}" describe --tags --match 'v[0-9]*.[0-9]*.[0-9]*' --abbrev=0 2>/dev/null || echo "v0.1.0")"
  VERSION="${VERSION#v}"
fi

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must use MAJOR.MINOR.PATCH: ${VERSION}" >&2
  exit 1
fi
```

Add a focused build function before bundle assembly:

```bash
build_slice() {
  local triple="$1"
  local scratch_path="$2"
  local args=(
    -c release
    --package-path "${ROOT_DIR}"
    --scratch-path "${scratch_path}"
    --triple "${triple}"
    --product cliplet
    --build-system "${SWIFT_BUILD_SYSTEM}"
  )

  swift build "${args[@]}" >&2
  swift build "${args[@]}" --show-bin-path
}

ARM64_BIN_DIR="$(build_slice arm64-apple-macosx13.0 "${ARM64_SCRATCH}")"
X86_64_BIN_DIR="$(build_slice x86_64-apple-macosx13.0 "${X86_64_SCRATCH}")"
mkdir -p "${UNIVERSAL_DIR}"
lipo -create \
  "${ARM64_BIN_DIR}/${APP_NAME}" \
  "${X86_64_BIN_DIR}/${APP_NAME}" \
  -output "${UNIVERSAL_DIR}/${APP_NAME}"
```

Change the bundle copy source to:

```bash
cp "${UNIVERSAL_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
```

After ad-hoc signing, invoke:

```bash
"${ROOT_DIR}/scripts/verify_app.sh" "${APP_DIR}" "${VERSION}"
```

- [ ] **Step 4: Run the universal packager**

Run on the current Command Line Tools environment:

```bash
SWIFT_BUILD_SYSTEM=native VERSION=0.4.1 ./scripts/package_app.sh
```

Expected: the script prints one `Verified` line containing `arm64`, `x86_64`, and `minos=13.0`.

- [ ] **Step 5: Verify the packager fails closed**

Run:

```bash
VERSION=not-semver ./scripts/package_app.sh
```

Expected: exit code is nonzero and output contains `VERSION must use MAJOR.MINOR.PATCH` before any build begins.

- [ ] **Step 6: Commit universal packaging**

```bash
git add scripts/package_app.sh scripts/verify_app.sh
git commit -m "Build verifiable universal app bundles"
```

---

### Task 2: Make Release Tagging Fail Closed

**Files:**
- Modify: `scripts/create_release_tag.sh`
- Create: `Tests/ScriptTests/create_release_tag_test.sh`

**Interfaces:**
- Produces: `scripts/create_release_tag.sh [--check] vMAJOR.MINOR.PATCH`
- Consumes: `CLIPLET_TEST_GATE=local|github`
- Consumes: `SWIFT_BUILD_SYSTEM` through `package_app.sh`

- [ ] **Step 1: Write a failing preflight script test**

Create `Tests/ScriptTests/create_release_tag_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${ROOT_DIR}/scripts/create_release_tag.sh"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

git init --bare "${WORK_DIR}/origin.git" >/dev/null
git clone "${WORK_DIR}/origin.git" "${WORK_DIR}/repo" >/dev/null 2>&1
cd "${WORK_DIR}/repo"
git config user.name "Cliplet Tests"
git config user.email "cliplet-tests@example.com"
mkdir -p scripts
cp "${SOURCE_SCRIPT}" scripts/create_release_tag.sh
chmod +x scripts/create_release_tag.sh
printf 'fixture\n' > README.md
git add README.md scripts/create_release_tag.sh
git commit -m "Initial fixture" >/dev/null
git branch -M main
git push -u origin main >/dev/null 2>&1

./scripts/create_release_tag.sh --check v9.9.9

printf 'dirty\n' > untracked.txt
if ./scripts/create_release_tag.sh --check v9.9.9; then
  echo "Preflight accepted an untracked file" >&2
  exit 1
fi
rm untracked.txt

git switch -c feature >/dev/null
if ./scripts/create_release_tag.sh --check v9.9.9; then
  echo "Preflight accepted a non-main branch" >&2
  exit 1
fi

echo "Release preflight tests passed"
```

Make it executable and run it:

```bash
chmod +x Tests/ScriptTests/create_release_tag_test.sh
./Tests/ScriptTests/create_release_tag_test.sh
```

Expected: failure because the current release script does not understand `--check` or enforce the branch and untracked-file rules.

- [ ] **Step 2: Replace release-tag preflight and test-gate logic**

Replace `scripts/create_release_tag.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="release"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
  shift
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [--check] v0.4.1" >&2
  exit 1
fi

TAG="$1"
TEST_GATE="${CLIPLET_TEST_GATE:-local}"
cd "${ROOT_DIR}"

if [[ ! "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Tag must look like v0.4.1" >&2
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
    CI_RESULT="$(gh run list \
      --workflow CI \
      --commit "${HEAD_SHA}" \
      --limit 1 \
      --json headSha,status,conclusion \
      --jq '.[0] | "\(.headSha) \(.status) \(.conclusion)"')"
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
```

- [ ] **Step 3: Run release-preflight tests**

```bash
./Tests/ScriptTests/create_release_tag_test.sh
```

Expected: output ends with `Release preflight tests passed`.

- [ ] **Step 4: Check script syntax**

```bash
bash -n scripts/create_release_tag.sh
bash -n Tests/ScriptTests/create_release_tag_test.sh
```

Expected: both commands exit 0 without output.

- [ ] **Step 5: Commit release preflight**

```bash
git add scripts/create_release_tag.sh Tests/ScriptTests/create_release_tag_test.sh
git commit -m "Make release tagging fail closed"
```

---

### Task 3: Pin CI and Exercise Packaging Before Release

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `scripts/verify_app.sh`
- Consumes: `scripts/package_app.sh`
- Produces: a successful exact-commit `CI` run accepted by the release tag script.

- [ ] **Step 1: Record the missing workflow checks**

Run:

```bash
rg -n 'macos-15|package_app|ScriptTests|node --check|bash -n' .github/workflows
```

Expected: no matches for the new package and script checks; both workflows still use `macos-latest`.

- [ ] **Step 2: Replace CI workflow contents**

Use this content for `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: macos-15
    steps:
      - name: Check out repository
        uses: actions/checkout@v5

      - name: Validate scripts and metadata
        run: |
          bash -n scripts/*.sh Tests/ScriptTests/*.sh
          node --check npm/cliplet.js
          plutil -lint Resources/Info.plist
          npm run pack:check

      - name: Test release preflight
        run: ./Tests/ScriptTests/create_release_tag_test.sh

      - name: Build
        run: swift build

      - name: Test
        run: swift test

      - name: Package universal app
        run: VERSION=0.0.0 ./scripts/package_app.sh
```

- [ ] **Step 3: Pin and extend the Release workflow**

Change `runs-on` in `.github/workflows/release.yml` to:

```yaml
runs-on: macos-15
```

Insert after `Package app`:

```yaml
      - name: Verify packaged app
        run: ./scripts/verify_app.sh dist/cliplet.app "${GITHUB_REF_NAME#v}"
```

- [ ] **Step 4: Parse the workflows locally**

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml", aliases: true); YAML.load_file(".github/workflows/release.yml", aliases: true)'
```

Expected: Ruby exits 0 without a parser error.

- [ ] **Step 5: Commit workflow hardening**

```bash
git add .github/workflows/ci.yml .github/workflows/release.yml
git commit -m "Pin and verify release workflows"
```

---

### Task 4: Document and Expose Engineering Verification

**Files:**
- Modify: `Makefile`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Produces: `make verify`
- Documents: `CLIPLET_TEST_GATE=github` for a Command Line Tools-only release machine.

- [ ] **Step 1: Add the verify target**

Change the phony declaration to:

```make
.PHONY: build test run verify package dmg clean
```

Add:

```make
verify:
	bash -n scripts/*.sh Tests/ScriptTests/*.sh
	node --check npm/cliplet.js
	plutil -lint Resources/Info.plist
	npm run pack:check
	./Tests/ScriptTests/create_release_tag_test.sh
	swift build
	swift test
```

- [ ] **Step 2: Update developer and release documentation**

Add `make verify` to the README development commands. Replace the release paragraph with the following Markdown block:

````markdown
发布脚本要求工作树干净、当前分支为 `main` 且 `HEAD` 与 `origin/main` 完全一致。默认在本地运行完整测试：

```sh
./scripts/create_release_tag.sh v0.4.1
```

若发布机器只有 Command Line Tools、无法运行 XCTest，必须先推送 `main` 并等待同一提交的 GitHub CI 成功，再显式使用远端测试门禁：

```sh
CLIPLET_TEST_GATE=github SWIFT_BUILD_SYSTEM=native ./scripts/create_release_tag.sh v0.4.1
```
````

Update `AGENTS.md` release instructions with the same exact-commit CI requirement and note that `package_app.sh` produces a universal arm64/x86_64 bundle.

- [ ] **Step 3: Run documentation-adjacent checks**

```bash
make verify
git diff --check
```

Expected: all verification commands pass in a full-Xcode environment; on the current machine, the XCTest step is explicitly deferred to exact-commit GitHub CI while all preceding checks run locally.

- [ ] **Step 4: Commit documentation and Makefile updates**

```bash
git add Makefile README.md AGENTS.md
git commit -m "Document verified release workflow"
```

---

### Task 5: Verify Release Engineering as One Unit

**Files:**
- Review: `scripts/package_app.sh`
- Review: `scripts/verify_app.sh`
- Review: `scripts/create_release_tag.sh`
- Review: `.github/workflows/ci.yml`
- Review: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: all interfaces produced by Tasks 1–4.
- Produces: release engineering ready for the v0.4.1 rollout plan.

- [ ] **Step 1: Run local non-XCTest verification**

```bash
bash -n scripts/*.sh Tests/ScriptTests/*.sh
node --check npm/cliplet.js
plutil -lint Resources/Info.plist
npm run pack:check
./Tests/ScriptTests/create_release_tag_test.sh
```

Expected: every command exits 0.

- [ ] **Step 2: Build and inspect the universal app**

```bash
SWIFT_BUILD_SYSTEM=native VERSION=0.4.1 ./scripts/package_app.sh
./scripts/verify_app.sh dist/cliplet.app 0.4.1
```

Expected: verification reports both architectures and macOS 13.0.

- [ ] **Step 3: Build a version-matched DMG**

```bash
VERSION=v0.4.1 ./scripts/package_dmg.sh
test -f dist/cliplet-macOS-v0.4.1.dmg
```

Expected: the DMG exists with the exact release filename.

- [ ] **Step 4: Inspect the engineering diff**

```bash
git diff HEAD~4 -- scripts Tests/ScriptTests .github Makefile README.md AGENTS.md
git diff --check
```

Expected: no fallback compiler path remains, all release guards have tests or smoke checks, and no whitespace errors exist.
