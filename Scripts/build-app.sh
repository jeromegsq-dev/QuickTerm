#!/bin/bash
# Builds build/QuickTerm.app (release, universal).
# Ad-hoc signed unless SIGN_IDENTITY names a Developer ID certificate.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/QuickTerm.app"

# One build per architecture, then lipo: SwiftPM can't build SwiftTerm's
# build plugin in a single multi-arch invocation.
BINARIES=()
for ARCH in arm64 x86_64; do
    swift build -c release --arch "$ARCH"
    BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)"
    BINARIES+=("$BIN/QuickTerm")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/QuickTerm"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SwiftPM resource bundles (SwiftTerm's Metal shaders).
find "$BIN" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp \
        --entitlements Resources/QuickTerm.entitlements --sign "$SIGN_IDENTITY" "$APP"
fi
echo "Built $APP"
