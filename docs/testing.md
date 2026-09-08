# Testing

`./Scripts/run-tests.sh` compiles and executes thirteen standalone Swift harnesses for clipboard storage,
schema upgrades and filtering, appearance, palette placement, scroll following, hover arming, hotkeys, callout
placement, menu-bar icon sizing, icon caching, and Settings navigation. Reliability regressions cover
locked and unreadable databases, transaction rollback, pending image
writes during clear, complete paged searches, paste fallbacks using a private pasteboard, and the
accessory activation policy. Paste delivery tests inject permissions and event posting; they do not
grant Accessibility access or send keystrokes to other applications.

The definition of done is:

```sh
xcodegen generate
./Scripts/run-tests.sh
./Scripts/lint.sh
xcodebuild -project Dittoo.xcodeproj -scheme Dittoo \
  -configuration Debug CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project Dittoo.xcodeproj -scheme Dittoo \
  -configuration Release CODE_SIGNING_ALLOWED=NO clean build
```

Also smoke-test text and image capture, search and type filters, pin/unpin, delete/clear, copy, both
paste modes, application exclusions, retention, language switching, and onboarding.
