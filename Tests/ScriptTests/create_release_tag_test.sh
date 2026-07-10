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
mkdir -p scripts fake-bin
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
git switch main >/dev/null

git tag v9.9.9
if ./scripts/create_release_tag.sh --check v9.9.9; then
  echo "Preflight accepted an existing local tag" >&2
  exit 1
fi
git tag -d v9.9.9 >/dev/null

cat > fake-bin/gh <<'EOF'
#!/usr/bin/env bash
echo "$(git rev-parse HEAD) completed success"
EOF
cat > scripts/package_app.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${VERSION:?}"
printf '%s\n' "app ${VERSION}" >> package.log
EOF
cat > scripts/package_dmg.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${VERSION:?}"
printf '%s\n' "dmg ${VERSION}" >> package.log
EOF
chmod +x fake-bin/gh scripts/package_app.sh scripts/package_dmg.sh
git add fake-bin/gh scripts/package_app.sh scripts/package_dmg.sh
git commit -m "Add packaging stubs" >/dev/null
git push >/dev/null 2>&1
PATH="${WORK_DIR}/repo/fake-bin:${PATH}" CLIPLET_TEST_GATE=github ./scripts/create_release_tag.sh v9.9.9
[[ -f package.log ]]
grep -qx 'app 9.9.9' package.log
grep -qx 'dmg v9.9.9' package.log
git rev-parse -q --verify refs/tags/v9.9.9 >/dev/null
git ls-remote --exit-code --tags origin refs/tags/v9.9.9 >/dev/null

echo "Release preflight tests passed"
