# Quran data

The Quran text and Mushaf layout used by every Aqra app. **Nothing in this folder may be edited by hand.**
Files are kept exactly as published; the iOS tests check every file against the SHA-256 values below.

## Sources

### `kfgqpc/` — King Fahd Glorious Quran Printing Complex (official)

From the Complex's developer platform, [qurancomplex.gov.sa/quran-dev](https://qurancomplex.gov.sa/quran-dev/),
package `kfgqpc_hafs_smart_4.zip` (Hafs, data v8, 2022-06-30).

| File | SHA-256 |
|---|---|
| `hafs_smart_v8.json` — all 6236 ayat with surah, juz', page and line data | `a272a119a4272f10cf42d8e389857b469183d3217fa23aa38b6a7331d0ac4aa2` |
| `HafsSmart_08.ttf` — KFGQPC Hafs Smart font v0.08 | `18c5641d1a9433499660122eccc6388bf89b9c8b752e5957aff41a2bed2c976b` |
| `read.me` — the Complex's notes for the data | `b40fe4086f706029573c2cc5575b561e1652729c44d4e296be0d9e3bda8d0890` |

**License:** the font's end-user license allows free use, copying and distribution; it must not be sold,
modified, altered, translated or reverse engineered. The Complex states this data is for ayah-level display,
not for reproducing full Mushaf pages.

### `qul/` — Quranic Universal Library (Tarteel) — ⚠️ provisional

From [qul.tarteel.ai](https://qul.tarteel.ai), downloaded with a QUL account on 2026-10-06.

| File | SHA-256 |
|---|---|
| `qpc-v2-15-lines.db` — "KFGQPC V2 layout (1421H print)": 604 pages × 15 lines | `e4df98f35dd3b8927ff096337c8739e0f0b12c8ba622834c345eaa4c3e28dd8c` |
| `qpc-v2.json` — "QPC V2 Glyph – Word by Word": each word's glyph in the page fonts | `40964a1b7932e9a69e0dfc0d58dce3b73e30a803febda119fd6828bcb75fac98` |

**License:** not stated on these resources; QUL's FAQ says commercial use is allowed but some resources require
attribution. **Must be confirmed before release.**

### `qcf2/` — Mushaf page fonts (QCF V2, 1421H print) — ⚠️ provisional

Not committed to git (~205 MB). Restore and verify with `scripts/fetch-mushaf-fonts.sh`, which downloads
`2013.zip` (MD5 `8570796a7d683b71c17ff17d923e6da7`) from [archive.org/details/qcf.fonts](https://archive.org/details/qcf.fonts)
and checks each font against `qcf2.sha256` (SHA-256 `1897276392759f73839ee1b1255c4b6bf97c6c36e108ed6172d560f2f09b34c3`).

These fonts were uploaded to the Internet Archive by an individual, not by the Complex. They carry no digital
signature, are labelled "Test Font, KFGQPC", and were saved with FontForge. **They must be replaced with an
official copy from the Complex before the App Store release.**

## Verification (2026-10-06)

The QUL layout and glyphs were checked against the Complex's official data and the page fonts:

- All 6236 ayat present; every ayah on the same page as the official data; every word on exactly one line;
  every glyph present in its page font.
- 8787 of 8790 justified lines fill the same width within 3% (88% within 1%).
- Line numbers differ from the official data by one line on 355 pages — the official data most likely follows a
  later printing than 1421H. Pages match exactly.
- 60 ayat have one fewer word than the official Imla'i text, all from Uthmani joined words such as «أَوَلَا».
- **For a hafiz to review against the printed Mushaf:** page 254 lines 6–7, page 575 line 12.
