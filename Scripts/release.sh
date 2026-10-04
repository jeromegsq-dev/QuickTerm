#!/bin/bash
# Builds and signs build/QuickTerm.dmg.
#
# Also notarizes it when NOTARY_PROFILE names a keychain profile created with:
#   xcrun notarytool store-credentials <profile> \
#       --apple-id <apple id> --team-id <team id>
set -euo pipefail
cd "$(dirname "$0")/.."

export SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Jérôme Ghesquière (XZ2L4V7U2J)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DMG="build/QuickTerm.dmg"

./Scripts/build-app.sh

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R build/QuickTerm.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname QuickTerm -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [ -z "$NOTARY_PROFILE" ]; then
    echo "Built $DMG (signed, NOT notarized)"
    exit 0
fi
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Built $DMG (signed and notarized)"
