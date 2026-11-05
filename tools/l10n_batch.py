#!/usr/bin/env python3
"""Writes a language's translation tables in l10n/ a batch at a time (ADR-458).

The English strings are the keys of l10n/pl.json, the reviewed Polish table, so a translator never
types a key: `show` prints each string with a number, the translator answers with a JSON object
from number to text, and `merge` puts the text under the right key. Three tables per language:

  ui          l10n/<code>.json            the screens (1,358 strings)
  infoplist   l10n/<code>_infoplist.json  the 8 system permission prompts
  shortcuts   l10n/<code>_shortcuts.json  the 26 Siri phrases

  python3 -I tools/l10n_batch.py show <code> [--table ui] [--count 80] [--all]
      The next <count> strings still missing in <code> (or every string with --all): the number,
      the English as a person reads it (real line breaks, real › and “ characters), the Polish
      as a second reference, and the current <code> text if there is one.
  python3 -I tools/l10n_batch.py merge <code> [--table ui] [file.json]
      Reads {"<number>": "<text>", …} from the file or stdin and writes the table. A text that
      is empty or loses a % placeholder is refused and listed; the rest are kept.
  python3 -I tools/l10n_batch.py status <code>
      How many strings each table still lacks, and the first missing numbers.

Then run tools/build_strings_catalog.py to put the tables in the app's catalogs.
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N = os.path.join(ROOT, "l10n")
TABLES = {"ui": "", "infoplist": "_infoplist", "shortcuts": "_shortcuts", "site": ""}
SITE_TAGS = re.compile(r"<[^>]*>")
SITE_TOKEN = re.compile(r"\[\[(?:svg|img|cmt)\d+\]\]")
SITE_PLACEHOLDER = re.compile(r"\{[A-Za-z_][A-Za-z0-9_]*\}")
SITE_BARE_AMP = re.compile(r"&(?!#?[A-Za-z0-9]+;)")
PLACEHOLDER = re.compile(r"%(?:@|lld|d|%)")
CODE = re.compile(r"^[a-z]{2,3}(?:-[A-Za-z0-9]+)*$")


def unescape(swift):
    """A Swift string literal's body to the string it makes (same as build_strings_catalog)."""
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


def path(code, table):
    if table == "site":
        return os.path.join(L10N, "site", f"{code}.json")
    return os.path.join(L10N, f"{code}{TABLES[table]}.json")


def load(file):
    return json.load(open(file, encoding="utf-8")) if os.path.exists(file) else {}


def save(file, data):
    text = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    open(file, "w", encoding="utf-8").write(text)


def source(table):
    """The English keys in a fixed order (sorted, as the files are written), with their Polish."""
    if table == "site":
        file = os.path.join(L10N, "site", "en.json")
        if not os.path.exists(file):
            sys.exit("FAIL: l10n/site/en.json is missing; run python3 -I tools/build_site_i18n.py")
        return sorted(load(file)), {}
    polish = load(path("pl", table))
    if not polish:
        sys.exit(f"FAIL: {os.path.relpath(path('pl', table), ROOT)} is missing")
    return sorted(polish), polish


def english_of(table, key, polish):
    if table == "site":
        return key
    if table == "infoplist":
        return polish[key]["en"]
    return unescape(key)


def polish_of(table, key, polish):
    if table == "site":
        return ""
    if table == "infoplist":
        return polish[key]["pl"]
    return polish[key]


def current_of(table, key, code, current):
    if table == "infoplist":
        return (current.get(key) or {}).get(code)
    return current.get(key)


def site_problem(key, text):
    """Why a site text can't be kept, or None: the same tokens, placeholders and tags as the English."""
    if not text.strip():
        return "empty"
    if sorted(SITE_TOKEN.findall(key)) != sorted(SITE_TOKEN.findall(text)):
        return "the [[svgN]] markup tokens must come back exactly as they are"
    if sorted(SITE_PLACEHOLDER.findall(key)) != sorted(SITE_PLACEHOLDER.findall(text)):
        return f"placeholders must be exactly {SITE_PLACEHOLDER.findall(key)}"
    if sorted(SITE_TAGS.findall(key)) != sorted(SITE_TAGS.findall(text)):
        return "tags and their attributes must come back exactly as they are"
    if SITE_BARE_AMP.search(text) and not SITE_BARE_AMP.search(key):
        return "a bare & must be written as &amp;"
    return None


