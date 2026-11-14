#!/usr/bin/env python3
"""Where render.yaml installs with `npm ci --ignore-scripts`, nothing may need a script to run.

The flag makes npm skip every install-time script: the ones in locked packages, and the folder's own
preinstall/install/postinstall/prepare. A build with the flag still passes when a package needs its script
(it just isn't set up), so the failure shows up later, at run time. This check reads render.yaml, finds each
`npm ci` with the flag, and for the folder it installs (rootDir, or `--prefix`) fails when

  * the folder's package-lock.json is missing, or is too old to say which packages have an install script
    (lockfileVersion below 2), or
  * a locked package is marked `hasInstallScript`, or
  * the folder's package.json has a script npm would run at install time.

An install without the flag is not looked at: it runs the scripts, which is the point of leaving it alone
(web/ keeps them because its build tool, esbuild, has one).

    python3 -I scripts/check_render_install_scripts.py [--root DIR]

Prints one line per problem and exits 1; prints what it checked and exits 0 when there are none. It never
prints file contents beyond package names.
"""
import argparse
import json
import os
import re
import shlex
import sys

LIFECYCLE = ("preinstall", "install", "postinstall", "prepare", "preprepare", "postprepare", "prepublish")
FLAG = "--ignore-scripts"


def services(text):
    """(name, rootDir, buildCommand) per service in a render.yaml, without a YAML library.

    A service starts at a `- type:` line; its keys are the lines indented under it. A block-style
    buildCommand (`|` or `>`) is joined into one line.
    """
    blocks, current = [], None
    for line in text.splitlines():
        if re.match(r"^\s*-\s+type:\s", line):
            current = []
            blocks.append(current)
        if current is not None:
            current.append(line)
    out = []
    for block in blocks:
        name, root, build = "?", ".", None
        i = 0
        while i < len(block):
            line = block[i]
            m = re.match(r"^\s*(?:-\s+)?(name|rootDir|buildCommand):\s*(.*?)\s*$", line)
            if m:
                key, value = m.group(1), m.group(2)
                if key == "buildCommand" and value[:1] in ("|", ">"):
                    parts, j = [], i + 1
                    indent = None
                    while j < len(block):
                        nxt = block[j]
                        if not nxt.strip():
                            j += 1
                            continue
                        lead = len(nxt) - len(nxt.lstrip())
                        if indent is None:
                            indent = lead
                        if lead < indent:
                            break
                        parts.append(nxt.strip())
                        j += 1
                    value, i = " ".join(parts), j - 1
                value = re.sub(r"\s+#.*$", "", value).strip().strip("'\"")
                if key == "name":
                    name = value
                elif key == "rootDir":
                    root = value or "."
                else:
                    build = value
            i += 1
        if build:
            out.append((name, root, build))
    return out


def installs(command):
    """(has_flag, prefix) for each npm ci / install in a shell command line."""
    found = []
    for piece in re.split(r"&&|\|\||;|\n", command):
        try:
            words = shlex.split(piece)
        except ValueError:
            words = piece.split()
        if len(words) >= 2 and words[0] == "npm" and words[1] in ("ci", "install", "i"):
            prefix = None
            for k, w in enumerate(words):
                if w == "--prefix" and k + 1 < len(words):
                    prefix = words[k + 1]
                elif w.startswith("--prefix="):
                    prefix = w.split("=", 1)[1]
            found.append((FLAG in words, prefix))
    return found


def problems_in(folder_abs, label):
    lock = os.path.join(folder_abs, "package-lock.json")
    if not os.path.isfile(lock):
        return [f"{label}: no package-lock.json, so nothing proves the flag safe"]
    try:
        with open(lock, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        return [f"{label}: package-lock.json can't be read ({type(e).__name__})"]
    if not isinstance(data.get("lockfileVersion"), int) or data["lockfileVersion"] < 2:
        return [f"{label}: package-lock.json is too old to say which packages have an install script (lockfileVersion {data.get('lockfileVersion')})"]
    out = []
    for key, entry in sorted((data.get("packages") or {}).items()):
        if key and isinstance(entry, dict) and entry.get("hasInstallScript"):
            out.append(f"{label}: {key} has an install script, which {FLAG} would skip")
    pkg = os.path.join(folder_abs, "package.json")
    try:
        with open(pkg, encoding="utf-8") as f:
            scripts = (json.load(f).get("scripts") or {})
    except (OSError, ValueError):
        scripts = {}
    for hook in LIFECYCLE:
        if hook in scripts:
            out.append(f"{label}: package.json has a \"{hook}\" script, which {FLAG} would skip")
    return out


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    root = os.path.abspath(ap.parse_args(argv).root)
    render = os.path.join(root, "render.yaml")
    try:
        with open(render, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        print(f"check_render_install_scripts: can't read render.yaml ({type(e).__name__})", file=sys.stderr)
        return 1
    problems, checked = [], 0
    for name, root_dir, build in services(text):
        for has_flag, prefix in installs(build):
            if not has_flag:
                continue
            folder = os.path.normpath(os.path.join(root_dir, prefix)) if prefix else os.path.normpath(root_dir)
            checked += 1
            problems += problems_in(os.path.join(root, folder), f"service {name} (folder {folder})")
    for p in problems:
        print(p, file=sys.stderr)
    if problems:
        print(f"check_render_install_scripts: {len(problems)} problem(s). Remove {FLAG} for that service, or the package.", file=sys.stderr)
        return 1
    print(f"check_render_install_scripts: {checked} install(s) with {FLAG} checked; none needs a script")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
