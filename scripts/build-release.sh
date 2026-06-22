#!/bin/bash
# Builds the release RQNapi.app with the CLI embedded in Contents/Helpers.
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

echo "==> Building rqnapi-cli (release)"
(cd RQNapiKit && swift build -c release --product rqnapi-cli)
CLI_BIN="RQNapiKit/.build/release/rqnapi-cli"

echo "==> Building RQNapi.app (release)"
xcodebuild -project RQNapi.xcodeproj -scheme RQNapi -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    build | tail -2

APP="$DERIVED_DATA/Build/Products/Release/RQNapi.app"

echo "==> Embedding CLI into the app bundle"
mkdir -p "$APP/Contents/Helpers"
cp "$CLI_BIN" "$APP/Contents/Helpers/rqnapi-cli"

echo "==> Re-signing bundle"
codesign --force --options runtime --sign "$IDENTITY" "$APP/Contents/Helpers/rqnapi-cli"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/RQNapi.app"
cp -R "$APP" "$OUTPUT_DIR/RQNapi.app"

echo "==> Done: $OUTPUT_DIR/RQNapi.app"
echo "    CLI: $OUTPUT_DIR/RQNapi.app/Contents/Helpers/rqnapi-cli"
echo "    Install CLI:  ln -sf \"\$(pwd)/$OUTPUT_DIR/RQNapi.app/Contents/Helpers/rqnapi-cli\" /usr/local/bin/rqnapi-cli"
