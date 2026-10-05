#!/usr/bin/env bash
# Builds a DOS Boxer release: Release build, Developer ID signing (inside
# out), notarization, stapling, a ZIP, and its entry in appcast.xml (the
# Sparkle update feed). Publishing is left to you: the script prints the
# commands for the GitHub release and the appcast commit.
#
#   Scripts/release.sh            # version from project.yml (MARKETING_VERSION)
#   Scripts/release.sh --sign-only   # build and sign, no notarizing or feed (a test run)
#
# One-time setup:
#   1. Sparkle signing key (kept in your login keychain):
#        build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
#      then put the public key it prints into Sources/DOSBoxerApp/Info.plist
#      (SUPublicEDKey). Back the private key up: generate_keys -x <file>.
#   2. Notarization credentials (an app-specific password from
#      account.apple.com):
#        xcrun notarytool store-credentials DOSBoxer --apple-id <you> --team-id 5NAFWWC2WZ
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: WILLIAM J SPRY III (5NAFWWC2WZ)"
TEAM=5NAFWWC2WZ
NOTARY_PROFILE=DOSBoxer
REPO=cantcodewontcode/dos-boxer

VERSION=$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?/\1/p' project.yml | head -1)
BUILD=$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([^"]+)"?/\1/p' project.yml | head -1)
OUT="build/release/$VERSION"
DATA=build/ReleaseData
ZIP="DOS-Boxer-$VERSION.zip"
APP="$OUT/DOS Boxer.app"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'release: %s\n' "$1" >&2; exit 1; }

SIGN_ONLY=false
[ "${1:-}" = "--sign-only" ] && SIGN_ONLY=true

step "Checking setup for DOS Boxer $VERSION ($BUILD)"
security find-identity -v -p codesigning | grep -q "$IDENTITY" || fail "Developer ID certificate not found"
if ! $SIGN_ONLY; then
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "no notarization credentials; see the setup notes at the top of this script"
grep -q "SPARKLE_PUBLIC_KEY" Sources/DOSBoxerApp/Info.plist \
  && fail "SUPublicEDKey in Info.plist is still a placeholder; see the setup notes"
grep -q "^## \[$VERSION\]\|^## $VERSION" CHANGELOG.md || fail "CHANGELOG.md has no section for $VERSION"
fi
[ -z "$(git status --porcelain)" ] || echo "warning: uncommitted changes will be in this build"

step "Building"
Scripts/build-core.sh
xcodegen generate >/dev/null
xcodebuild -project DOSBoxer.xcodeproj -scheme "DOS Boxer" -configuration Release \
  -derivedDataPath "$DATA" build | grep -E "error:|\*\* BUILD" || true
[ -d "$DATA/Build/Products/Release/DOS Boxer.app" ] || fail "build failed"
rm -rf "$OUT" && mkdir -p "$OUT"
ditto "$DATA/Build/Products/Release/DOS Boxer.app" "$APP"

step "Signing"
sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/Frameworks/libDOSBoxerCore.dylib"
sign "$APP/Contents/Frameworks/DOSBoxerKit.framework"
# The emulator's dynamic CPU core needs to generate code
sign --entitlements Sources/DOSBoxerEngine/DOSBoxerEngine.entitlements "$APP/Contents/MacOS/DOS Boxer Engine"
sign "$APP"
codesign --verify --deep --strict "$APP" || fail "signature check failed"
if $SIGN_ONLY; then step "Signed (test run): $APP"; exit 0; fi

step "Notarizing (a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$OUT/notary.log"
grep -q "status: Accepted" "$OUT/notary.log" || fail "notarization failed; see $OUT/notary.log"
xcrun stapler staple "$APP"
spctl --assess --type execute "$APP" || fail "Gatekeeper rejected the app"
rm "$OUT/notarize.zip"
ditto -c -k --keepParent "$APP" "$OUT/$ZIP"

step "Signing the update"
SIGN_UPDATE=$DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
SIGNATURE=$("$SIGN_UPDATE" "$OUT/$ZIP")   # sparkle:edSignature="…" length="…"

step "Adding $VERSION to appcast.xml"
# Update notes (what Sparkle shows): the top of this version's CHANGELOG
# section, up to its first "###" heading. Lists become bullets, other lines
# paragraphs; **bold** is kept.
NOTES=$(awk -v v="$VERSION" '
  $0 ~ "^## \\[?"v"\\]?" { on = 1; next }
  on && /^##/ { exit }
  !on || /^[[:space:]]*$/ { next }
  { line = $0; while (match(line, /\*\*[^*]+\*\*/)) {
      line = substr(line, 1, RSTART - 1) "<b>" substr(line, RSTART + 2, RLENGTH - 4) "</b>" substr(line, RSTART + RLENGTH) } }
  /^[-*] / { sub(/^[-*] /, "", line); items = items "<li>" line "</li>"; next }
  { print "<p>" line "</p>" }
  END { if (items != "") print "<ul>" items "</ul>" }
' CHANGELOG.md)
ITEM="    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES]]></description>
      <enclosure url=\"https://github.com/$REPO/releases/download/v$VERSION/$ZIP\" type=\"application/octet-stream\" $SIGNATURE/>
    </item>"
if [ ! -f appcast.xml ]; then
  cat > appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>DOS Boxer</title>
    <!-- newest first -->
  </channel>
</rss>
EOF
fi
ITEM="$ITEM" python3 - <<'EOF'
import os
path = "appcast.xml"
text = open(path).read()
marker = "<!-- newest first -->"
text = text.replace(marker, marker + "\n" + os.environ["ITEM"], 1)
open(path, "w").write(text)
EOF

step "Done: $OUT/$ZIP"
cat <<EOF

To publish (in this order, so the download exists before the feed points at it):

  cd "$(pwd)" && gh release create v$VERSION "$OUT/$ZIP" --repo $REPO --title "DOS Boxer $VERSION" --notes-file <(awk -v v="$VERSION" '\$0 ~ "^## \\\\[?"v"\\\\]?" {on=1; next} on && /^## / {exit} on' CHANGELOG.md)
  cd "$(pwd)" && git add appcast.xml && git commit -m "Release $VERSION" && git push
EOF
