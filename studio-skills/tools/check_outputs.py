#!/usr/bin/env python3
"""Checks rendered Studio files the way Doddy's server does (docs/implementation/STUDIO.md, "The files").

    python3 -I check_outputs.py --content content.json --dir OUT

brief.pdf: starts %PDF-, at most 15 MB, at least one page, no /JavaScript, /JS, /Launch or /EmbeddedFile.
infographic.svg: parses; no <script>, <image> or <foreignObject>, no on* handlers, no href that leaves the
file; every <text> (and <tspan>) resolves a font-size and fill from its own attributes or style, else the
nearest ancestor <g>, else 16 and #000000; every size >= 22, every fill one of ink, accent text or
secondary and at least 4.5:1 on paper; the headline and each fact appear in the text nodes joined in
document order with single spaces (whitespace collapsed); <title> and <desc> carry the alt text.
infographic.png 1080x1350 and infographic-a4.png 1240x1754, by the PNG header.
Exit status 0 when everything passes, 1 otherwise.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

PAPER = "#FFF7E9"
TEXT_FILLS = {"#171715", "#A64B00", "#5E584F"}
MIN_FONT = 22
MAX_PDF = 15 * 1024 * 1024
PNGS = {"infographic.png": (1080, 1350), "infographic-a4.png": (1240, 1754)}


def collapse(s: str) -> str:
    return " ".join((s or "").split())


def luminance(hex_colour: str) -> float:
    h = hex_colour.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4  # noqa: E731
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a: str, b: str) -> float:
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def style_of(el) -> dict:
    out = {}
    for part in (el.get("style") or "").split(";"):
        if ":" in part:
            k, v = part.split(":", 1)
            out[k.strip().lower()] = v.strip()
    return out


def own(el, prop: str) -> str | None:
    if el.get(prop) is not None:
        return el.get(prop)
    return style_of(el).get(prop)


def check_pdf(path: Path) -> list[str]:
    data = path.read_bytes()
    errors = []
    if not data.startswith(b"%PDF-"):
        errors.append("brief.pdf doesn't start with %PDF-")
    if len(data) > MAX_PDF:
        errors.append(f"brief.pdf is {len(data)} bytes (over 15 MB)")
    if len(re.findall(rb"/Type\s*/Page(?![A-Za-z])", data)) < 1:
        errors.append("brief.pdf has no pages")
    for name in (rb"/JavaScript", rb"/JS", rb"/Launch", rb"/EmbeddedFile"):
        if re.search(re.escape(name) + rb"(?![A-Za-z])", data):
            errors.append(f"brief.pdf contains {name.decode()}")
    return errors


def check_svg(path: Path, info: dict) -> list[str]:
    raw = path.read_text(encoding="utf-8")
    errors = []
    if "<!DOCTYPE" in raw or "<!ENTITY" in raw:
        return ["infographic.svg declares a DOCTYPE or ENTITY"]
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as e:
        return [f"infographic.svg doesn't parse: {e}"]
    if local(root.tag) != "svg":
        return ["infographic.svg's root isn't <svg>"]
    if " ".join((root.get("viewBox") or "").split()) != "0 0 1080 1350":
        errors.append(f"viewBox is {root.get('viewBox')!r}, not '0 0 1080 1350'")

    parents = {child: parent for parent in root.iter() for child in parent}
    for el in root.iter():
        tag = local(el.tag)
        if tag in {"script", "image", "foreignObject"}:
            errors.append(f"<{tag}> is not allowed")
        for k, v in el.attrib.items():
            name = local(k)
            if name.lower().startswith("on"):
                errors.append(f"event handler {name} on <{tag}>")
            if name == "href" and not v.startswith("#"):
                errors.append(f"external href {v!r} on <{tag}>")
            if "url(" in v and not re.fullmatch(r".*url\(\s*#[^)]*\).*", v, re.S):
                errors.append(f"external url() in {name} on <{tag}>")

    def resolve(el, prop: str, default: str) -> str:
        v = own(el, prop)
        node = parents.get(el)
        while v is None and node is not None:
            if local(node.tag) == "g":
                v = own(node, prop)
            node = parents.get(node)
        return v if v is not None else default

    nodes: list[str] = []
    for el in root.iter():
        if local(el.tag) not in {"text", "tspan"}:
            continue
        if el.text and el.text.strip():
            nodes.append(el.text)
        size_raw = resolve(el, "font-size", "16")
        fill = resolve(el, "fill", "#000000").strip().upper()
        try:
            size = float(size_raw.replace("px", ""))
        except ValueError:
            size = 0.0
        sample = collapse(el.text or "")[:40]
        if size < MIN_FONT:
            errors.append(f"text {sample!r} is {size_raw} (under {MIN_FONT})")
        if fill not in TEXT_FILLS:
            errors.append(f"text {sample!r} has fill {fill} (text may only be ink, accent text or secondary)")
        elif contrast(fill, PAPER) < 4.5:
            errors.append(f"text {sample!r} has contrast {contrast(fill, PAPER):.2f}:1 on paper")
    joined = collapse(" ".join(nodes))
    for label, text in [("headline", info["headline"]["text"])] + [(f"fact {i + 1}", f["text"]) for i, f in enumerate(info["facts"])]:
        if collapse(text) not in joined:
            errors.append(f"the {label} isn't in the SVG's text: {collapse(text)[:60]!r}")
    alt = collapse(info.get("altText", ""))
    title = next((el for el in root if local(el.tag) == "title"), None)
    desc = next((el for el in root if local(el.tag) == "desc"), None)
    if title is None or not collapse(title.text or ""):
        errors.append("no <title>")
    if desc is None or collapse(desc.text or "") != alt:
        errors.append("<desc> doesn't carry the alt text")
    return errors


def check_png(path: Path, size: tuple[int, int]) -> list[str]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return [f"{path.name} isn't a PNG"]
    w, h = struct.unpack(">II", data[16:24])
    return [] if (w, h) == size else [f"{path.name} is {w}x{h}, not {size[0]}x{size[1]}"]


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--content", required=True)
    p.add_argument("--dir", required=True)
    a = p.parse_args(argv)
    content = json.loads(Path(a.content).read_text(encoding="utf-8"))
    out = Path(a.dir)
    errors: list[str] = []
    expected = {"brief.pdf", "infographic.svg", *PNGS}
    found = {f.name for f in out.iterdir() if f.is_file()}
    errors += [f"missing {n}" for n in sorted(expected - found)]
    if "brief.pdf" in found:
        errors += check_pdf(out / "brief.pdf")
    if "infographic.svg" in found:
        errors += check_svg(out / "infographic.svg", content["infographic"])
    for name, size in PNGS.items():
        if name in found:
            errors += check_png(out / name, size)
    for e in errors:
        print(f"FAIL {out}: {e}")
    if not errors:
        print(f"PASS {out}: brief.pdf, infographic.svg, infographic.png, infographic-a4.png")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
