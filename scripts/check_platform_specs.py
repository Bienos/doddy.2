#!/usr/bin/env python3
"""Keeps the per-platform XcodeGen specs in step (docs/platforms/README.md).

  project.yml         iPhone + iPad app, extensions, embedded Apple Watch app (ships)
  project-iphone.yml  project.yml with the app's dependencies minus DoddyWatch, and only its scheme
  project-mac.yml     the Mac app and widget only

Fails when the iPhone-only dependency list or scheme drifts from project.yml, when a target is in
the wrong spec for its platform, or when the base bundle identifier differs.

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
    full, iphone, mac = load("project.yml"), load("project-iphone.yml"), load("project-mac.yml")
    problems = []

    if iphone.get("include") != ["project.yml"]:
        problems.append("project-iphone.yml must include exactly project.yml")
    expected = [d for d in full["targets"]["Doddy"]["dependencies"] if d.get("target") != "DoddyWatch"]
    if iphone["targets"]["Doddy"]["dependencies:REPLACE"] != expected:
        problems.append("project-iphone.yml: Doddy's dependencies must be project.yml's minus DoddyWatch")
    if iphone.get("schemes:REPLACE", {}).get("Doddy") != full["schemes"]["Doddy"]:
        problems.append("project-iphone.yml: the Doddy scheme must equal project.yml's")

    for name, target in full["targets"].items():
        if target.get("platform") == "macOS":
            problems.append(f"project.yml: macOS target {name} belongs in project-mac.yml")
    for name, target in mac["targets"].items():
        if target.get("platform") != "macOS":
            problems.append(f"project-mac.yml: {name} is not a macOS target")

    base = "DODDY_APP_BUNDLE_IDENTIFIER"
    if full["settings"]["base"][base] != mac["settings"]["base"][base]:
        problems.append(f"{base} differs between project.yml and project-mac.yml")

    if problems:
        sys.exit("FAIL: " + "; ".join(problems))
    print("PASS: platform specs in step (iPhone-only = project.yml minus the watch app; Mac on its own)")


if __name__ == "__main__":
    main()
