#!/bin/zsh
# Builds AsterNUP.app with SwiftPM (Xcode or the Command Line Tools), ARM64, signed.
# Usage: scripts/make_app.sh [output dir]      (default: build/)
#   ASTERNUP_SIGN_IDENTITY="Apple Development: Name (TEAMID)"  sign with your certificate (default: ad-hoc "-")
set -euo pipefail
cd "${0:A:h}/.."
OUT="${1:-build}"
IDENTITY="${ASTERNUP_SIGN_IDENTITY:--}"
VERSION="$(sed -n 's/^MARKETING_VERSION = //p' Config/Signing.xcconfig)"
BUILDNUM="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/AsterNUP"
APP="$OUT/AsterNUP.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AsterNUP"
sed -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.asterpolaris.AsterNUP/' -e "s/\$(MARKETING_VERSION)/$VERSION/" -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILDNUM/" \
    Resources/App/Info.plist > "$APP/Contents/Info.plist"
cp Resources/App/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/Backend "$APP/Contents/Resources/Backend"
find "$APP" -name __pycache__ -prune -exec rm -rf {} +
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --options runtime --timestamp=none --entitlements Resources/App/AsterNUP.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"
echo "archs: $(lipo -archs "$APP/Contents/MacOS/AsterNUP")"
echo "$APP"
