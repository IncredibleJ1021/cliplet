# AGENTS.md

## Project

Clip is a lightweight macOS menu bar clipboard history app built with Swift Package Manager, AppKit, and a small Foundation-only core module.

## Build And Test

- Build: `swift build`
- Test: `swift test`
- Run locally: `swift run Clip`
- Package ad-hoc signed app bundle: `./scripts/package_app.sh`

## Release

- Version tags must use `vMAJOR.MINOR.PATCH`, for example `v0.1.0`.
- Use `./scripts/create_release_tag.sh v0.1.0` from a clean `main` branch to run tests, package locally, push `main`, and push the tag.
- Pushing a version tag triggers `.github/workflows/release.yml`, which uploads `Clip.app` as a zip to GitHub Releases.

## Architecture Notes

- `Sources/ClipCore` contains persistence-friendly models and history logic.
- `Sources/Clip` contains AppKit UI, pasteboard polling, global hotkey registration, and settings.
- Keep clipboard history behavior covered in `Tests/ClipCoreTests`.
- The app currently stores text clipboard items only.

## Coding Guidelines

- Keep UI code AppKit-native and dependency-light.
- Avoid adding third-party packages unless they remove meaningful complexity.
- Prefer small, focused types over broad app-level controllers.
- Do not introduce automatic paste behavior without also adding an Accessibility permission flow and clear user-facing controls.
