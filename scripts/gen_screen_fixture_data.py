#!/usr/bin/env python3
"""Rebuilds DoddyApp/Features/Voice/ScreenFixtureData.swift from the contract fixtures (ADR-694)."""
import json, pathlib, sys

root = pathlib.Path(__file__).resolve().parent.parent
deals = json.loads((root / "schemas/fixtures/deals_search_v1.json").read_text())["response"]
errand = json.loads((root / "schemas/fixtures/errand_result_shopping_v1.json").read_text())


def lit(name, obj):
    s = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    assert '"""' not in s
    return f'    static let {name} = #"""\n{s}\n"""#\n'


out = '''#if DEBUG
import Foundation

/// Sample data for the screens run (ADR-694), copied from the repository's contract fixtures
/// (`schemas/fixtures/deals_search_v1.json` and `errand_result_shopping_v1.json`) by
/// `scripts/gen_screen_fixture_data.py`. Made-up shops, prices and dates (24 Oct 2026): nothing here
/// is a real offer. Debug builds only.
enum ScreenFixtureData {
''' + lit("deals", deals) + "\n" + lit("shoppingResult", errand) + "}\n#endif\n"
target = root / "DoddyApp/Features/Voice/ScreenFixtureData.swift"
if "--check" in sys.argv:
    sys.exit(0 if target.read_text() == out else 1)
target.write_text(out)
