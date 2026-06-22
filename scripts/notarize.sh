#!/bin/bash
# Notarizes a Developer ID-signed RQNapi.app and staples the ticket.
#
# Prerequisites:
#   - App built with scripts/build-release.sh and CODE_SIGN_IDENTITY set to a
#     "Developer ID Application" certificate.
#   - One-time credential setup:
#       xcrun notarytool store-credentials rqnapi-notary \
#           --apple-id <apple-id> --team-id <team-id> --password <app-specific-pw>
#
# Usage: scripts/notarize.sh build/RQNapi.app
set -euo pipefail

APP="${1:?usage: notarize.sh path/to/RQNapi.app}"
PROFILE="${NOTARY_PROFILE:-rqnapi-notary}"
ZIP="$(mktemp -d)/RQNapi.zip"

echo "==> Zipping for submission"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple notary service"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling ticket"
xcrun stapler staple "$APP"

echo "==> Verifying"
spctl --assess --type execute --verbose=2 "$APP"
echo "==> Notarization complete"
