# Dittoo contributor instructions

Dittoo is a native, clipboard-only macOS menu-bar app. It targets macOS 26+, Xcode 26, and Swift 6,
uses SwiftUI and AppKit, and has no third-party runtime dependencies.

## Architecture

- `AppCore` owns all long-lived state and coordinators.
- `Features/Clipboard/Model` stays free of AppKit and SwiftUI.
- Clipboard history is durable user data under Application Support.
- Clipboard polling starts only after onboarding completes.
- Accessibility is requested only when a paste operation needs it.
- `project.yml` is authoritative; regenerate `Dittoo.xcodeproj` with XcodeGen.

## Scope

Keep the product single-purpose. Do not add launchers, notes, snippets, calculators, extensions,
quicklinks, file search, emoji browsing, system actions, window management, backup frameworks, or
website deployment code.

## Implementation rules

- Prefer minimal diffs and current Apple APIs.
- Preserve text/image capture, search, filters, pinning, deletion, copy, paste, exclusions, and
  retention behavior.
- Keep English and Simplified Chinese localizations complete.
- Use the custom dialog surface rather than `NSAlert`.
- Do not add dependencies, network calls, telemetry, or a Dock icon.

## Definition of done

- `xcodegen generate`
- `./Scripts/run-tests.sh`
- `./Scripts/lint.sh`
- clean Debug and Release builds
- no references to deleted feature symbols
