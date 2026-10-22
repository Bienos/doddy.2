#!/usr/bin/env python3
"""Checks every skill under studio-skills/ before it is uploaded (STUDIO.md, Agent Skills limits).

    python3 -I check_skills.py STUDIO_SKILLS_DIR

- each `doddy-*` folder has a SKILL.md with YAML frontmatter;
- `name` equals the folder name, at most 64 characters of lowercase letters, digits and hyphens, no
  XML tags and no reserved word ("anthropic", "claude");
- `description` is not empty, at most 1,024 characters, no XML tags;
- each skill is under 30 MB uncompressed, counting every file it would upload;
- no font or image file anywhere under studio-skills/ unless listed in allowed-assets.txt;
- no __pycache__ or .pyc file inside a skill (they'd be uploaded).
Exit 0 when all pass.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

MAX_BYTES = 30 * 1024 * 1024
ASSET_EXT = {".ttf", ".otf", ".woff", ".woff2", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"}
NAME = re.compile(r"^[a-z0-9-]{1,64}$")


def frontmatter(text: str) -> dict[str, str] | None:
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end < 0:
        return None
    out: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if ":" in line and not line.startswith((" ", "\t")):
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def main(root: Path) -> int:
    errors: list[str] = []
    allowed = {
        line.strip() for line in (root / "allowed-assets.txt").read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    } if (root / "allowed-assets.txt").exists() else set()
    for f in sorted(root.rglob("*")):
        if f.is_file() and f.suffix.lower() in ASSET_EXT and str(f.relative_to(root)) not in allowed:
            errors.append(f"{f.relative_to(root)}: font or image file not in allowed-assets.txt")

    skills = sorted(d for d in root.iterdir() if d.is_dir() and d.name.startswith("doddy-"))
    if not skills:
        errors.append("no doddy-* skills found")
    for d in skills:
        md = d / "SKILL.md"
        if not md.is_file():
            errors.append(f"{d.name}: no SKILL.md")
            continue
        fm = frontmatter(md.read_text(encoding="utf-8"))
        if fm is None:
            errors.append(f"{d.name}: SKILL.md has no frontmatter")
            continue
        name, desc = fm.get("name", ""), fm.get("description", "")
        if name != d.name:
            errors.append(f"{d.name}: name {name!r} differs from the folder")
        if not NAME.match(name):
            errors.append(f"{d.name}: name must be 1-64 lowercase letters, digits or hyphens")
        if "anthropic" in name or "claude" in name:
            errors.append(f"{d.name}: name uses a reserved word")
        if not desc or len(desc) > 1024:
            errors.append(f"{d.name}: description is {len(desc)} characters (1 to 1,024)")
        if "<" in name + desc or ">" in name + desc:
            errors.append(f"{d.name}: XML tags in name or description")
        files = [f for f in d.rglob("*") if f.is_file()]
        for f in files:
            if "__pycache__" in f.parts or f.suffix == ".pyc":
                errors.append(f"{f.relative_to(root)}: compiled Python inside a skill")
        size = sum(f.stat().st_size for f in files)
        if size >= MAX_BYTES:
            errors.append(f"{d.name}: {size} bytes (30 MB limit)")
        if not any(e.startswith(d.name + ":") for e in errors):
            print(f"PASS skill {d.name}: frontmatter, {len(files)} files, {size} bytes")
    for e in errors:
        print(f"FAIL {e}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else "studio-skills")))
