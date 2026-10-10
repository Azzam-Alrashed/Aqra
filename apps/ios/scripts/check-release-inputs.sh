#!/bin/bash
# Release builds must carry what isn't in git: the Firebase config and the 604 Mushaf page fonts. Without this
# check a Release build without them ships silently, with accounts off and a Mushaf that can't load.
# Debug builds pass, so tests and worktrees without the config keep working. Runs as an Xcode build phase.
set -u
[ "${CONFIGURATION:-}" = "Release" ] || exit 0

status=0
plist="$SRCROOT/Firebase/GoogleService-Info.plist"
if [ ! -f "$plist" ]; then
  echo "error: Firebase/GoogleService-Info.plist is missing. A Release build ships with accounts and backup off. Restore it with scripts/fetch-firebase-config.sh." >&2
  status=1
fi

fonts="$SRCROOT/../../shared/quran/qcf4"
manifest="$SRCROOT/../../shared/quran/qcf4.sha256"
count=$(find "$fonts" -maxdepth 1 -name 'p*.woff2' 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" != "604" ]; then
  echo "error: shared/quran/qcf4 has $count of the 604 Mushaf page fonts. Restore them with scripts/fetch-mushaf-fonts.sh." >&2
  status=1
elif ! (cd "$fonts" && shasum -a 256 -c --quiet "$manifest" >/dev/null 2>&1); then
  echo "error: shared/quran/qcf4 doesn't match shared/quran/qcf4.sha256. Restore the fonts with scripts/fetch-mushaf-fonts.sh." >&2
  status=1
fi
exit $status
