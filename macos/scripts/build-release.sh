#!/bin/bash
# Builds the release QNapi.app with the CLI embedded in Contents/Helpers.
#
# Usage: scripts/build-release.sh [output-dir]
#
# Signing: set CODE_SIGN_IDENTITY to a "Developer ID Application: ..." identity
# for distributable builds; defaults to ad-hoc signing for local use.
set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT_DIR="${1:-build}"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building qnapi-cli (release)"
(cd QNapiKit && swift build -c release --product qnapi-cli)
CLI_BIN="QNapiKit/.build/release/qnapi-cli"

echo "==> Building QNapi.app (release)"
xcodebuild -project QNapi.xcodeproj -scheme QNapi -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    build | tail -2

APP="$DERIVED_DATA/Build/Products/Release/QNapi.app"

echo "==> Embedding CLI into the app bundle"
mkdir -p "$APP/Contents/Helpers"
cp "$CLI_BIN" "$APP/Contents/Helpers/qnapi-cli"

echo "==> Re-signing bundle"
codesign --force --options runtime --sign "$IDENTITY" "$APP/Contents/Helpers/qnapi-cli"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/QNapi.app"
cp -R "$APP" "$OUTPUT_DIR/QNapi.app"

echo "==> Done: $OUTPUT_DIR/QNapi.app"
echo "    CLI: $OUTPUT_DIR/QNapi.app/Contents/Helpers/qnapi-cli"
echo "    Install CLI:  ln -sf \"\$(pwd)/$OUTPUT_DIR/QNapi.app/Contents/Helpers/qnapi-cli\" /usr/local/bin/qnapi-cli"
