#!/usr/bin/env python3
"""Builds DoddyApp/Resources/Localizable.xcstrings from l10n/pl.json (ADR-223).

l10n/pl.json maps each English UI string, written as it appears in the Swift source (escapes
such as \\n, \\" and \\u{201C} included), to its Polish text. SwiftUI looks these keys up for
Text("…"), Button("…") and the like, so the iPhone shows Polish when its language is Polish and
English otherwise. Strings without a Polish line stay in English.

  python3 -I tools/build_strings_catalog.py          write the catalog, print coverage
  python3 -I tools/build_strings_catalog.py --check  fail if the catalog is out of date, or a
                                                     Polish line's key is no longer in the app
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLE = os.path.join(ROOT, "l10n", "pl.json")
CATALOG = os.path.join(ROOT, "DoddyApp", "Resources", "Localizable.xcstrings")
APP = os.path.join(ROOT, "DoddyApp")
CALLS = (r'(?:Text|Button|Label|Toggle|Section|navigationTitle|TextField|SecureField|DisclosureGroup|Picker|'
         r'confirmationDialog|alert|LabeledContent|Link|ShareLink|DatePicker|Stepper|accessibilityLabel|accessibilityHint)')
LITERAL = re.compile(CALLS + r'\(\s*"((?:[^"\\]|\\.)*)"')
NAMED = re.compile(r'(?:eyebrow|title|subtitle):\s*"((?:[^"\\]|\\.)*)"')


def unescape(swift):
    """A Swift string literal's body to the string it makes."""
    out, i = [], 0
    while i < len(swift):
        c = swift[i]
        if c == "\\" and i + 1 < len(swift):
            n = swift[i + 1]
            if n == "u" and swift[i + 2:i + 3] == "{":
                end = swift.index("}", i)
                out.append(chr(int(swift[i + 3:end], 16)))
                i = end + 1
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def app_strings():
    found = set()
    for dirpath, _, files in os.walk(APP):
        for name in files:
            if name.endswith(".swift"):
                text = open(os.path.join(dirpath, name), encoding="utf-8").read()
                for match in list(LITERAL.finditer(text)) + list(NAMED.finditer(text)):
                    if "\\(" not in match.group(1):
                        found.add(match.group(1))
    return found


def catalog(table):
    strings = {}
    for key in sorted(table):
        strings[unescape(key)] = {
            "extractionState": "manual",
            "localizations": {"pl": {"stringUnit": {"state": "translated", "value": table[key]}}},
        }
    return json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"},
                      ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main():
    table = json.load(open(TABLE, encoding="utf-8"))
    bad = [k for k, v in table.items() if "%" in k or not v.strip()]
    if bad:
        sys.exit(f"FAIL: keys with % or empty Polish lines in l10n/pl.json: {bad[:5]}")
    in_app = app_strings()
    stale = sorted(k for k in table if k not in in_app)
    text = catalog(table)
    if "--check" in sys.argv:
        current = open(CATALOG, encoding="utf-8").read() if os.path.exists(CATALOG) else ""
        if current != text:
            sys.exit("FAIL: Localizable.xcstrings is out of date; run python3 -I tools/build_strings_catalog.py")
        if stale:
            sys.exit(f"FAIL: Polish lines for strings no longer in the app: {stale[:5]}")
        print(f"PASS: Polish catalog up to date ({len(table)} of {len(in_app)} literal UI strings; the rest show in English).")
        return
    os.makedirs(os.path.dirname(CATALOG), exist_ok=True)
    open(CATALOG, "w", encoding="utf-8").write(text)
    print(f"Wrote {len(table)} Polish strings; {len(in_app)} literal UI strings in the app.")
    if stale:
        print("Not in the app any more:", stale)


if __name__ == "__main__":
    main()
