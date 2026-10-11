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
# Each target gets the Polish lines for the strings in its own sources (the app gets them all,
# as before). Shared/ is compiled into the app and the widget extension.
TARGETS = [
    ("DoddyApp/Resources/Localizable.xcstrings", ("DoddyApp", "Shared")),
    ("DoddyWidgets/Localizable.xcstrings", ("DoddyWidgets", "Shared")),
    ("DoddyWatch/Localizable.xcstrings", ("DoddyWatch",)),
    ("DoddyWatchWidgets/Localizable.xcstrings", ("DoddyWatchWidgets",)),
]
# System permission prompts (INFOPLIST_KEY_NS…UsageDescription in project.yml, app target):
# l10n/pl_infoplist.json holds the English each translation was made from, so a changed prompt
# fails the check until its Polish is reviewed.
INFOPLIST_TABLE = os.path.join(ROOT, "l10n", "pl_infoplist.json")
INFOPLIST_CATALOG = os.path.join(ROOT, "DoddyApp", "Resources", "InfoPlist.xcstrings")
PROJECT = os.path.join(ROOT, "project.yml")
# Siri and Shortcuts phrases (DoddyShortcuts.swift): "\(.applicationName)" is written
# ${applicationName} and "\(\.$list)" ${list}, as App Shortcut catalogs expect.
SHORTCUTS_TABLE = os.path.join(ROOT, "l10n", "pl_shortcuts.json")
SHORTCUTS_SOURCE = os.path.join(ROOT, "DoddyApp", "Intents", "DoddyShortcuts.swift")
SHORTCUTS_CATALOG = os.path.join(ROOT, "DoddyApp", "Resources", "AppShortcuts.xcstrings")
CALLS = (r'(?:Text|Button|Label|Toggle|Section|navigationTitle|TextField|SecureField|DisclosureGroup|Picker|'
         r'confirmationDialog|alert|LabeledContent|Link|ShareLink|DatePicker|Stepper|ProgressView|accessibilityLabel|accessibilityHint)')
LITERAL = re.compile(CALLS + r'\(\s*"((?:[^"\\]|\\.)*)"')
NAMED = re.compile(r'(?:eyebrow|title|subtitle):\s*"((?:[^"\\]|\\.)*)"')
# Strings made in code (ADR-223 follow-up): NSLocalizedString("…"), App Intent titles and
# descriptions, App Shortcut short titles.
RUNTIME = re.compile(r'(?:NSLocalizedString\(|LocalizedStringResource\(|IntentDescription\(|(?:LocalizedStringResource|IntentDescription) = |shortTitle:\s*)\s*"((?:[^"\\]|\\.)*)"')


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


def catalog(table):
    strings = {}
    for key in sorted(table):
        strings[unescape(key)] = {
            "extractionState": "manual",
            "localizations": {"pl": {"stringUnit": {"state": "translated", "value": table[key]}}},
        }
    return json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"},
                      ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def usage_prompts():
    """The app target's INFOPLIST_KEY_NS…UsageDescription values, in project.yml order."""
    text = open(PROJECT, encoding="utf-8").read()
    app = text.split("\n  DoddyWidgets:")[0]
    prompts = dict(re.findall(r'INFOPLIST_KEY_(NS\w+UsageDescription): "((?:[^"\\]|\\.)*)"', app))
    # Keys that have no INFOPLIST_KEY_ build setting live in the app's partial Info.plist.
    plist = open(os.path.join(ROOT, "Config", "Doddy-Info.plist"), encoding="utf-8").read()
    prompts.update(re.findall(r"<key>(NS\w+UsageDescription)</key>\s*<string>([^<]*)</string>", plist))
    return prompts


