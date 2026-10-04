#!/bin/bash
# Builds, signs and notarizes build/QuickTerm.dmg.
#
# One-time setup, to store the notary credentials in the keychain:
#   xcrun notarytool store-credentials quickterm-notary \
#       --apple-id <apple id> --team-id <team id>
set -euo pipefail
cd "$(dirname "$0")/.."

export SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Jérôme Ghesquière (XZ2L4V7U2J)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-quickterm-notary}"
DMG="build/QuickTerm.dmg"

./Scripts/build-app.sh

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R build/QuickTerm.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname QuickTerm -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "Built $DMG (signed, NOT notarized)"
    exit 0
fi
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Built $DMG (signed and notarized)"
