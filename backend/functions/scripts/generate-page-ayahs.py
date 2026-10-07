#!/usr/bin/env python3
"""Writes src/pageAyahs.json: each Mushaf page's first and last ayah (numbered 0..6235 in Quran order), from the
1441H layout and glyph data in shared/quran (the same data the apps draw from). It holds no Quran text.

Run from backend/functions:  python3 scripts/generate-page-ayahs.py
"""
import json
import sqlite3
from pathlib import Path

quran = Path(__file__).resolve().parents[3] / "shared" / "quran"
official = json.load(open(quran / "kfgqpc" / "hafs_smart_v8.json"))
index = {f"{a['sura_no']}:{a['aya_no']}": i for i, a in enumerate(official)}
words = json.load(open(quran / "qul" / "qpc-v4.json"))
ayah_of_word = {w["id"]: index[f"{w['surah']}:{w['ayah']}"] for w in words.values()}

pages = {}
db = sqlite3.connect(quran / "qul" / "qpc-v4-tajweed-15-lines.db")
for page, first, last in db.execute("SELECT page_number, first_word_id, last_word_id FROM pages WHERE line_type = 'ayah'"):
    ayahs = [ayah_of_word[w] for w in range(first, last + 1)]
    low, high = pages.get(page, (10**9, -1))
    pages[page] = (min(low, min(ayahs)), max(high, max(ayahs)))

table = [list(pages[p]) for p in range(1, 605)]
assert table[0] == [0, 6] and table[-1][1] == 6235
out = Path(__file__).resolve().parents[1] / "src" / "pageAyahs.json"
out.write_text(json.dumps(table, separators=(",", ":")))
print(f"wrote {out}")
