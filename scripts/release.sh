#!/bin/zsh
# Build, sign, notarize, staple, and package Mic Check as a DMG.
#
#   scripts/release.sh                 build, notarize, DMG, appcast (nothing published)
#   scripts/release.sh --publish       ...then create the GitHub release and push appcast.xml
#   scripts/release.sh --skip-notarize build + DMG + appcast only, for testing the pipeline
#
# Sparkle: the EdDSA private key lives in the login keychain (generate_keys); the public key is
# SUPublicEDKey in project.yml. appcast.xml at the repo root is what shipped apps poll.
#
# One-time credential setup (app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials "MicCheck-Notary" --apple-id "you@example.com" --team-id XQL374L3KC
set -euo pipefail

cd "$(dirname "$0")/.."
PROFILE="MicCheck-Notary"
IDENTITY="Developer ID Application: UJU Pty Ltd (XQL374L3KC)"
SKIP_NOTARIZE=0
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --publish) PUBLISH=1 ;;
  esac
done
REPO="bryceadams/mic-check-mac"
SPARKLE_BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"

VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
BUILD_NUMBER=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
DIST="dist"
APP="build/Build/Products/Release/Mic Check.app"
DMG="$DIST/Mic-Check-$VERSION.dmg"
ZIP="$DIST/Mic-Check-$VERSION.zip"

step() { print -P "\n%F{cyan}==> $1%f"; }

step "Generating project and building Release $VERSION ($BUILD_NUMBER)"
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  echo "v$VERSION is already published; bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml"; exit 1
fi
grep -q "^## $VERSION\b" CHANGELOG.md || { echo "CHANGELOG.md has no '## $VERSION' section"; exit 1; }
xcodegen generate >/dev/null
xcodebuild -project MicCheck.xcodeproj -scheme MicCheck -resolvePackageDependencies -derivedDataPath build >/dev/null 2>&1
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

step "Release notes and appcast"
# Extract this version's CHANGELOG section as Markdown (for GitHub) and HTML (embedded in the appcast).
NOTES_MD="$DIST/notes.md"
awk -v v="$VERSION" '/^## /{p=($2==v)} p && !/^## /' CHANGELOG.md | sed '/./,$!d' > "$NOTES_MD"
python3 - "$NOTES_MD" "$DIST/Mic-Check-$VERSION.html" <<'PY'
import html, sys
lines = open(sys.argv[1]).read().splitlines()
out, in_list = [], False
for l in lines:
    if l.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        out.append("<li>" + html.escape(l[2:]) + "</li>")
    else:
        if in_list: out.append("</ul>"); in_list = False
        if l.strip(): out.append("<p>" + html.escape(l) + "</p>")
if in_list: out.append("</ul>")
open(sys.argv[2], "w").write("\n".join(out) + "\n")
PY
[[ -f appcast.xml ]] && cp appcast.xml "$DIST/appcast.xml"   # keep earlier versions in the feed
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --embed-release-notes -o "$DIST/appcast.xml" "$DIST" | grep -vE "^\s*$" || true
cp "$DIST/appcast.xml" appcast.xml
grep -E "sparkle:version|sparkle:shortVersionString|enclosure" appcast.xml | tail -3

if (( PUBLISH == 1 )); then
  (( SKIP_NOTARIZE == 0 )) || { echo "Refusing to publish an unnotarized build"; exit 1; }
  step "Publishing v$VERSION"
  git add appcast.xml CHANGELOG.md project.yml
  git diff --cached --quiet || git commit -q -m "Release $VERSION"
  git push -q origin main
  gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "Mic Check $VERSION" --notes-file "$NOTES_MD"
  gh release view "v$VERSION" --repo "$REPO" --json url -q .url
fi

step "Done"
ls -la "$DMG"
shasum -a 256 "$DMG"
