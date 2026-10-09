#!/usr/bin/env python3
"""Turns the iOS app's string catalog into Android string resources, so both apps say the same thing.

    python3 apps/android/tools/import-ios-strings.py

Reads apps/ios/Aqra/Localizable.xcstrings (English keys, Arabic translations) and writes
apps/android/app/src/main/res/values/strings_ios.xml and values-ar/strings_ios.xml. Run it again whenever the
catalog changes. Each string's resource name is made from its English key (see `name`); a key already imported keeps
the name it has, so a new key whose name would clash takes a new one rather than renaming the old. Strings only
Android needs live in strings.xml, which this never touches.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CATALOG = ROOT / "apps/ios/Aqra/Localizable.xcstrings"
RES = ROOT / "apps/android/app/src/main/res"
LANGUAGES = {"en": "values", "ar": "values-ar"}
ARABIC_QUANTITIES = ["zero", "one", "two", "few", "many", "other"]
JAVA_KEYWORDS = set("""abstract assert boolean break byte case catch char class const continue default do double else enum
extends final finally float for goto if implements import instanceof int interface long native new package private
protected public return short static strictfp super switch synchronized this throw throws transient try void volatile
while true false null""".split())
SPECIFIER = re.compile(r"%(?:(\d+)\$)?(#@\w+@|lld|ld|d|@|f|\.\d+f)")


def name(key: str) -> str:
    """A resource name from an English key: «%lld pages from %@» → n_pages_from_s, «Sign out?» → sign_out_q."""
    text = SPECIFIER.sub(lambda m: " s " if m.group(2) == "@" else " n ", key)
    words = re.sub(r"[^a-z0-9]+", " ", text.lower().replace("'", "").replace("?", " q ")).split()
    slug = "_".join(words[:10]) or "empty"
    if slug in JAVA_KEYWORDS:
        slug += "_action"
    return ("s_" + slug) if slug[0].isdigit() else slug


def android_format(value: str, positional: bool) -> str:
    """iOS format specifiers as Android's: %lld → %d, %@ → %s, numbered when there's more than one."""
    counter = 0

    def replace(match):
        nonlocal counter
        counter += 1
        index = match.group(1) or str(counter)
        kind = "s" if match.group(2) == "@" else "d"
        return f"%{index}${kind}" if positional else f"%{kind}"

    return SPECIFIER.sub(replace, value)


def escape(value: str) -> str:
    value = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    value = value.replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"').replace("\n", "\\n")
    if value[:1] in "@?":
        value = "\\" + value
    return value


def count_args(key: str) -> int:
    return len(SPECIFIER.findall(key))


def unit(localization):
    return localization.get("stringUnit", {}).get("value")


def entries(key: str, entry: dict, language: str):
    """The resource for one key in one language: ("string", text) or ("plurals", {quantity: text})."""
    localization = entry.get("localizations", {}).get(language)
    args = count_args(key)
    positional = args > 1
    if localization is None:
        if language != "en":
            return None
        return ("string", android_format(key, positional))
    plural = localization.get("variations", {}).get("plural")
    if plural:
        return ("plurals", {q: android_format(v["stringUnit"]["value"], positional) for q, v in plural.items()})
    substitutions = localization.get("substitutions")
    if substitutions:
        # One plural inside a sentence (%1$#@pages@ from %2$@): the whole sentence for each quantity.
        (sub_name, sub), = substitutions.items()
        template = unit(localization)
        forms = {}
        for quantity, variation in sub["variations"]["plural"].items():
            text = variation["stringUnit"]["value"].replace("%arg", f"%{sub['argNum']}$lld")
            sentence = template.replace(f"%{sub['argNum']}$#@{sub_name}@", text)
            forms[quantity] = android_format(sentence, True)
        return ("plurals", forms)
    value = unit(localization)
    return None if value is None else ("string", android_format(value, positional))


def comment(key: str) -> str:
    """The comment above each resource: its key, as the file writes it."""
    return escape(key).replace("--", "- -")


def existing_names() -> dict:
    """The names already given, by their key's comment, from the English file written last time."""
    path = RES / LANGUAGES["en"] / "strings_ios.xml"
    if not path.exists():
        return {}
    found = re.findall(r'<!-- (.*?) -->\n\s*<(?:string|plurals) name="([^"]+)"', path.read_text())
    return dict(found)


def main():
    catalog = json.loads(CATALOG.read_text())
    keys = [key for key in sorted(catalog["strings"], key=str.lower) if key.strip()]
    # Keys imported before keep their names, so the screens using them keep their text; new keys take free names.
    previous = existing_names()
    names = {key: previous[comment(key)] for key in keys if comment(key) in previous}
    used = set(names.values())
    for key in keys:
        if key in names:
            continue
        base = name(key)
        resource = base
        suffix = 2
        while resource in used:
            resource = f"{base}_{suffix}"
            suffix += 1
        names[key] = resource
        used.add(resource)
    names = {key: names[key] for key in keys}

    for language, folder in LANGUAGES.items():
        lines = [
            '<?xml version="1.0" encoding="utf-8"?>',
            "<!-- Generated from apps/ios/Aqra/Localizable.xcstrings by tools/import-ios-strings.py. Don't edit by hand. -->",
            '<resources xmlns:tools="http://schemas.android.com/tools" tools:ignore="MissingTranslation,UnusedResources,PluralsCandidate">',
        ]
        for key, resource in names.items():
            # Plurals stay plurals in every language, even where one language has a single form.
            english = entries(key, catalog["strings"][key], "en")
            found = entries(key, catalog["strings"][key], language)
            if found is None:
                continue
            kind, value = found
            if english and english[0] == "plurals" and kind == "string":
                kind, value = "plurals", {"other": value}
            lines.append(f"    <!-- {comment(key)} -->")
            if kind == "string":
                formatted = ' formatted="false"' if "%" in value and count_args(key) == 0 else ""
                lines.append(f'    <string name="{resource}"{formatted}>{escape(value)}</string>')
            else:
                lines.append(f'    <plurals name="{resource}">')
                order = ARABIC_QUANTITIES if language == "ar" else ["zero", "one", "two", "few", "many", "other"]
                for quantity in order:
                    if quantity in value:
                        lines.append(f'        <item quantity="{quantity}">{escape(value[quantity])}</item>')
                lines.append("    </plurals>")
        lines.append("</resources>")
        path = RES / folder / "strings_ios.xml"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines) + "\n")
        print(f"Wrote {path.relative_to(ROOT)}")

    if "--names" in sys.argv:
        for key, resource in names.items():
            print(f"{resource}\t{key}")


if __name__ == "__main__":
    main()
