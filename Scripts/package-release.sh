#!/bin/bash
# Build and package a signed Dittoo release for GitHub Releases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="${1:-$REPO_ROOT/dist}"
DERIVED_DATA_PATH="${DITTOO_DERIVED_DATA_PATH:-$REPO_ROOT/build/DerivedData-Dittoo-Release}"
SIGNING_IDENTITY="${DITTOO_CODE_SIGN_IDENTITY:-Dittoo Self-Signed}"
EXPECTED_BUNDLE_ID="io.github.felixlyfe.Dittoo"

for command in xcodegen xcodebuild ditto shasum; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing required command: $command" >&2
        exit 1
    fi
done

if ! security find-identity -v -p codesigning | grep -F "\"$SIGNING_IDENTITY\"" >/dev/null; then
    echo "Missing valid code-signing identity: $SIGNING_IDENTITY" >&2
    echo "See docs/signing.md before packaging a release." >&2
    exit 1
fi

mkdir -p "$DIST_DIR"
cd "$REPO_ROOT"

xcodegen generate
xcodebuild \
    -project Dittoo.xcodeproj \
    -scheme Dittoo \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination 'generic/platform=macOS' \
    clean build \
    ARCHS=arm64 \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    -quiet

# Build inside DerivedData so a clean build never tries to delete the distribution directory.
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Dittoo.app"
APP_PATH="$DIST_DIR/Dittoo.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

if [ ! -d "$BUILT_APP_PATH" ]; then
    echo "Release build did not produce $BUILT_APP_PATH" >&2
    exit 1
fi

if [ ! "$BUILT_APP_PATH" -ef "$APP_PATH" ]; then
    /bin/rm -rf "$APP_PATH"
    /usr/bin/ditto "$BUILT_APP_PATH" "$APP_PATH"
fi

if [ ! -d "$APP_PATH" ] || [ ! -f "$INFO_PLIST" ]; then
    echo "Release build did not produce $APP_PATH" >&2
    exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"

if [ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]; then
    echo "Unexpected bundle ID: $BUNDLE_ID" >&2
    exit 1
fi

for localization in en.lproj zh-Hans.lproj; do
    if [ ! -d "$APP_PATH/Contents/Resources/$localization" ]; then
        echo "Missing packaged localization: $localization" >&2
        exit 1
    fi
done

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE_INFO="$(/usr/bin/codesign -d --verbose=2 "$APP_PATH" 2>&1)"
if ! printf '%s\n' "$SIGNATURE_INFO" | grep -F "Authority=$SIGNING_IDENTITY" >/dev/null; then
    echo "Release is not signed by $SIGNING_IDENTITY" >&2
    exit 1
fi

ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/$EXECUTABLE")"
ARCH_LABEL="${ARCHITECTURES// /-}"
ZIP_NAME="Dittoo-$VERSION-macOS-$ARCH_LABEL.zip"
CHECKSUM_NAME="$ZIP_NAME.sha256"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
CHECKSUM_PATH="$DIST_DIR/$CHECKSUM_NAME"

/bin/rm -f "$ZIP_PATH" "$CHECKSUM_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
(
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 "$ZIP_NAME" > "$CHECKSUM_NAME"
)

echo
echo "Release package ready"
echo "  App:      $APP_PATH"
echo "  ZIP:      $ZIP_PATH"
echo "  SHA-256:  $CHECKSUM_PATH"
echo "  Version:  $VERSION"
echo "  Bundle:   $BUNDLE_ID"
echo "  Arch:     $ARCHITECTURES"
echo "  Signing:  $SIGNING_IDENTITY"
echo
echo "This self-signed build is not notarized. Document that limitation in the GitHub Release."
