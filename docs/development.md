# Development

## Requirements

- macOS 26+
- Xcode 26
- XcodeGen
- SwiftLint

```sh
brew install xcodegen swiftlint
xcodegen generate
open Dittoo.xcodeproj
```

Debug uses `io.github.felixlyfe.Dittoo.dev` and builds as `Dittoo Dev.app`. Release uses
`io.github.felixlyfe.Dittoo` and builds as `Dittoo.app`.

Clipboard history, preferences, and onboarding state use the new bundle identifiers; earlier
installations are not imported. Their data files are left in place. The product name, Xcode project, and scheme are
`Dittoo`; the GitHub repository is `FelixLyfe/Dittoo`.

## Command-line validation

```sh
xcodegen generate
xcodebuild -project Dittoo.xcodeproj -scheme Dittoo \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Dittoo.xcodeproj -scheme Dittoo \
  -configuration Release CODE_SIGNING_ALLOWED=NO build
./Scripts/run-tests.sh
./Scripts/lint.sh
```

Use a custom `-derivedDataPath` when the environment cannot write to Xcode's default DerivedData.
