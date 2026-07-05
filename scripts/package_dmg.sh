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

WORK_DIR="$(mktemp -d)"
STAGING_DIR="${WORK_DIR}/stage"
MOUNT_DIR=""
RW_DMG="${WORK_DIR}/${APP_NAME}.rw.dmg"
DMG_PATH="${ROOT_DIR}/dist/${APP_NAME}-macOS-${VERSION}.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"

cleanup() {
  if [[ -n "${MOUNT_DIR}" ]]; then
    hdiutil detach "${MOUNT_DIR}" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "${WORK_DIR}"
}

create_background() {
  local target_png="$1"
  local drawer="${STAGING_DIR}/draw_dmg_background.swift"

  cat > "${drawer}" <<'SWIFT'
import AppKit
import Foundation

let target = URL(fileURLWithPath: CommandLine.arguments[1])
let version = CommandLine.arguments[2]
let size = NSSize(width: 660, height: 420)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawString(_ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color textColor: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: textColor
    ]
    string.draw(at: point, withAttributes: attributes)
}

let image = NSImage(size: size)
image.lockFocus()

let rect = NSRect(origin: .zero, size: size)
color(247, 250, 252).setFill()
rect.fill()

let topBand = NSBezierPath(rect: NSRect(x: 0, y: 310, width: size.width, height: 110))
NSGradient(colors: [
    color(230, 246, 249),
    color(246, 250, 252)
])?.draw(in: topBand, angle: 90)

drawString("Install cliplet", at: NSPoint(x: 38, y: 356), size: 25, weight: .semibold, color: color(42, 52, 65))
drawString(version, at: NSPoint(x: 39, y: 330), size: 13, weight: .medium, color: color(109, 121, 135))

let hint = "Drag cliplet to Applications"
let hintAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .medium),
    .foregroundColor: color(78, 90, 104)
]
let hintSize = hint.size(withAttributes: hintAttributes)
hint.draw(
    at: NSPoint(x: (size.width - hintSize.width) / 2, y: 78),
    withAttributes: hintAttributes
)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 272, y: 218))
arrow.line(to: NSPoint(x: 388, y: 218))
arrow.lineCapStyle = .round
arrow.lineWidth = 8
color(83, 158, 229, 0.42).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 380, y: 238))
head.line(to: NSPoint(x: 408, y: 218))
head.line(to: NSPoint(x: 380, y: 198))
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.lineWidth = 8
head.stroke()

let leftPad = NSBezierPath(roundedRect: NSRect(x: 92, y: 130, width: 164, height: 164), xRadius: 34, yRadius: 34)
color(255, 255, 255, 0.45).setFill()
leftPad.fill()
color(207, 223, 233, 0.6).setStroke()
leftPad.lineWidth = 1
leftPad.stroke()

let rightPad = NSBezierPath(roundedRect: NSRect(x: 404, y: 130, width: 164, height: 164), xRadius: 34, yRadius: 34)
color(255, 255, 255, 0.45).setFill()
rightPad.fill()
color(207, 223, 233, 0.6).setStroke()
rightPad.lineWidth = 1
rightPad.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render DMG background")
}

try data.write(to: target)
SWIFT

  swift "${drawer}" "${target_png}" "${VERSION}"
  rm -f "${drawer}"
}

style_dmg() {
  local volume_name="$1"
  local background_path="$2"

  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "${volume_name}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 780, 540}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set text size of theViewOptions to 14
    set background picture of theViewOptions to (POSIX file "${background_path}" as alias)
    set position of item "${APP_NAME}.app" of container window to {174, 210}
    set position of item "Applications" of container window to {486, 210}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
}

trap cleanup EXIT

mkdir -p "${STAGING_DIR}"

cp -R "${APP_DIR}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"
mkdir -p "${STAGING_DIR}/.background"
create_background "${STAGING_DIR}/.background/background.png"
chflags hidden "${STAGING_DIR}/.background" 2>/dev/null || true

rm -f "${DMG_PATH}"

if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from \
    --format UDRW \
    --volumeName "${VOLUME_NAME}" \
    "${STAGING_DIR}" \
    "${RW_DMG}"
else
  hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDRW \
    "${RW_DMG}"
fi

ATTACH_PLIST="${WORK_DIR}/attach.plist"
diskutil image attach \
  --plist \
  "${RW_DMG}" > "${ATTACH_PLIST}"

MOUNT_DIR="$(python3 - "${ATTACH_PLIST}" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    plist = plistlib.load(handle)

for entity in plist.get("system-entities", []):
    mount_point = entity.get("mount-point")
    if mount_point:
        print(mount_point)
        break
else:
    raise SystemExit("Could not determine mounted DMG path")
PY
)"

ACTUAL_VOLUME_NAME="$(diskutil info "${MOUNT_DIR}" | awk -F: '/Volume Name/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')"

style_dmg "${ACTUAL_VOLUME_NAME}" "${MOUNT_DIR}/.background/background.png"
sync
hdiutil detach "${MOUNT_DIR}" -quiet
MOUNT_DIR=""

diskutil image create from \
  --format UDZO \
  "${RW_DMG}" \
  "${DMG_PATH}" >/dev/null

echo "Packaged ${DMG_PATH}"
