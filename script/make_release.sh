#!/bin/zsh
# Builds a Lull release in dist/release/<version>: a Developer ID signed, notarized and
# stapled DMG and ZIP, SHA-256 checksums, and a signed Sparkle appcast.xml at the
# repository root that points at the release's tag. It uploads nothing.
# See docs/RELEASING.md.
#
#   script/make_release.sh 0.1.0
#
# Set MARKETING_VERSION and a higher CURRENT_PROJECT_VERSION on the Lull target first,
# add the version's section to CHANGELOG.md, and commit. Needs, on this Mac:
#   - The Developer ID Application certificate for the team below, in the login Keychain.
#   - The notarization key that `asc auth login` stores in the keychain.
#   - The Sparkle private key, in the login Keychain under the account `lull`. macOS may
#     ask once to let generate_appcast read it. Lose this key and every installed copy
#     needs a download by hand.
#   - uvx, to run dmgbuild for the install window.
set -euo pipefail

cd "${0:A:h:h}"

die() { print -u2 "make_release: $*"; exit 1; }
step() { print "\n== $*"; }

version="${1:-}"
[[ "$version" =~ '^[0-9]+(\.[0-9]+)+$' ]] || die "usage: make_release.sh <version>, for example 0.1.0"

team="${LULL_TEAM:-7BVMD7TA97}"
account=lull
tag="v$version"
repo=https://github.com/dlev02/Lull
feed=https://raw.githubusercontent.com/dlev02/Lull/main/appcast.xml
out="dist/release/$version"
project=Lull.xcodeproj/project.xcproj
dmg="Lull-$version.dmg"
zip="Lull-$version.zip"

setting() { sed -n "s/.*\"$1\": \"\\([^\"]*\\)\".*/\\1/p" "$project" | head -1; }
notes() { sed -n "/^## $version /,/^## /p" CHANGELOG.md | sed '1d;$d'; }

# Everything that needs setting up on this Mac fails here, not after a long build.
git diff --quiet HEAD -- || die "tracked files have changes: commit first, so the release is what's in the repository"
[[ "$(setting MARKETING_VERSION)" == "$version" ]] || die "MARKETING_VERSION isn't $version"
build=$(setting CURRENT_PROJECT_VERSION)
[[ "$build" =~ '^[0-9]+$' ]] || die "the build number must be a whole number, not $build"
print -r -- "$(notes)" | grep -q '[^[:space:]]' || die "CHANGELOG.md has no section for $version"
[[ "$(plutil -extract SUFeedURL raw App/Info.plist)" == "$feed" ]] || die "SUFeedURL isn't $feed"
(( $+commands[uvx] )) || die "uvx isn't installed; it runs dmgbuild"

identity=$(security find-identity -v -p codesigning | awk -v team="($team)" '/Developer ID Application/ && index($0, team) { print $2; exit }')
[[ -n "$identity" ]] || die "no Developer ID Application certificate for team $team in the Keychain"

# Sparkle compares CFBundleVersion, so a build number that doesn't rise never reaches anyone.
published=$(curl -fsL "$feed" 2>/dev/null | sed -n 's|.*<sparkle:version>\([0-9]*\)</sparkle:version>.*|\1|p' | sort -n | tail -1 || true)
if [[ -n "$published" ]] && (( build <= published )); then
  die "build $build isn't higher than the published build $published"
fi

rm -rf "$out"
mkdir -p "$out"
app="$out/Lull.app"

step "Building"
built=""
if (( $+commands[bitrig] )); then
  # Inside Bitrig, use its build system and cache.
  built=$(bitrig build -destination 'generic/platform=macOS' -configuration Release 2>"$out/build.log" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["builds"][0]["apps"][0])' 2>/dev/null || true)
fi
if [[ -z "$built" || ! -d "$built" ]]; then
  xcodebuild -project Lull.xcodeproj -scheme Lull -configuration Release -derivedDataPath dist/DerivedData \
    CODE_SIGN_IDENTITY=- build >>"$out/build.log" 2>&1 || { tail -30 "$out/build.log"; die "the build failed; see $out/build.log"; }
  built=dist/DerivedData/Build/Products/Release/Lull.app
fi
ditto "$built" "$app"
[[ "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" == "$version" ]] || die "the built app isn't version $version"
[[ ! -e "$app/Contents/MacOS/Lull.debug.dylib" ]] || die "this is a debug build"

sparkle_bin=$(find dist/DerivedData "${built:h:h:h:h:h}/DerivedData" -type d -path '*artifacts/sparkle/Sparkle/bin' 2>/dev/null | head -1)
[[ -n "$sparkle_bin" ]] || die "Sparkle's tools weren't found beside the build"
public_key=$("$sparkle_bin/generate_keys" --account "$account" -p) || die "no Sparkle key for account $account in the Keychain"
[[ "$public_key" == "$(plutil -extract SUPublicEDKey raw "$app/Contents/Info.plist")" ]] || die "the Keychain's Sparkle key doesn't match SUPublicEDKey"

