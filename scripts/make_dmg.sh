#!/bin/zsh
# Builds AsterNUP.app and packs it into a drag-to-install disk image: build/AsterNUP-<version>.dmg
# Usage: scripts/make_dmg.sh
#   ASTERNUP_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"  signs the app and the DMG (default: ad-hoc app, unsigned DMG)
# Notarize a Developer ID build afterwards with:
#   xcrun notarytool submit build/AsterNUP-<version>.dmg --keychain-profile <profile> --wait && xcrun stapler staple build/AsterNUP-<version>.dmg
set -euo pipefail
cd "${0:A:h}/.."
scripts/make_app.sh build >/dev/null
VERSION="$(sed -n 's/^MARKETING_VERSION = //p' Config/Signing.xcconfig)"
STAGE="$(mktemp -d)/AsterNUP"
mkdir -p "$STAGE"
cp -R build/AsterNUP.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<TXT
AsterNUP $VERSION
A controller-first game library for Apple silicon Macs.

1. Drag AsterNUP to Applications, then open it.
2. If macOS says it can't check AsterNUP for malicious software (this build isn't notarized):
   System Settings > Privacy & Security, scroll down, click Open Anyway next to AsterNUP.
   Or in Terminal: xattr -dr com.apple.quarantine /Applications/AsterNUP.app
3. In AsterNUP: Backend & Toolchain > Set up backend, then Add a game > Import a dump.

Building games also needs Xcode, its Metal toolchain and a few Homebrew tools;
Backend & Toolchain lists what's missing and how to fix each item.

Getting started:  https://github.com/asterpolaris/AsterNUP/blob/main/docs/GETTING_STARTED.md
Troubleshooting:  https://github.com/asterpolaris/AsterNUP/blob/main/docs/TROUBLESHOOTING.md
Acknowledgements: https://github.com/asterpolaris/AsterNUP/blob/main/ACKNOWLEDGEMENTS.md
TXT
DMG="build/AsterNUP-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "AsterNUP $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "${STAGE:h}"
if [[ -n "${ASTERNUP_SIGN_IDENTITY:-}" && "$ASTERNUP_SIGN_IDENTITY" != "-" ]]; then codesign --force --sign "$ASTERNUP_SIGN_IDENTITY" "$DMG"; fi
hdiutil verify "$DMG" >/dev/null && echo "verified: $DMG ($(du -h "$DMG" | cut -f1))"
