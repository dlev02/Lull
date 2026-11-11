# Releasing Lull

A release is a Developer ID signed, notarized DMG and ZIP attached to a GitHub release, plus a signed update feed (`appcast.xml`) at the repository root on `main`. Installed copies read the feed from `https://raw.githubusercontent.com/dlev02/Lull/main/appcast.xml`.

## Steps

1. Set the version and a higher build number on the Lull target. Sparkle compares the build number, so one that doesn't rise never reaches anyone.

   ```sh
   xcrun xcodeproj setting set --target Lull MARKETING_VERSION 0.1.1
   xcrun xcodeproj setting set --target Lull CURRENT_PROJECT_VERSION 2
   ```

2. Add the version's section to `CHANGELOG.md`, in the form `## 0.1.1 — 2026-11-12`. Its text becomes the release notes in the update window, so write it for people.
3. Commit. The script refuses to run with uncommitted changes, so the release is what's in the repository.
4. Run `script/make_release.sh <version>`. It checks this Mac first (certificate, Sparkle key, version, build number against the published feed), builds, signs from the inside out with hardened runtime and secure timestamps, notarizes and staples the app, makes the ZIP, makes, signs, notarizes and staples the DMG, writes checksums to `dist/release/<version>`, and writes the signed `appcast.xml` at the repository root. It uploads nothing.
5. Create the GitHub release tagged `v<version>` and attach the DMG, the ZIP and their `.sha256` files. Use the changelog section as the notes.
6. Only then commit and push `appcast.xml`. Pushing it first would point installed copies at a download that doesn't exist yet.
7. Download the published DMG and check it against its checksum. Open it and confirm the drag-to-Applications window looks right.

## Before the first release, and after any change to updating

Install the previous release, publish the new one, and watch the installed copy find it, download it and relaunch into the new version. Check `lull log` for the `[update]` lines. A release that can't update is worse than no release.

### Testing an update without publishing it

To prove a build can be updated to before it goes out, or when a firewall on the test Mac holds the download from GitHub, serve the update from the same Mac:

```sh
mkdir /tmp/feed && cp dist/release/<version>/Lull-<version>.zip /tmp/feed/
dist/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast --account lull \
  --download-url-prefix http://127.0.0.1:8765/ -o /tmp/feed/appcast.xml /tmp/feed
(cd /tmp/feed && python3 -m http.server 8765 --bind 127.0.0.1) &
lull quit
defaults write io.github.dlev02.lull SUFeedURL http://127.0.0.1:8765/appcast.xml
open -g /Applications/Lull.app
lull update check      # then `lull update` until "ready" is true
lull update install    # relaunches into the new version
defaults delete io.github.dlev02.lull SUFeedURL
```

The update is still verified against the signing key, so this exercises everything except GitHub's hosting. If `lull log` shows "An error occurred while downloading the update" after exactly a minute, something on the Mac is holding the connection to `github.com` or `release-assets.githubusercontent.com`; a firewall app such as Little Snitch waits for an answer to its prompt.

## What the script needs on this Mac

- The Developer ID Application certificate, in the login Keychain. The team is set at the top of the script, or with `LULL_TEAM`.
- The notarization key stored by `asc auth login`. No credentials are kept in this repository.
- The Sparkle signing key (below).
- `uvx`, which runs `dmgbuild` for the install window. The window's layout is `script/dmg_settings.py` and its background is `Resources/DMG/background.png`, drawn by `script/make_dmg_background.swift`.

## Update signing key

Updates are signed with an EdDSA key made by Sparkle's `generate_keys --account lull`. The private half is in the login Keychain and is read by `generate_appcast`; macOS may ask once to allow that. The public half is `SUPublicEDKey` in `App/Info.plist`. Don't use Sparkle's default account: that key belongs to another project.

Keep a backup outside this repository, made with `generate_keys --account lull -x <file>`. Lose this key and every installed copy needs a download by hand, because the app requires a signed feed and nothing falls back to accepting an unsigned one. Restore with `generate_keys --account lull -f <file>`.

To confirm a backup matches the Keychain, sign the same file both ways and compare; EdDSA signatures are deterministic:

```sh
sign_update --account lull some-file
sign_update -f <backup-file> some-file
```

## The app icon

`script/make_icon.swift` draws the icon. `swiftc -O script/make_icon.swift -o /tmp/make_icon`, then `/tmp/make_icon App/Assets.xcassets/AppIcon.appiconset/Icon.png 2B2A6B E8866A FFC38A`.
