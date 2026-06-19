# cliplet

cliplet is a lightweight macOS clipboard history app. It lives in the menu bar, watches text copied to the system clipboard, and opens a compact Windows-style history panel with a configurable global shortcut.

## Features

- Menu bar app with no Dock icon
- Global shortcut, defaulting to `⌃⌥V`
- Text and image clipboard history with duplicate promotion
- Configurable history limit from 1 to 200 items
- Click, double-click, or press Return on an item to copy it back to the clipboard
- Local persistence through `UserDefaults`
- GitHub Actions CI and tag-based release packaging

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer

## Development

```sh
make build
make test
make run
```

## Package Locally

```sh
make package
open dist/cliplet.app
```

The local package is ad-hoc signed but not notarized. On a fresh machine, macOS may require opening it from Finder once with the context menu.

## Release

Release builds are created when a semantic version tag is pushed:

```sh
./scripts/create_release_tag.sh v0.2.0
```

The GitHub Actions release workflow builds `cliplet.app`, ad-hoc signs it, zips it, and attaches it to a GitHub Release.

## Current Scope

cliplet stores text and image clipboard entries. Selecting a history item copies it back to the clipboard; it does not automatically paste into the frontmost app, so it does not need Accessibility permission.
