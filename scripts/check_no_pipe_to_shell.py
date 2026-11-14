#!/usr/bin/env python3
"""Fail when a tracked file downloads something and runs it at once.

`curl ... | sh`, `bash <(curl ...)`, `sh -c "$(curl ...)"` and `eval "$(curl ...)"` run whatever the server
sends before anyone, or any checksum, has seen it. Download to a file, check its SHA-256, then run it
(scripts/install_xcodegen.sh does that). Reading JSON or text from a download, hashing it and unpacking an
archive are not touched.

    python3 -I scripts/check_no_pipe_to_shell.py [--root DIR]

Looks at every tracked file (all files under --root when it isn't a git checkout) except history kept for
reference (reference/, docs/archive/), node_modules/, and this check and its test. Prints `path:line: kind`
for each hit and nothing from the line itself, because a line can hold a token. Exits 1 on any hit.
"""
import argparse
import os
import re
import subprocess
import sys

SHELL = r"(?:ba|z|da|k)?sh"
FETCH = r"(?:curl|wget)"
KINDS = (
    ("a download piped into a shell",
     re.compile(rf"\b{FETCH}\b(?:(?!&&|;).)*\|[ \t]*(?:sudo\b(?:[ \t]+-\S+)*[ \t]+)?(?:/(?:usr/)?bin/)?{SHELL}(?![\w.-])")),
    ("a download read by a shell through process substitution",
     re.compile(rf"(?:\b{SHELL}\b|\bsource\b|(?<![\w.-])\.)[ \t]+<\([ \t]*{FETCH}\b")),
    ("a download run through command substitution",
     re.compile(rf"\b(?:{SHELL}|eval)\b[ \t]+(?:-\w+[ \t]+)*[\"']?(?:\$\(|`)[ \t]*{FETCH}\b")),
)
SKIP_PREFIXES = ("reference/", "docs/archive/")
SKIP_PARTS = ("node_modules",)
SELF = ("scripts/check_no_pipe_to_shell.py", "scripts/test_check_no_pipe_to_shell.sh")


def tracked_files(root):
    if os.path.isdir(os.path.join(root, ".git")) or os.path.isfile(os.path.join(root, ".git")):
        try:
            out = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True).stdout
            return [p for p in out.decode("utf-8", "replace").split("\0") if p]
        except (OSError, subprocess.CalledProcessError):
            pass
    found = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in (".git",) + SKIP_PARTS]
        for name in files:
            found.append(os.path.relpath(os.path.join(base, name), root).replace(os.sep, "/"))
    return found


def skipped(rel):
    return (rel in SELF or rel.startswith(SKIP_PREFIXES)
            or any(part in SKIP_PARTS for part in rel.split("/")))


def scan(root):
    hits = []
    for rel in sorted(tracked_files(root)):
        if skipped(rel):
            continue
        path = os.path.join(root, rel)
        try:
            with open(path, "rb") as f:
                data = f.read()
        except OSError:
            continue
        if b"\0" in data[:8192]:
            continue
        for number, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
            for kind, pattern in KINDS:
                if pattern.search(line):
                    hits.append((rel, number, kind))
                    break
    return hits


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    root = os.path.abspath(ap.parse_args(argv).root)
    hits = scan(root)
    for rel, number, kind in hits:
        print(f"{rel}:{number}: {kind}", file=sys.stderr)
    if hits:
        print(f"check_no_pipe_to_shell: {len(hits)} hit(s). Download to a file, check its SHA-256, then run it.", file=sys.stderr)
        return 1
    print("check_no_pipe_to_shell: no tracked file pipes a download into a shell")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
