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
| `qpc-v4-tajweed-15-lines.db` — "KFGQPC V4 layout (1441H print)": 604 pages × 15 lines | `4b3fb1cbe8dff749ab0173c4b86cb40fe3c48dd072f41d3c7e715654a9f843cd` |
| `qpc-v4.json` — "V4 Glyphs (With Tajweed) – Word by word": each word's glyph in the page fonts (byte-identical to QUL's V2 glyph file) | `40964a1b7932e9a69e0dfc0d58dce3b73e30a803febda119fd6828bcb75fac98` |
| `QCF_SurahHeader_COLOR-Regular.ttf` — "Surah header font": each surah's framed calligraphic title (name field: "King Fahad Complex, All rights reserved.") | `de261a309bdd42262e1a268d5ead56b6ea8366cd59124baedea3903561d7370b` |
| `surah-header-ligatures.json` — which character draws each surah's header | `c4480a1fb616685421ada1f9cbd36187c1c27c01d8d78d27a866858fdaf5c4f7` |
| `ayah-themes.db` — "Ayah theme" (credited to "Ayah by Ayah"): English topic summaries over ayah ranges; **a temporary stand-in for the topic colors** until a published thematic Mushaf's division can be used with permission | `b3c20c4fab472586904543ed12c87e2ac616ce629ac18a125357408e50927a42` |

**License:** not stated on these resources; QUL's FAQ says commercial use is allowed but some resources require
attribution. **Must be confirmed before release.**

`ayah-themes.db` lists each of its 1,049 sections twice and leaves 36 ayat outside any section (al-Baqarah 2:134,
Ghafir 40:61, al-Qamar 54:45–55, ar-Rahman 55:56–78). Aqra colors each of those four gaps as a section of its own,
which keeps every boundary the source draws. Its scholarly source isn't stated, so it must be replaced before release.

### `qcf4/` — Mushaf page fonts with tajweed (QCF V4, 1441H print) — ⚠️ provisional

Not committed to git (~50 MB). Restore and verify with `scripts/fetch-mushaf-fonts.sh`, which downloads the 604
fonts from Quran Foundation's font CDN (`verses.quran.foundation/fonts/quran/hafs/v4/colrv1/woff2/pN.woff2`) and
checks each against `qcf4.sha256` (SHA-256 `7d2034c4e65b69b01337be804c9fb5934dee6b03b1b2e05f4fe9ec69810f28e2`).

Each font is named `QCF4NNN_COLOR` ("King Fahad Complex, All rights reserved."). It holds the page's words as plain
outlines, plus color layers (COLR version 0) and six palettes (CPAL) for tajweed: light, dark and sepia, with and
without tajweed colors. Aqra reads the fonts as they are and never modifies them.

**Terms:** Quran Foundation allows bundling these fonts in an app if the developer keeps an active account in its
Developer Console and credits Quran Foundation in the app. **The account and the credit are needed before release.**

**Proofreading:** QUL lists these fonts as disabled "while we're proofreading them". Aqra's own team must proofread
the text and the tajweed colors before release. Automated checks (2026-10-06) found:

- Every page font has every glyph its page needs, and every word has a plain outline.
- The color layers don't always match the plain outlines. Over 88,206 colored glyphs on 578 pages:
  2,166 add hairline boxes or ellipses around marks; 32 are shifted from the plain outline; 2 lack part of
  the word, including the pause sign on word 10 of al-Baqarah 2:268. quran.com shows the same layers.
  **Aqra therefore draws every word from its plain outline and uses the color layers only to tint it.**
- 8 glyphs are intentionally empty: the second character of the disjointed letters on pages 208, 249, 262, 377,
  453, 518 and 564, whose first glyph draws the whole word.
- One word has no width of its own: the pause sign after word 4 of Ghafir 40:77 (page 475, line 14), which sits
  over the word before it.

## Verification (2026-10-06)

The 1441H layout was checked against the Complex's official data (`kfgqpc/hafs_smart_v8.json`):

- All 6236 ayat present; every ayah on the same page, starting and ending on the same lines, as the official data
  (`everyAyahEndsWhereTheOfficialDataSays` keeps this checked). The earlier 1421H layout differed on 869 ayat
  across 355 pages: the official data follows the 1441H print.
- Every word on exactly one line, and every glyph present in its page font.
- Where the prints differ, the 1441H fonts follow the official text: for example, the 1441H print drops the
  pause sign after word 5 of Maryam 19:38, and so do the official data and the V4 font.
- **For a hafiz to review against the printed Mushaf:** all 604 pages, with and without tajweed colors.
