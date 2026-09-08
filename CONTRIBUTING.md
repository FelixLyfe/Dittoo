# Contributing to Dittoo

Keep changes focused on clipboard history. Feature additions outside that scope should start with an
issue explaining why they belong in a deliberately single-purpose app.

## Setup

- macOS 26+, Xcode 26
- `brew install xcodegen swiftlint`
- `xcodegen generate` after changing `project.yml` or the source tree
- Open `Dittoo.xcodeproj` to run the Debug channel (`Dittoo Dev.app`)

## Before submitting

```sh
./Scripts/run-tests.sh
./Scripts/lint.sh
xcodebuild -project Dittoo.xcodeproj -scheme Dittoo \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Exercise text and image capture, search, filters, pinning, deletion, copy, and paste. Visual changes
should include before/after evidence. Do not modify unrelated behavior or add dependencies.

Contributions are licensed under [AGPL-3.0](LICENSE).
