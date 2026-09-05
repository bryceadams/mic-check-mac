#!/bin/zsh
# Build, sign, notarize, staple, and package Mic Check as a DMG.
#
#   scripts/release.sh                 full release (needs notarytool profile "MicCheck-Notary")
#   scripts/release.sh --skip-notarize build + DMG only, for testing the pipeline
#
# One-time credential setup (app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials "MicCheck-Notary" --apple-id "you@example.com" --team-id XQL374L3KC
set -euo pipefail

cd "$(dirname "$0")/.."
PROFILE="MicCheck-Notary"
IDENTITY="Developer ID Application: UJU Pty Ltd (XQL374L3KC)"
SKIP_NOTARIZE=0
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=1

VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
BUILD_NUMBER=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
DIST="dist"
APP="build/Build/Products/Release/MicCheck.app"
DMG="$DIST/Mic-Check-$VERSION.dmg"
ZIP="$DIST/Mic-Check-$VERSION.zip"

step() { print -P "\n%F{cyan}==> $1%f"; }

step "Generating project and building Release $VERSION ($BUILD_NUMBER)"
xcodegen generate >/dev/null
xcodebuild -project MicCheck.xcodeproj -scheme MicCheck -configuration Release \
  -derivedDataPath build clean build 2>&1 | grep -E "error:|warning:|BUILD" | grep -v appintents || true
[[ -d "$APP" ]] || { echo "Build failed: $APP missing"; exit 1; }

step "Verifying signature and entitlements"
codesign --verify --deep --strict --verbose=1 "$APP"
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "get-task-allow"; then
  echo "Release build still carries get-task-allow; refusing to notarize."; exit 1
fi
codesign -dvv "$APP" 2>&1 | grep -E "Authority=Developer ID|flags=.*runtime" || { echo "Not signed with Developer ID + hardened runtime"; exit 1; }

rm -rf "$DIST"; mkdir -p "$DIST"

if (( SKIP_NOTARIZE == 0 )); then
  step "Notarizing app"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait 2>&1 | tee "$DIST/notary-app.log"
  grep -q "status: Accepted" "$DIST/notary-app.log" || {
    ID=$(grep -m1 -E "^\s*id:" "$DIST/notary-app.log" | awk '{print $2}')
    [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE"
    echo "App notarization failed"; exit 1
  }
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
fi

step "Building DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Mic Check" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if (( SKIP_NOTARIZE == 0 )); then
  step "Notarizing DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 | tee "$DIST/notary-dmg.log"
  grep -q "status: Accepted" "$DIST/notary-dmg.log" || { echo "DMG notarization failed"; exit 1; }
  xcrun stapler staple "$DMG"

  step "Gatekeeper assessment"
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
else
  print -P "%F{yellow}Skipped notarization; this DMG will be blocked by Gatekeeper on other Macs.%f"
fi

step "Done"
ls -la "$DMG"
shasum -a 256 "$DMG"
