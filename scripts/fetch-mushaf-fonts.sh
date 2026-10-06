#!/usr/bin/env bash
# Restores the 604 Mushaf page fonts (QCF V4 with tajweed, 1441H print) into shared/quran/qcf4/
# and verifies every file against shared/quran/qcf4.sha256.
#
# Usage: scripts/fetch-mushaf-fonts.sh
# Downloads ~50 MB from Quran Foundation's font CDN. See shared/quran/README.md for the terms.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/shared/quran/qcf4"
manifest="$root/shared/quran/qcf4.sha256"
base="https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/woff2"

mkdir -p "$dest"
echo "Downloading 604 page fonts from Quran Foundation…"
seq 1 604 | xargs -P 6 -I{} curl -fsS --retry 3 -o "$dest/p{}.woff2" "$base/p{}.woff2"

(cd "$dest" && shasum -a 256 -c --quiet "$manifest")
echo "OK: $(ls "$dest" | wc -l | tr -d ' ') page fonts verified in shared/quran/qcf4/"
