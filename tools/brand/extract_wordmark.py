"""The app's wordmark from Brand Guidelines V2.2 (ADR-562).

The guide's logo is the "Doddy" wordmark in Caveat Bold, option C "NOTE", the one it recommends
and puts on its cover (p.1, p.18). Page 18 sets it as five glyphs in ink #171715. pdftocairo turns
those glyphs into outlines, and this script keeps only them: each glyph's path is moved to where
the page places it, and the five are written as plain SVG paths in a box fitted to the ink. No
font file is written or bundled, and nothing is redrawn: the curves are the PDF's own.

    python3 -I tools/brand/extract_wordmark.py <repo root>

Needs pdftocairo (poppler-utils). Refuses a PDF whose SHA-256 differs from the one in
design/brand-v2.2/README.md.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

PDF = "design/brand-v2.2/DODDY_Brand_Guidelines_V2.2_review_draft.pdf"
PDF_SHA256 = "ee3007b7ad858e861425dac7b032b57dfc2b124ad4c5615a9b18353a9f73da35"
PAGE = 18
CROP = ["-x", "480", "-y", "400", "-W", "140", "-H", "80"]  # points: the "C / NOTE" wordmark only
INK = "#171715"  # brand.ink (p.20); the asset is a template, so the app colours it
PAD = 2.0  # points of air around the ink
IMAGESET = "DoddyApp/Resources/Assets.xcassets/DoddyWordmark.imageset"

TOKEN = re.compile(r"[MLCZ]|-?\d+(?:\.\d+)?(?:e-?\d+)?")


def glyph_outlines(svg):
    """{glyph id: path data} from cairo's <defs>, and the placed glyphs [(id, x, y)]."""
    defs = dict(re.findall(r'<g id="(glyph-[\d-]+)">\s*<path d="([^"]*)"', svg))
    groups = re.findall(r'<g fill="[^"]*" fill-opacity="1">(.*?)</g>', svg, re.S)
    placed = [
        (ref, float(x), float(y))
        for group in groups
        for ref, x, y in re.findall(r'<use xlink:href="#([^"]+)" x="([^"]+)" y="([^"]+)"/>', group)
    ]
    return defs, placed


def moved(data, dx, dy):
    """The glyph's path with every point shifted, and the curve's sampled points (for the box)."""
    out, points, numbers, command = [], [], [], None
    current = (0.0, 0.0)

    def flush():
        nonlocal current
        if command is None:
            return
        pairs = [(numbers[i] + dx, numbers[i + 1] + dy) for i in range(0, len(numbers), 2)]
        if command == "C":
            for start in range(0, len(pairs), 3):
                p1, p2, p3 = pairs[start:start + 3]
                for step in range(1, 21):
                    t = step / 20
                    u = 1 - t
                    points.append((
                        u ** 3 * current[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                        u ** 3 * current[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1],
                    ))
                current = p3
        elif pairs:
            points.extend(pairs)
            current = pairs[-1]
        out.append(command + " " + " ".join(f"{x:.3f} {y:.3f}" for x, y in pairs))

    for token in TOKEN.findall(data):
        if token in "MLCZ":
            flush()
            command, numbers = token, []
            if token == "Z":
                out.append("Z")
                command = None
        else:
            numbers.append(float(token))
    flush()
    return " ".join(part.strip() for part in out), points


def main(repo):
    pdf = os.path.join(repo, PDF)
    digest = hashlib.sha256(open(pdf, "rb").read()).hexdigest()
    if digest != PDF_SHA256:
        raise SystemExit(f"{PDF} has SHA-256 {digest}, expected {PDF_SHA256}")
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "page.svg")
        subprocess.run(["pdftocairo", "-svg", "-f", str(PAGE), "-l", str(PAGE), *CROP, pdf, out], check=True)
        svg = open(out, encoding="utf-8").read()
    defs, placed = glyph_outlines(svg)
    if [ref for ref, _, _ in placed] != ["glyph-0-0", "glyph-0-1", "glyph-0-2", "glyph-0-2", "glyph-0-3"]:
        raise SystemExit(f"expected the five glyphs of 'Doddy' (D o d d y), found {placed}")
    paths, points = [], []
    for ref, x, y in placed:
        data, sampled = moved(defs[ref], x, y)
        paths.append(data)
        points.extend(sampled)
    left = min(p[0] for p in points) - PAD
    top = min(p[1] for p in points) - PAD
    width = max(p[0] for p in points) + PAD - left
    height = max(p[1] for p in points) + PAD - top
    body = "\n".join(f'  <path d="{moved(data, -left, -top)[0]}"/>' for data in paths)
    result = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<!-- "Doddy", Caveat Bold, Brand Guidelines V2.2 p.18 option C (ADR-562). '
        f'Made by tools/brand/extract_wordmark.py; do not edit by hand. -->\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.3f}" height="{height:.3f}" '
        f'viewBox="0 0 {width:.3f} {height:.3f}">\n'
        f'<g fill="{INK}">\n{body}\n</g>\n</svg>\n'
    )
    folder = os.path.join(repo, IMAGESET)
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "wordmark.svg"), "w", encoding="utf-8") as f:
        f.write(result)
    contents = {
        "images": [{"filename": "wordmark.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }
    with open(os.path.join(folder, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")
    print(f"{IMAGESET}/wordmark.svg: {width:.1f} x {height:.1f} pt, aspect {width / height:.4f}")


if __name__ == "__main__":
    main(sys.argv[1])