def infoplist_catalog(table):
    strings = {}
    for key in sorted(table):
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                "en": {"stringUnit": {"state": "translated", "value": table[key]["en"]}},
                "pl": {"stringUnit": {"state": "translated", "value": table[key]["pl"]}},
            },
        }
    return json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"},
                      ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def shortcut_phrases():
    text = open(SHORTCUTS_SOURCE, encoding="utf-8").read()
    phrases = []
    for block in re.findall(r'phrases:\s*\[(.*?)\]', text, re.S):
        for raw in re.findall(r'"((?:[^"\\]|\\.)*)"', block):
            phrases.append(raw.replace("\\(.applicationName)", "${applicationName}").replace("\\(\\.$list)", "${list}"))
    return phrases


def check_extra(problems):
    prompts = usage_prompts()
    infoplist = json.load(open(INFOPLIST_TABLE, encoding="utf-8"))
    for key, english in prompts.items():
        entry = infoplist.get(key)
        if entry is None:
            problems.append(f"{key} has no Polish line in l10n/pl_infoplist.json")
        elif entry["en"] != english.replace('\\"', '"'):
            problems.append(f"{key} changed in project.yml; review its Polish in l10n/pl_infoplist.json")
    for key in infoplist:
        if key not in prompts:
            problems.append(f"{key} is in l10n/pl_infoplist.json but not in project.yml")
    phrases = shortcut_phrases()
    shortcuts = json.load(open(SHORTCUTS_TABLE, encoding="utf-8"))
    for phrase in phrases:
        if phrase not in shortcuts:
            problems.append(f"Siri phrase without Polish: {phrase}")
    for phrase, polish in shortcuts.items():
        if phrase not in phrases:
            problems.append(f"Polish Siri phrase for a phrase no longer in DoddyShortcuts.swift: {phrase}")
        if polish.count("${applicationName}") != 1 or ("${list}" in phrase) != ("${list}" in polish):
            problems.append(f"Polish Siri phrase must name the app once and keep ${{list}} as the English does: {polish}")
    return infoplist, shortcuts


def main():
    table = json.load(open(TABLE, encoding="utf-8"))
    # A % is allowed only in a format string from code (NSLocalizedString("Moved %@")): the
    # Polish line must keep exactly the same placeholders, in the same order.
    spec = re.compile(r"%(?:@|lld|d|%)")
    bad = [k for k, v in table.items()
           if not v.strip() or ("%" in k and (re.sub(spec, "", k).count("%") > 0 or spec.findall(k) != spec.findall(v)))]
    if bad:
        sys.exit(f"FAIL: empty Polish lines, or a % that isn't a matching placeholder, in l10n/pl.json: {bad[:5]}")
    in_app = app_strings()
    stale = sorted(k for k in table if k not in in_app)
    problems = []
    infoplist, shortcuts = check_extra(problems)
    outputs = {}
    for index, (path, folders) in enumerate(TARGETS):
        found = strings_in(*folders)
        # The app's catalog carries every line, as before; the others only their own strings.
        part = table if index == 0 else {k: v for k, v in table.items() if k in found}
        outputs[os.path.join(ROOT, path)] = catalog(part)
    outputs[INFOPLIST_CATALOG] = infoplist_catalog(infoplist)
    outputs[SHORTCUTS_CATALOG] = catalog(shortcuts)
    if "--check" in sys.argv:
        for path, text in outputs.items():
            current = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
            if current != text:
                sys.exit(f"FAIL: {os.path.relpath(path, ROOT)} is out of date; run python3 -I tools/build_strings_catalog.py")
        if stale:
            sys.exit(f"FAIL: Polish lines for strings no longer in the app: {stale[:5]}")
        if problems:
            sys.exit("FAIL: " + "; ".join(problems[:5]))
        print(f"PASS: Polish catalogs up to date ({len(table)} of {len(in_app)} UI strings; "
              f"{len(infoplist)} permission prompts; {len(shortcuts)} Siri phrases; the rest show in English).")
        return
    for path, text in outputs.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", encoding="utf-8").write(text)
    print(f"Wrote {len(table)} Polish strings; {len(in_app)} UI strings in the app; "
          f"{len(infoplist)} permission prompts; {len(shortcuts)} Siri phrases.")
    if stale:
        print("Not in the app any more:", stale)
    for problem in problems:
        print("Problem:", problem)


if __name__ == "__main__":
    main()