def problem(table, key, text, polish):
    """Why a text can't be kept, or None."""
    if table == "site":
        return site_problem(key, text)
    if not text or not text.strip():
        return "empty"
    english = english_of(table, key, polish)
    if table == "shortcuts":
        if text.count("${applicationName}") != 1:
            return "must contain ${applicationName} exactly once"
        if ("${list}" in english) != ("${list}" in text):
            return "must keep ${list} as the English does"
        return None
    if "%" in key:
        if PLACEHOLDER.findall(key) != PLACEHOLDER.findall(text):
            return f"placeholders must be exactly {PLACEHOLDER.findall(key)} in that order"
    elif "%" in text:
        return "a % that the English doesn't have"
    return None


def show(args):
    keys, polish = source(args.table)
    current = load(path(args.code, args.table))
    shown = 0
    for number, key in enumerate(keys):
        existing = current_of(args.table, key, args.code, current)
        if existing is not None and not args.all:
            continue
        if shown >= args.count:
            break
        shown += 1
        print(f"#{number}")
        print("EN: " + english_of(args.table, key, polish).replace("\n", "\n    "))
        if args.table != "site":
            print("PL: " + polish_of(args.table, key, polish).replace("\n", "\n    "))
        if existing is not None:
            print(f"{args.code.upper()}: " + existing.replace("\n", "\n    "))
        print()
    missing = sum(1 for key in keys if current_of(args.table, key, args.code, current) is None)
    print(f"({shown} shown; {missing} of {len(keys)} still missing in {args.code} {args.table})")


def merge(args):
    keys, polish = source(args.table)
    file = path(args.code, args.table)
    current = load(file)
    text = open(args.file, encoding="utf-8").read() if args.file else sys.stdin.read()
    try:
        batch = json.loads(text)
    except json.JSONDecodeError as error:
        sys.exit(f"FAIL: the batch is not valid JSON: {error}")
    if not isinstance(batch, dict):
        sys.exit("FAIL: the batch must be a JSON object from number to text")
    kept, refused = 0, []
    for number, value in batch.items():
        if not str(number).isdigit() or int(number) >= len(keys):
            refused.append(f"#{number}: no such number")
            continue
        key = keys[int(number)]
        if not isinstance(value, str):
            refused.append(f"#{number}: text must be a string")
            continue
        why = problem(args.table, key, value, polish)
        if why:
            refused.append(f"#{number}: {why}")
            continue
        if args.table == "infoplist":
            current[key] = {"en": polish[key]["en"], args.code: value}
        else:
            current[key] = value
        kept += 1
    # Keys that are no longer in the Polish table are dropped, so a stale line can't linger.
    current = {key: current[key] for key in keys if key in current}
    save(file, current)
    missing = len(keys) - len(current)
    print(f"Kept {kept}; {os.path.relpath(file, ROOT)} now has {len(current)} of {len(keys)}, {missing} missing.")
    for line in refused:
        print("Refused", line)
    if refused:
        sys.exit(1)


def status(args):
    for table in TABLES:
        keys, _ = source(table)
        current = load(path(args.code, table))
        missing = [number for number, key in enumerate(keys) if current_of(table, key, args.code, current) is None]
        first = ", ".join(f"#{n}" for n in missing[:12]) + (", …" if len(missing) > 12 else "")
        print(f"{table}: {len(keys) - len(missing)} of {len(keys)}; {len(missing)} missing" + (f" ({first})" if missing else ""))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    for name, function in (("show", show), ("merge", merge), ("status", status)):
        command = commands.add_parser(name)
        command.add_argument("code")
        command.set_defaults(run=function)
        if name != "status":
            command.add_argument("--table", choices=TABLES, default="ui")
        if name == "show":
            command.add_argument("--count", type=int, default=80)
            command.add_argument("--all", action="store_true")
        if name == "merge":
            command.add_argument("file", nargs="?")
    args = parser.parse_args()
    if not CODE.match(args.code) or args.code == "en":
        sys.exit(f"FAIL: '{args.code}' is not a language code such as de, pt-BR or zh-Hans")
    args.run(args)


if __name__ == "__main__":
    main()
