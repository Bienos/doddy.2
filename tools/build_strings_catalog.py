#!/usr/bin/env python3
"""Builds the String Catalogs (*.xcstrings) from the translation tables in l10n/ (ADR-223, ADR-458).

l10n/<code>.json maps each English UI string, written as it appears in the Swift source (escapes
such as \\n, \\" and \\u{201C} included), to its text in the language <code>: an Xcode language
code such as pl, de, pt-BR or zh-Hans. SwiftUI looks these keys up for Text("…"), Button("…") and
the like, so the iPhone shows that language when it is set to it and English otherwise. Strings
without a line in a language stay in English. Each language also has <code>_infoplist.json (the
system permission prompts, with the English each translation was made from) and
<code>_shortcuts.json (the Siri phrases). The languages found are written to CFBundleLocalizations
in Config/Doddy-Info.plist and Config/DoddyMac-Info.plist. tools/l10n_batch.py writes the tables;
l10n/README.md explains the steps.

  python3 -I tools/build_strings_catalog.py          write the catalogs and plists, print coverage
  python3 -I tools/build_strings_catalog.py --check  fail if anything is out of date, a line's key is
                                                     no longer in the app, or a table is malformed
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N = os.path.join(ROOT, "l10n")
# A table's file name is its language code: pl.json, pt-BR.json, zh-Hans.json. The permission
# prompts and Siri phrases sit next to it as <code>_infoplist.json and <code>_shortcuts.json.
CODE = re.compile(r"^([a-z]{2,3}(?:-[A-Za-z0-9]+)*)\.json$")
APP = os.path.join(ROOT, "DoddyApp")
# Each target gets the lines for the strings in its own sources (the app gets them all, as
# before). Shared/ is compiled into the app and the widget extension.
TARGETS = [
    ("DoddyApp/Resources/Localizable.xcstrings", ("DoddyApp", "Shared")),
    ("DoddyWidgets/Localizable.xcstrings", ("DoddyWidgets", "Shared")),
    ("DoddyShare/Localizable.xcstrings", ("DoddyShare",)),
    ("DoddyWatch/Localizable.xcstrings", ("DoddyWatch",)),
    ("DoddyWatchWidgets/Localizable.xcstrings", ("DoddyWatchWidgets",)),
    ("DoddyMac/Localizable.xcstrings", ("DoddyMac",)),
    ("DoddyMacWidgets/Localizable.xcstrings", ("DoddyMacWidgets",)),
]
# System permission prompts (INFOPLIST_KEY_NS…UsageDescription in project.yml, app target):
# l10n/<code>_infoplist.json holds the English each translation was made from, so a changed
# prompt fails the check until its translation is reviewed.
INFOPLIST_CATALOG = os.path.join(ROOT, "DoddyApp", "Resources", "InfoPlist.xcstrings")
PROJECT = os.path.join(ROOT, "project.yml")
# Siri and Shortcuts phrases (DoddyShortcuts.swift): "\(.applicationName)" is written
# ${applicationName} and "\(\.$list)" ${list}, as App Shortcut catalogs expect.
SHORTCUTS_SOURCE = os.path.join(ROOT, "DoddyApp", "Intents", "DoddyShortcuts.swift")
SHORTCUTS_CATALOG = os.path.join(ROOT, "DoddyApp", "Resources", "AppShortcuts.xcstrings")
# The app and Mac bundles list their languages; the array is rewritten from the tables found.
# Settings › App language lists the languages from this enum (ADR-459).
APP_LANGUAGE = os.path.join(ROOT, "Packages", "DoddyCore", "Sources", "DoddyCore", "AppLanguage.swift")
PLISTS = [os.path.join(ROOT, "Config", "Doddy-Info.plist"), os.path.join(ROOT, "Config", "DoddyMac-Info.plist")]
PLIST_LANGUAGES = re.compile(r"(<key>CFBundleLocalizations</key>\n\t<array>\n)(?:\t\t<string>[^<]*</string>\n)*(\t</array>)")
CALLS = (r'(?:Text|Button|Label|Toggle|Section|navigationTitle|TextField|SecureField|DisclosureGroup|Picker|'
         r'confirmationDialog|alert|LabeledContent|Link|ShareLink|DatePicker|Stepper|ProgressView|accessibilityLabel|accessibilityHint)')
LITERAL = re.compile(CALLS + r'\(\s*"((?:[^"\\]|\\.)*)"')
NAMED = re.compile(r'(?:eyebrow|title|subtitle):\s*"((?:[^"\\]|\\.)*)"')
# Strings made in code (ADR-223 follow-up): NSLocalizedString("…"), App Intent titles and
# descriptions, App Shortcut short titles.
# The Dynamic Island's and Lock Screen's words (ADR-617): `islandWord("…")` in Shared/, which the
# island's views look up in the app's language (Shared/IslandArt/IslandLanguage.swift).
RUNTIME = re.compile(r'(?:NSLocalizedString\(|LocalizedStringResource\(|IntentDescription\(|islandWord\(|(?:LocalizedStringResource|IntentDescription) = |shortTitle:\s*)\s*"((?:[^"\\]|\\.)*)"')
# A % is allowed only in a format string from code (NSLocalizedString("Moved %@")): a translated
# line must keep exactly the same placeholders, in the same order.
PLACEHOLDER = re.compile(r"%(?:@|lld|d|%)")


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


def strings_in(*folders):
    found = set()
    for folder in folders:
        for dirpath, _, files in os.walk(os.path.join(ROOT, folder)):
            for name in files:
                if name.endswith(".swift"):
                    text = open(os.path.join(dirpath, name), encoding="utf-8").read()
                    for pattern in (LITERAL, NAMED, RUNTIME):
                        for match in pattern.finditer(text):
                            if "\\(" not in match.group(1):
                                found.add(match.group(1))
    return found


def app_strings():
    return strings_in(*[folder for _, folders in TARGETS for folder in folders])


def languages():
    """The codes with a table in l10n/, Polish first since it is the reviewed one."""
    codes = sorted(match.group(1) for name in os.listdir(L10N) if (match := CODE.match(name)))
    if "pl" not in codes:
        sys.exit("FAIL: l10n/pl.json is missing")
    return codes


def table_path(code, kind=""):
    return os.path.join(L10N, f"{code}{kind}.json")


def load(path):
    return json.load(open(path, encoding="utf-8"))


def placeholders_match(key, value):
    """The value keeps the key's % placeholders, and has no stray %."""
    if "%" not in key:
        return "%" not in value
    return PLACEHOLDER.sub("", key).count("%") == 0 and PLACEHOLDER.findall(key) == PLACEHOLDER.findall(value)


