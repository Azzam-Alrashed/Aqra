#!/usr/bin/env bash
# Restores the 604 Mushaf page fonts (QCF V2, 1421H print) into shared/quran/qcf2/
# and verifies every file against shared/quran/qcf2.sha256.
#
# Usage: scripts/fetch-mushaf-fonts.sh [path/to/2013.zip]
# Without an argument it downloads 2013.zip (135 MB) from the Internet Archive.
# PROVISIONAL source — see shared/quran/README.md.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/shared/quran/qcf2"
manifest="$root/shared/quran/qcf2.sha256"
expected_md5="8570796a7d683b71c17ff17d923e6da7"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

zip="${1:-}"
if [[ -z "$zip" ]]; then
  zip="$work/2013.zip"
  echo "Downloading 2013.zip from the Internet Archive…"
  curl -fSL -o "$zip" "https://archive.org/download/qcf.fonts/2013.zip"
fi

actual_md5="$(md5 -q "$zip" 2>/dev/null || md5sum "$zip" | cut -d' ' -f1)"
if [[ "$actual_md5" != "$expected_md5" ]]; then
  echo "MD5 mismatch for 2013.zip: $actual_md5 (expected $expected_md5)" >&2
  exit 1
fi

unzip -q "$zip" 'QCF2BSMLfonts/QCF2[0-9][0-9][0-9].ttf' -d "$work"
mkdir -p "$dest"
cp "$work"/QCF2BSMLfonts/QCF2[0-9][0-9][0-9].ttf "$dest/"

(cd "$dest" && shasum -a 256 -c --quiet "$manifest")
echo "OK: $(ls "$dest" | wc -l | tr -d ' ') page fonts verified in shared/quran/qcf2/"
