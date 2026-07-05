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
  local icon_work_dir
  icon_work_dir="$(mktemp -d)"
  local iconset_dir="${icon_work_dir}/AppIcon.iconset"
  local drawer="${icon_work_dir}/draw_icon.swift"

  mkdir -p "${iconset_dir}"

  cat > "${drawer}" <<'SWIFT'
import AppKit
import Foundation

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon() {
    NSGraphicsContext.current?.imageInterpolation = .high

    let shadow = NSShadow()
    shadow.shadowColor = color(24, 56, 96, 0.28)
    shadow.shadowBlurRadius = 42
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.set()

    let outer = roundedRect(NSRect(x: 86, y: 86, width: 852, height: 852), radius: 210)
    NSGradient(colors: [
        color(27, 214, 199),
        color(44, 142, 238),
        color(88, 99, 246)
    ])?.draw(in: outer, angle: -38)

    NSShadow().set()

    color(255, 255, 255, 0.20).setStroke()
    outer.lineWidth = 10
    outer.stroke()

    let pageShadow = NSShadow()
    pageShadow.shadowColor = color(9, 41, 74, 0.22)
    pageShadow.shadowBlurRadius = 24
    pageShadow.shadowOffset = NSSize(width: 0, height: -12)
    pageShadow.set()

    let page = roundedRect(NSRect(x: 284, y: 210, width: 456, height: 604), radius: 60)
    color(255, 255, 255, 0.92).setFill()
    page.fill()

    NSShadow().set()

    let clip = roundedRect(NSRect(x: 392, y: 748, width: 240, height: 92), radius: 38)
    color(226, 240, 248, 0.96).setFill()
    clip.fill()

    let clipInner = roundedRect(NSRect(x: 446, y: 786, width: 132, height: 46), radius: 23)
    color(52, 141, 219, 0.22).setStroke()
    clipInner.lineWidth = 18
    clipInner.stroke()

    let lineColor = color(43, 108, 174, 0.52)
    lineColor.setStroke()
    for y in [624, 526, 428] {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 360, y: y))
        line.line(to: NSPoint(x: 664, y: y))
        line.lineCapStyle = .round
        line.lineWidth = 30
        line.stroke()
    }

    let check = NSBezierPath()
    check.move(to: NSPoint(x: 372, y: 322))
    check.line(to: NSPoint(x: 468, y: 236))
    check.line(to: NSPoint(x: 658, y: 470))
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.lineWidth = 52
    color(34, 191, 149).setStroke()
    check.stroke()
}

for (logicalSize, scale) in sizes {
    let pixelSize = logicalSize * scale
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()
    NSGraphicsContext.current?.cgContext.scaleBy(
        x: CGFloat(pixelSize) / 1024,
        y: CGFloat(pixelSize) / 1024
    )
    drawIcon()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not render icon size \(logicalSize)@\(scale)x")
    }

    let suffix = scale == 2 ? "@2x" : ""
    let filename = "icon_\(logicalSize)x\(logicalSize)\(suffix).png"
    try data.write(to: iconsetURL.appendingPathComponent(filename))
}
SWIFT

  swift "${drawer}" "${iconset_dir}"
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
