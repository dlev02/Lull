#!/bin/bash
# Signs a Lull.app from the inside out with the given codesign options: Sparkle's
# helpers first, then the framework, then the app with its entitlements.
# No --deep: it would apply one set of options to everything.
#   script/sign_app.sh path/to/Lull.app --force --sign IDENTITY [--options runtime] [--timestamp]
set -euo pipefail
app="$1"; shift
here="$(cd "$(dirname "$0")/.." && pwd)"
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for helper in "$sparkle/XPCServices/Installer.xpc" "$sparkle/XPCServices/Downloader.xpc" "$sparkle/Autoupdate" "$sparkle/Updater.app"; do
  if [ -e "$helper" ]; then
    codesign "$@" --preserve-metadata=entitlements "$helper"
  fi
done
codesign "$@" "$app/Contents/Frameworks/Sparkle.framework"
codesign "$@" --entitlements "$here/App/Lull.entitlements" "$app"