step "Signing with Developer ID"
script/sign_app.sh "$app" --force --options runtime --timestamp --sign "$identity"
codesign --verify --deep --strict "$app" || die "the app's signature doesn't verify"
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for code in "$app" "$sparkle" "$sparkle/Autoupdate" "$sparkle/Updater.app" "$sparkle"/XPCServices/*.xpc(N); do
  details=$(codesign -dvv "$code" 2>&1)
  [[ "$details" == *"Authority=Developer ID Application"* && "$details" == *"TeamIdentifier=$team"* ]] || die "$code isn't signed with team $team's Developer ID"
  [[ "$details" == *"(runtime)"* ]] || die "$code has no hardened runtime"
  [[ "$details" == *"Timestamp="* ]] || die "$code has no secure timestamp"
done
codesign -d --entitlements - "$app" 2>/dev/null | grep -q 'automation.apple-events' || die "the app lost its Automation entitlement"
if strings "$app/Contents/MacOS/Lull" | grep -q '/Users/'; then die "the executable contains a local path"; fi

notarize() {
  local result="$out/notary-${1:t}.json"
  asc notarization submit --file "$1" --wait --output json >"$result" || true
  local verdict; verdict=$(plutil -extract data.attributes.status raw "$result" 2>/dev/null || print unknown)
  if [[ "$verdict" != "Accepted" ]]; then
    local id; id=$(plutil -extract data.id raw "$result" 2>/dev/null || print "")
    [[ -n "$id" ]] && asc notarization log --id "$id" || true
    die "notarizing ${1:t} came back $verdict"
  fi
}

step "Notarizing the app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/submission.zip"
notarize "$out/submission.zip"
rm "$out/submission.zip"
xcrun stapler staple -q "$app"
xcrun stapler validate -q "$app"
spctl --assess --type execute "$app" || die "Gatekeeper refuses the stapled app"

step "Making the ZIP"
# ditto keeps the framework's symlinks, which a plain zip would break.
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/$zip"

step "Making and notarizing the DMG"
# The install window: the app on the left, Applications on the right, an arrow between.
uvx dmgbuild -s script/dmg_settings.py -D app="$app" -D background=Resources/DMG/background.png Lull "$out/$dmg" >"$out/dmg.log" 2>&1 \
  || { tail -20 "$out/dmg.log"; die "dmgbuild failed; see $out/dmg.log"; }
codesign --sign "$identity" --timestamp "$out/$dmg"
notarize "$out/$dmg"
xcrun stapler staple -q "$out/$dmg"
xcrun stapler validate -q "$out/$dmg"
spctl --assess --type open --context context:primary-signature "$out/$dmg" || die "Gatekeeper refuses the DMG"

step "Signing the appcast"
# Only the ZIP goes in: Sparkle installs from it, and the DMG is for people. The changelog
# section becomes the release notes. The feed lives at the repository root on main, so a
# release can never be published without it; push it only after the release's files are up.
stage="$out/appcast-stage"
mkdir "$stage"
ln "$out/$zip" "$stage/$zip"
print -r -- "$(notes)" >"$stage/${zip:r}.md"
"$sparkle_bin/generate_appcast" --account "$account" --embed-release-notes --maximum-deltas 0 \
  --download-url-prefix "$repo/releases/download/$tag/" --link "$repo/releases/tag/$tag" \
  -o "$PWD/appcast.xml" "$stage" | tee "$out/appcast.log"
rm -rf "$stage"
xmllint --noout appcast.xml
grep -q "url=\"$repo/releases/download/$tag/$zip\"" appcast.xml || die "the appcast's enclosure doesn't point at $tag"
grep -q "<sparkle:version>$build</sparkle:version>" appcast.xml || die "the appcast doesn't offer build $build"
grep -q 'sparkle:edSignature=' appcast.xml || die "the download isn't signed in the appcast"
grep -q 'sparkle-signatures:' appcast.xml || die "the appcast itself isn't signed, and the app requires that"

step "Checksums"
(cd "$out" && shasum -a 256 "$dmg" >"$dmg.sha256" && shasum -a 256 "$zip" >"$zip.sha256" && cat ./*.sha256)

print "\nReady in $out. Nothing has been uploaded. To publish:"
print "  1. Create the release tagged $tag with: $dmg  $dmg.sha256  $zip  $zip.sha256"
print "  2. Then commit and push appcast.xml to main. Installed copies see the update once it is there."