# iPad wording (ADR-437): a string that says "this iPhone" gets a device variation, so on an iPad
# it says "this iPad" in every language. Every other "iPhone" in such a string also means this
# device ("your iPhone backups"), checked when this was added. Polish declines the word, so it has
# its own rule; other languages keep "iPhone" unchanged (the translation prompt asks for that) and
# get the plain swap. Only the targets that run on iPad; the watch and Mac catalogs are left alone.
IPAD_TARGETS = ("DoddyApp/Resources/Localizable.xcstrings", "DoddyWidgets/Localizable.xcstrings",
                "DoddyShare/Localizable.xcstrings")


def says_this_iphone(key):
    return "this iPhone" in unescape(key)


def ipad_english(text):
    return text.replace("iPhone", "iPad")


def ipad_polish(text):
    # Locative "na tym iPhonie", genitive "z tego iPhone’a", nominative "iPhone".
    return re.sub(r"iPhone[’']a", "iPada", text).replace("iPhonie", "iPadzie").replace("iPhone", "iPad")


IPAD_RULES = {"en": ipad_english, "pl": ipad_polish}


def ipad_text(code, text):
    return IPAD_RULES.get(code, ipad_english)(text)


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def by_device(other, ipad):
    return {"variations": {"device": {"ipad": unit(ipad), "other": unit(other)}}}


