#!/bin/bash
# Builds the release RNapi.app with the CLI embedded in Contents/Helpers.
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

echo "==> Building rnapi-cli (release)"
(cd RNapiKit && swift build -c release --product rnapi-cli)
CLI_BIN="RNapiKit/.build/release/rnapi-cli"

echo "==> Building RNapi.app (release)"
xcodebuild -project RNapi.xcodeproj -scheme RNapi -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    build | tail -2

APP="$DERIVED_DATA/Build/Products/Release/RNapi.app"

echo "==> Embedding CLI into the app bundle"
mkdir -p "$APP/Contents/Helpers"
cp "$CLI_BIN" "$APP/Contents/Helpers/rnapi-cli"

echo "==> Re-signing bundle"
codesign --force --options runtime --sign "$IDENTITY" "$APP/Contents/Helpers/rnapi-cli"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/RNapi.app"
cp -R "$APP" "$OUTPUT_DIR/RNapi.app"

echo "==> Done: $OUTPUT_DIR/RNapi.app"
echo "    CLI: $OUTPUT_DIR/RNapi.app/Contents/Helpers/rnapi-cli"
echo "    Install CLI:  ln -sf \"\$(pwd)/$OUTPUT_DIR/RNapi.app/Contents/Helpers/rnapi-cli\" /usr/local/bin/rnapi-cli"
