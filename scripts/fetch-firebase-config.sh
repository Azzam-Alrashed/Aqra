#!/usr/bin/env bash
# Restores the iOS app's Firebase config into apps/ios/Firebase/GoogleService-Info.plist.
#
# Usage: scripts/fetch-firebase-config.sh
# Needs the Firebase CLI, signed in with access to the aqra-quran project. Without the file the app still
# builds and runs, with accounts and backup turned off.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_id="1:768522165585:ios:b5318d9c6a6713629ec770"

dest="$root/apps/ios/Firebase/GoogleService-Info.plist"
rm -f "$dest"
firebase apps:sdkconfig IOS "$app_id" --project aqra-quran -o "$dest"
echo "OK: apps/ios/Firebase/GoogleService-Info.plist"