def dump(strings):
    return json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"},
                      ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def catalog(tables, ipad_keys=()):
    """tables: {code: {English key: text}}. One entry per key in any table, with a column per
    language that has it; the English device variation for the iPad keys."""
    keys = set(ipad_keys)
    for table in tables.values():
        keys |= set(table)
    strings = {}
    for key in sorted(keys):
        localizations = {}
        if key in ipad_keys:
            english = unescape(key)
            localizations["en"] = by_device(english, ipad_english(english))
        for code, table in tables.items():
            if key in table:
                text = table[key]
                localizations[code] = by_device(text, ipad_text(code, text)) if key in ipad_keys else unit(text)
        strings[unescape(key)] = {"extractionState": "manual", "localizations": localizations}
    return dump(strings)


def usage_prompts():
    """The app target's INFOPLIST_KEY_NS…UsageDescription values, in project.yml order."""
    text = open(PROJECT, encoding="utf-8").read()
    app = text.split("\n  DoddyWidgets:")[0]
    prompts = dict(re.findall(r'INFOPLIST_KEY_(NS\w+UsageDescription): "((?:[^"\\]|\\.)*)"', app))
    # Keys that have no INFOPLIST_KEY_ build setting live in the app's partial Info.plist.
    plist = open(os.path.join(ROOT, "Config", "Doddy-Info.plist"), encoding="utf-8").read()
    prompts.update(re.findall(r"<key>(NS\w+UsageDescription)</key>\s*<string>([^<]*)</string>", plist))
    return prompts


def infoplist_catalog(tables):
    """tables: {code: {prompt key: {"en": English, code: translation}}}."""
    keys = set()
    for table in tables.values():
        keys |= set(table)
    strings = {}
    for key in sorted(keys):
        localizations = {}
        for code, table in tables.items():
            if key in table:
                localizations["en"] = unit(table[key]["en"])
                localizations[code] = unit(table[key][code])
        strings[key] = {"extractionState": "manual", "localizations": localizations}
    return dump(strings)


def shortcut_phrases():
    text = open(SHORTCUTS_SOURCE, encoding="utf-8").read()
    phrases = []
    for block in re.findall(r'phrases:\s*\[(.*?)\]', text, re.S):
        for raw in re.findall(r'"((?:[^"\\]|\\.)*)"', block):
            phrases.append(raw.replace("\\(.applicationName)", "${applicationName}").replace("\\(\\.$list)", "${list}"))
    return phrases


def check_language(code, prompts, phrases, problems):
    """The language's permission prompts and Siri phrases, with what is wrong with them."""
    infoplist, shortcuts = {}, {}
    path = table_path(code, "_infoplist")
    if os.path.exists(path):
        infoplist = load(path)
        for key, english in prompts.items():
            entry = infoplist.get(key)
            if entry is None:
                problems.append(f"{key} has no line in l10n/{code}_infoplist.json")
            elif entry.get("en") != english.replace('\\"', '"'):
                problems.append(f"{key} changed in project.yml; review its text in l10n/{code}_infoplist.json")
            elif not entry.get(code, "").strip():
                problems.append(f"{key} has no '{code}' text in l10n/{code}_infoplist.json")
        for key in infoplist:
            if key not in prompts:
                problems.append(f"{key} is in l10n/{code}_infoplist.json but not in project.yml")
    else:
        problems.append(f"l10n/{code}_infoplist.json is missing (the permission prompts)")
    path = table_path(code, "_shortcuts")
    if os.path.exists(path):
        shortcuts = load(path)
        for phrase in phrases:
            if phrase not in shortcuts:
                problems.append(f"Siri phrase without {code}: {phrase}")
        for phrase, text in shortcuts.items():
            if phrase not in phrases:
                problems.append(f"{code} Siri phrase for a phrase no longer in DoddyShortcuts.swift: {phrase}")
            if text.count("${applicationName}") != 1 or ("${list}" in phrase) != ("${list}" in text):
                problems.append(f"A {code} Siri phrase must name the app once and keep ${{list}} as the English does: {text}")
    else:
        problems.append(f"l10n/{code}_shortcuts.json is missing (the Siri phrases)")
    return infoplist, shortcuts


