#!/usr/bin/env python3
"""Keeps the per-platform XcodeGen specs in step (docs/platforms/README.md).

  project.yml         iPhone + iPad app and its extensions (ships). No Watch or Mac target (ADR-572).
  project-iphone.yml  the same dependencies (less the widget and share extensions) and scheme, with no entitlements
  project-watch.yml   PAUSED: project.yml plus the Apple Watch app embedded in the iPhone app
  project-mac.yml     PAUSED: the Mac app and widget only

Fails when a watchOS or macOS target is back in project.yml (so the pause can't end by accident),
when the dormant specs drift from project.yml, when a target is in the wrong spec for its platform,
or when the base bundle identifier differs.

  python3 -I scripts/check_platform_specs.py
"""
import os
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name):
    with open(os.path.join(ROOT, name), encoding="utf-8") as f:
        return yaml.safe_load(f)


def main():
    full, iphone, watch, mac = (load(n) for n in ("project.yml", "project-iphone.yml", "project-watch.yml", "project-mac.yml"))
    problems = []
    app_deps = full["targets"]["Doddy"]["dependencies"]

    # The pause (ADR-572): the shipping project and its CI build contain no Watch or Mac target.
    for name, target in full["targets"].items():
        if target.get("platform") in ("macOS", "watchOS") or name.startswith(("DoddyWatch", "DoddyMac")):
            problems.append(f"project.yml: {name} is paused (ADR-572); its spec is project-watch.yml / project-mac.yml")
    if any(d.get("target", "").startswith(("DoddyWatch", "DoddyMac")) for d in app_deps):
        problems.append("project.yml: the Doddy app must not depend on a Watch or Mac target (ADR-572)")
    if set(full.get("schemes", {})) != {"Doddy"}:
        problems.append("project.yml: its only scheme is Doddy (ADR-572)")

    if iphone.get("include") != ["project.yml"]:
        problems.append("project-iphone.yml must include exactly project.yml")
    # A free Apple team signs only the app (owner, 23 Oct 2026): the widgets and Save to Doddy, which
    # can't work without App Groups anyway, are left out, so Xcode asks for a team once.
    extensions = ("DoddyWidgets", "DoddyShare")
    if iphone["targets"]["Doddy"]["dependencies:REPLACE"] != [d for d in app_deps if d.get("target") not in extensions]:
        problems.append("project-iphone.yml: Doddy's dependencies must be project.yml's without DoddyWidgets and DoddyShare")
    if iphone.get("schemes:REPLACE", {}).get("Doddy") != full["schemes"]["Doddy"]:
        problems.append("project-iphone.yml: the Doddy scheme must equal project.yml's")

    # The dormant Watch spec: project.yml's app dependencies plus the Watch app (order doesn't matter).
    if watch.get("include") != ["project.yml"]:
        problems.append("project-watch.yml must include exactly project.yml")
    got = sorted(map(repr, watch["targets"]["Doddy"]["dependencies:REPLACE"]))
    if got != sorted(map(repr, app_deps + [{"target": "DoddyWatch"}])):
        problems.append("project-watch.yml: Doddy's dependencies must be project.yml's plus DoddyWatch")
    if set(watch["targets"]) != {"Doddy", "DoddyWatch", "DoddyWatchWidgets"}:
        problems.append("project-watch.yml: expected the Doddy override and the DoddyWatch and DoddyWatchWidgets targets")
    for name in ("DoddyWatch", "DoddyWatchWidgets"):
        if watch["targets"].get(name, {}).get("platform") != "watchOS":
            problems.append(f"project-watch.yml: {name} is not a watchOS target")
    if "DoddyWatch" not in watch.get("schemes", {}):
        problems.append("project-watch.yml: the DoddyWatch scheme is missing")

    for name, target in mac["targets"].items():
        if target.get("platform") != "macOS":
            problems.append(f"project-mac.yml: {name} is not a macOS target")

    base = "DODDY_APP_BUNDLE_IDENTIFIER"
    if full["settings"]["base"][base] != mac["settings"]["base"][base]:
        problems.append(f"{base} differs between project.yml and project-mac.yml")

    if problems:
        sys.exit("FAIL: " + "; ".join(problems))
    print("PASS: platform specs in step (project.yml is iPhone/iPad only; Watch and Mac specs dormant, ADR-572)")


if __name__ == "__main__":
    main()
