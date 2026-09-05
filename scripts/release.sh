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
APP="build/Build/Products/Release/Mic Check.app"
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
RW_DMG="$DIST/rw.dmg"
MOUNT="/Volumes/Mic Check"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# Build read-write first so the Finder window layout and volume icon can be set, then compress.
hdiutil create -volname "Mic Check" -srcfolder "$STAGE" -ov -format UDRW -quiet "$RW_DMG"
rm -rf "$STAGE"
hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT" -nobrowse -quiet
# Finder layout first. Do not use Finder's "update" here: it clears the volume icon set below.
osascript <<APPLESCRIPT || echo "Finder layout skipped (automation permission?)"
tell application "Finder"
  tell disk "Mic Check"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 200, 960, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set position of item "Mic Check.app" of container window to {150, 170}
    set position of item "Applications" of container window to {410, 170}
    close
    open
    delay 1
    close
  end tell
end tell
APPLESCRIPT
# Volume icon: the icns at the root plus the custom-icon flag on the root directory.
cp scripts/dmg/VolumeIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -quiet -o "$DMG"
rm -f "$RW_DMG"
# Give the .dmg file itself the icon for local copies (resource fork; does not survive a web download).
# Work on a temp copy: sips -i writes an icon resource into the file it is given.
if command -v Rez >/dev/null 2>&1; then
  ICON_TMP=$(mktemp -d)
  cp scripts/dmg/VolumeIcon.icns "$ICON_TMP/icon.icns"
  if sips -i "$ICON_TMP/icon.icns" >/dev/null 2>&1 && DeRez -only icns "$ICON_TMP/icon.icns" > "$ICON_TMP/icon.rsrc" 2>/dev/null; then
    Rez -append "$ICON_TMP/icon.rsrc" -o "$DMG" && SetFile -a C "$DMG" || true
  fi
  rm -rf "$ICON_TMP"
fi
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