def check_picker(codes, problems):
    """Every language with a table is a choice in Settings › App language (ADR-459), and the
    picker offers nothing the app has no strings for."""
    text = open(APP_LANGUAGE, encoding="utf-8").read()
    offered = set(re.findall(r'case \w+ = "([^"]+)"', text))
    for code in codes:
        if code not in offered:
            problems.append(f"{code} has a table in l10n/ but is not a case in AppLanguage.swift, so the picker can't offer it")
    for code in sorted(offered - set(codes) - {"en", "system"}):
        problems.append(f"AppLanguage.swift offers {code}, which has no table in l10n/")


def plist_with_languages(text, codes, path):
    lines = "".join(f"\t\t<string>{code}</string>\n" for code in ["en"] + codes)
    new, count = PLIST_LANGUAGES.subn(lambda m: m.group(1) + lines + m.group(2), text, count=1)
    if count != 1:
        sys.exit(f"FAIL: no CFBundleLocalizations array found in {os.path.relpath(path, ROOT)}")
    return new


def main():
    codes = languages()
    tables = {code: load(table_path(code)) for code in codes}
    for code, table in tables.items():
        bad = [k for k, v in table.items() if not v.strip() or not placeholders_match(k, v)]
        if bad:
            sys.exit(f"FAIL: empty lines, or a % that isn't a matching placeholder, in l10n/{code}.json: {bad[:5]}")
    in_app = app_strings()
    stale = [f"{code}: {k}" for code, table in tables.items() for k in sorted(table) if k not in in_app]
    problems = []
    prompts, phrases = usage_prompts(), shortcut_phrases()
    infoplists, shortcuts = {}, {}
    for code in codes:
        infoplists[code], shortcuts[code] = check_language(code, prompts, phrases, problems)
    check_picker(codes, problems)
    outputs = {}
    for index, (path, folders) in enumerate(TARGETS):
        found = strings_in(*folders)
        # The app's catalog carries every line, as before; the others only their own strings.
        parts = {code: (table if index == 0 else {k: v for k, v in table.items() if k in found})
                 for code, table in tables.items()}
        ipad_keys = {k for k in found if says_this_iphone(k)} if path in IPAD_TARGETS else set()
        outputs[os.path.join(ROOT, path)] = catalog(parts, ipad_keys)
    outputs[INFOPLIST_CATALOG] = infoplist_catalog(infoplists)
    outputs[SHORTCUTS_CATALOG] = catalog(shortcuts)
    for plist in PLISTS:
        outputs[plist] = plist_with_languages(open(plist, encoding="utf-8").read(), codes, plist)
    coverage = "; ".join(f"{code}: {len(tables[code])} of {len(in_app)} UI strings, {len(infoplists[code])} permission prompts, "
                         f"{len(shortcuts[code])} Siri phrases" for code in codes)
    if "--check" in sys.argv:
        for path, text in outputs.items():
            current = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
            if current != text:
                sys.exit(f"FAIL: {os.path.relpath(path, ROOT)} is out of date; run python3 -I tools/build_strings_catalog.py")
        if stale:
            sys.exit(f"FAIL: lines for strings no longer in the app: {stale[:5]}")
        if problems:
            sys.exit("FAIL: " + "; ".join(problems[:5]))
        print(f"PASS: string catalogs up to date ({coverage}; the rest show in English).")
        return
    for path, text in outputs.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", encoding="utf-8").write(text)
    print(f"Wrote {len(codes)} language(s): {coverage}.")
    if stale:
        print("Not in the app any more:", stale)
    for problem in problems:
        print("Problem:", problem)


if __name__ == "__main__":
    main()
