# Dittoo

Dittoo is a focused, native macOS clipboard-history app. It records copied text and images locally,
lets you search and filter them, and pastes them back into the app you were using.

## Features

- Searchable text and image clipboard history
- Type filters for text, images, links, and email addresses
- Pin, copy, paste, paste while keeping the window open, delete, and clear
- Source-application display and per-application exclusions
- Configurable retention, appearance, launch at login, and global shortcut
- English and Simplified Chinese interface
- Menu-bar operation with no Dock icon

Clipboard history is stored in the app's Application Support directory. Dittoo does not use
telemetry or third-party dependencies.

## Download

Download the latest build from [GitHub Releases](https://github.com/FelixLyfe/Dittoo/releases/latest).
Current releases require macOS 26 or later and an Apple Silicon Mac. They are self-signed and not
notarized, so macOS may require confirmation from Privacy & Security before the first launch.

## Build

Requirements: macOS 26+, Xcode 26, XcodeGen, and SwiftLint.

```sh
xcodegen generate
xcodebuild -project Dittoo.xcodeproj -scheme Dittoo \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
./Scripts/run-tests.sh
./Scripts/lint.sh
```

See [development](docs/development.md), [testing](docs/testing.md), [signing](docs/signing.md), and
[release](docs/release.md) for local development and tag-triggered GitHub Releases.

## Attribution and license

Dittoo is based on work by Abue Ammar and retains the original copyright and license notices. Dittoo is licensed under [AGPL-3.0](LICENSE).
