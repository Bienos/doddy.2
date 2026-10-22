#!/usr/bin/env python3
"""Doddy Studio infographic: content.json -> infographic.svg, infographic.png, infographic-a4.png.

    python3 render_infographic.py --content content.json --out-dir "$OUTPUT_DIR"

One layout, drawn with matplotlib (Agg) on Doddy's paper: a small label, the headline fact, an orange
rule, 3 to 7 facts, one chart (bar, column, line or donut) and a source line. The phone canvas is
1080 x 1350; the print canvas is A4 at 150 dpi (1240 x 1754). The SVG keeps every line of text as its
own <text> element with an explicit font-size and fill, carries the alt text in <title> and <desc>, and
has no scripts, images or external links. content.json is data: nothing in it is run.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

PHONE = (1080, 1350)
A4 = (1240, 1754)
DPI = 72  # 1 pt == 1 px, so font sizes in points are SVG user units


def _brand_dir(explicit: str | None) -> Path:
    candidates = [Path(explicit)] if explicit else []
    if os.environ.get("DODDY_BRAND_DIR"):
        candidates.append(Path(os.environ["DODDY_BRAND_DIR"]))
    here = Path(__file__).resolve().parent
    candidates += [here.parent / "doddy-brand", Path("/skills/doddy-brand")]
    candidates += sorted(Path("/skills").glob("*/brand.py")) if Path("/skills").is_dir() else []
    for c in candidates:
        c = c.parent if c.name == "brand.py" else c
        if (c / "brand.py").is_file():
            return c
    raise SystemExit("doddy-brand not found: pass --brand-dir with the doddy-brand skill's folder")


def _load(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        content = json.load(f)
    info = content.get("infographic")
    if not isinstance(info, dict):
        raise SystemExit("content.json has no infographic")
    facts = info.get("facts") or []
    if not 3 <= len(facts) <= 7:
        raise SystemExit(f"the infographic needs 3 to 7 facts, got {len(facts)}")
    chart = info.get("chart") or {}
    if chart.get("kind") not in {"bar", "column", "line", "donut"}:
        raise SystemExit(f"unknown chart kind {chart.get('kind')!r}")
    data = chart.get("data") or []
    if not 2 <= len(data) <= 8:
        raise SystemExit("the chart needs 2 to 8 rows")
    for row in data:
        if not isinstance(row.get("value"), (int, float)) or row["value"] != row["value"]:
            raise SystemExit("chart values must be numbers")
        if chart["kind"] == "donut" and row["value"] < 0:
            raise SystemExit("donut values can't be negative")
    if not (info.get("altText") or "").strip():
        raise SystemExit("the infographic needs alt text")
    return content


class Canvas:
    """Draws on one figure in pixel coordinates, y growing downwards."""

    def __init__(self, brand, size: tuple[int, int]):
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib.font_manager import FontProperties

        self.brand = brand
        self.W, self.H = size
        self.s = self.W / PHONE[0]
        self.fig = plt.figure(figsize=(self.W / DPI, self.H / DPI), dpi=DPI)
        self.fig.patch.set_facecolor(brand.PAPER)
        self.ax = self.fig.add_axes((0, 0, 1, 1))
        self.ax.set_xlim(0, self.W)
        self.ax.set_ylim(self.H, 0)
        self.ax.axis("off")
        self.renderer = self.fig.canvas.get_renderer()
        self.FontProperties = FontProperties

    def px(self, v: float) -> float:
        return v * self.s

    def width(self, text: str, size: float, bold: bool = False) -> float:
        prop = self.FontProperties(family="DejaVu Sans", size=size, weight="bold" if bold else "normal")
        w, _, _ = self.renderer.get_text_width_height_descent(text, prop, ismath=False)
        return w

    def wrap(self, text: str, size: float, max_width: float, bold: bool = False) -> list[str]:
        """Greedy wrap at spaces only (never hyphenated), so the joined lines equal the text."""
        words = " ".join(text.split()).split(" ")
        lines: list[str] = []
        line = ""
        for word in words:
            trial = f"{line} {word}" if line else word
            if not line or self.width(trial, size, bold) <= max_width:
                line = trial
            else:
                lines.append(line)
                line = word
        if line:
            lines.append(line)
        return lines

    def text(self, x: float, y: float, s: str, size: float, colour: str, bold: bool = False, ha: str = "left", va: str = "top"):
        assert colour in self.brand.TEXT_COLOURS, f"{colour} is not a text colour"
        self.ax.text(x, y, s, fontsize=size, color=colour, fontweight="bold" if bold else "normal",
                     ha=ha, va=va, family="DejaVu Sans")

    def lines(self, x: float, y: float, lines: list[str], size: float, colour: str, bold: bool, leading: float) -> float:
        for i, line in enumerate(lines):
            self.text(x, y + i * size * leading, line, size, colour, bold)
        return len(lines) * size * leading


def _kicker(language: str) -> str:
    return "DODDY STUDIO · RAPORT" if language == "pl" else "DODDY STUDIO · RESEARCH BRIEF"


def _layout(c: Canvas, info: dict, language: str, headline_size: float, fact_size: float, draw: bool) -> float:
    """Lays the top part out (or only measures it). Returns the y where the chart may start."""
    b = c.brand
    m = c.px(72)
    width = c.W - 2 * m
    y = m
    if draw:
        c.text(m, y, _kicker(language), c.px(b.TYPE["label"]), b.SECONDARY, bold=True)
    y += c.px(b.TYPE["label"]) + c.px(30)

    headline = c.wrap(info["headline"]["text"], headline_size, width, bold=True)
    if draw:
        c.lines(m, y, headline, headline_size, b.INK, True, 1.16)
    y += len(headline) * headline_size * 1.16 + c.px(22)
    if draw:
        from matplotlib.patches import Rectangle

        c.ax.add_patch(Rectangle((m, y), c.px(120), c.px(8), color=b.ORANGE, lw=0))
    y += c.px(8) + c.px(38)

    numbered = bool(info.get("numbered"))
    indent = c.px(64) if numbered else c.px(40)
    for i, fact in enumerate(info["facts"]):
        lines = c.wrap(fact["text"], fact_size, width - indent)
        if draw:
            from matplotlib.patches import Circle

            mid = y + fact_size * 0.55
            if numbered:
                r = c.px(21)
                c.ax.add_patch(Circle((m + r, mid), r, color=b.ORANGE, lw=0))
                c.text(m + r, mid, str(i + 1), c.px(b.TYPE["chart_text"]), b.INK, bold=True, ha="center", va="center")
            else:
                c.ax.add_patch(Circle((m + c.px(9), mid), c.px(8), color=b.ORANGE, lw=0))
            c.lines(m + indent, y, lines, fact_size, b.INK, False, 1.3)
        y += len(lines) * fact_size * 1.3 + c.px(20)
    return y + c.px(18)


def _source_block(c: Canvas, info: dict) -> tuple[list[str], float]:
    size = c.px(c.brand.TYPE["source"])
    lines = c.wrap(info["sourceLine"], size, c.W - 2 * c.px(72))[:3]
    return lines, size


def _chart(c: Canvas, chart: dict, language: str, top: float, bottom: float) -> None:
    b = c.brand
    m = c.px(72)
    width = c.W - 2 * m
    title_size = c.px(b.TYPE["chart_title"])
    small = c.px(b.TYPE["chart_text"])
    title = chart["title"] + (f" ({chart['unit']})" if chart.get("unit") else "")
    title_lines = c.wrap(title, title_size, width, bold=True)
    title_h = len(title_lines) * title_size * 1.2 + c.px(18)
    # A calm chart: never taller than this; spare room is shared above and below it.
    max_plot = c.px(560)
    spare = (bottom - top - title_h) - max_plot
    if spare > 0:
        top += spare / 2
        bottom -= spare / 2
    top += c.lines(m, top, title_lines, title_size, b.INK, True, 1.2) + c.px(18)

    labels = [str(r["label"]) for r in chart["data"]]
    values = [float(r["value"]) for r in chart["data"]]
    fmt = lambda v: b.format_number(v, language)  # noqa: E731
    kind = chart["kind"]
    height = bottom - top

    def axes(left: float, right: float, top_: float, bottom_: float):
        ax = c.fig.add_axes((left / c.W, 1 - bottom_ / c.H, (right - left) / c.W, (bottom_ - top_) / c.H))
        ax.set_facecolor(b.PAPER)
        ax.tick_params(labelsize=small, labelcolor=b.SECONDARY, colors=b.MUTED, length=0, pad=c.px(10))
        for side in ("top", "right"):
            ax.spines[side].set_visible(False)
        ax.spines["left"].set_color(b.MUTED)
        ax.spines["bottom"].set_color(b.MUTED)
        return ax

    if kind == "bar":
        label_w = max(c.width(label, small) for label in labels) + c.px(16)
        value_w = max(c.width(fmt(v), small) for v in values) + c.px(16)
        ax = axes(m + label_w, c.W - m, top, bottom)
        ys = list(range(len(values)))[::-1]
        ax.barh(ys, values, color=b.ORANGE, height=0.58)
        ax.set_yticks(ys, labels)
        ax.set_xticks([])
        ax.spines["bottom"].set_visible(False)
        top_v = max(max(values), 0) or 1
        span_px = (c.W - m) - (m + label_w)
        ax.set_xlim(min(0, min(values)), top_v * (1 + value_w / max(span_px - value_w, 1)))
        for yy, v in zip(ys, values):
            ax.text(v, yy, " " + fmt(v), va="center", ha="left", fontsize=small, color=b.INK, family="DejaVu Sans")
    elif kind == "column":
        n = len(values)
        slot = width / n
        wrapped = ["\n".join(c.wrap(label, small, slot - c.px(10))[:2]) for label in labels]
        rows = max(lbl.count("\n") + 1 for lbl in wrapped)
        ax = axes(m, c.W - m, top + small * 1.6, bottom - rows * small * 1.25 - c.px(10))
        xs = list(range(n))
        ax.bar(xs, values, color=b.ORANGE, width=0.6)
        ax.set_xticks(xs, wrapped)
        ax.set_yticks([])
        ax.spines["left"].set_visible(False)
        ax.set_ylim(min(0, min(values)), max(max(values), 0) * 1.0 or 1)
        ax.margins(y=0)
        for xx, v in zip(xs, values):
            ax.text(xx, v, fmt(v), va="bottom", ha="center", fontsize=small, color=b.INK, family="DejaVu Sans")
        ax.set_clip_on(False)
        for t in ax.texts:
            t.set_clip_on(False)
    elif kind == "line":
        from matplotlib.ticker import FuncFormatter, MaxNLocator

        n = len(values)
        slot = width / n
        wrapped = ["\n".join(c.wrap(label, small, slot - c.px(6))[:2]) for label in labels]
        rows = max(lbl.count("\n") + 1 for lbl in wrapped)
        tick_w = max(c.width(fmt(v), small) for v in values) + c.px(20)
        ax = axes(m + tick_w, c.W - m - c.px(20), top + c.px(10), bottom - rows * small * 1.25 - c.px(10))
        xs = list(range(n))
        ax.plot(xs, values, color=b.ORANGE, lw=c.px(5), marker="o", ms=c.px(12), mfc=b.ORANGE, mec=b.PAPER, mew=c.px(3))
        ax.set_xticks(xs, wrapped)
        ax.yaxis.set_major_locator(MaxNLocator(4))
        ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: fmt(v)))
        ax.grid(axis="y", color=b.MUTED, lw=1)
        ax.set_axisbelow(True)
        ax.spines["left"].set_visible(False)
    else:  # donut
        from matplotlib.patches import Rectangle

        size = min(height, width * 0.5)
        ax = c.fig.add_axes((m / c.W, 1 - (top + size) / c.H, size / c.W, size / c.H))
        ax.pie(values, colors=list(b.SERIES[: len(values)]), startangle=90, counterclock=False,
               wedgeprops={"width": 0.38, "edgecolor": b.PAPER, "linewidth": c.px(3)})
        ax.set_aspect("equal")
        lx = m + size + c.px(36)
        ly = top + max(0.0, (size - len(values) * small * 2.1) / 2)
        legend_w = c.W - m - lx - c.px(40)
        total = sum(values) or 1
        for i, (label, v) in enumerate(zip(labels, values)):
            c.ax.add_patch(Rectangle((lx, ly + c.px(4)), c.px(22), c.px(22), color=b.SERIES[i], lw=0))
            pct = fmt(round(v / total * 100, 1)) + "%"
            shown = f"{fmt(v)}%" if (chart.get("unit") or "").strip() == "%" else f"{fmt(v)} ({pct})"
            line = c.wrap(f"{label}: {shown}", small, legend_w)[:2]
            ly += c.lines(lx + c.px(36), ly, line, small, b.INK, False, 1.2) + small * 0.8


def render(content: dict, size: tuple[int, int], brand):
    brand.apply_theme()
    c = Canvas(brand, size)
    info = content["infographic"]
    language = content.get("language") or "en"
    source_lines, source_size = _source_block(c, info)
    source_top = c.H - c.px(72) - len(source_lines) * source_size * 1.3
    chart_min = c.px(330)
    sizes = [(56, 30), (52, 28), (48, 27), (44, 26), (40, 24), (36, 22)]
    for hs, fs in sizes:
        y = _layout(c, info, language, c.px(hs), c.px(fs), draw=False)
        if source_top - c.px(36) - y >= chart_min or (hs, fs) == sizes[-1]:
            break
    y = _layout(c, info, language, c.px(hs), c.px(fs), draw=True)
    _chart(c, info["chart"], language, y, source_top - c.px(40))
    c.lines(c.px(72), source_top, source_lines, source_size, brand.SECONDARY, False, 1.3)
    return c.fig


# ---------------------------------------------------------------- SVG clean-up

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"


def _style(value: str) -> dict:
    out = {}
    for part in value.split(";"):
        if ":" in part:
            k, v = part.split(":", 1)
            out[k.strip()] = v.strip()
    return out


def _font_size(style: dict) -> str | None:
    if "font-size" in style:
        return style["font-size"].replace("px", "").strip()
    font = style.get("font", "")
    for token in font.split():
        if token.endswith("px"):
            return token[:-2]
    return None


def clean_svg(path: Path, alt: str, size: tuple[int, int]) -> None:
    ET.register_namespace("", SVG_NS)
    ET.register_namespace("xlink", XLINK_NS)
    tree = ET.parse(path)
    root = tree.getroot()
    q = lambda tag: f"{{{SVG_NS}}}{tag}"  # noqa: E731
    for meta in list(root.findall(q("metadata"))):
        root.remove(meta)
    w, h = size
    root.set("width", str(w))
    root.set("height", str(h))
    root.set("viewBox", f"0 0 {w} {h}")
    root.set("role", "img")
    root.set("aria-labelledby", "doddy-title doddy-desc")
    title = ET.Element(q("title"), {"id": "doddy-title"})
    title.text = alt
    desc = ET.Element(q("desc"), {"id": "doddy-desc"})
    desc.text = alt
    root.insert(0, desc)
    root.insert(0, title)
    for text in root.iter(q("text")):
        style = _style(text.get("style", ""))
        size_px = _font_size(style)
        fill = style.get("fill") or text.get("fill")
        if size_px is None or fill is None:
            raise SystemExit(f"a text element has no size or colour: {ET.tostring(text)[:120]!r}")
        weight = "bold" if ("bold" in style.get("font", "") or style.get("font-weight") in {"bold", "700"}) else "normal"
        anchor = style.get("text-anchor")
        text.attrib.pop("style", None)
        text.set("font-family", "DejaVu Sans, sans-serif")
        text.set("font-size", size_px)
        text.set("font-weight", weight)
        text.set("fill", fill.upper() if fill.startswith("#") else fill)
        if anchor:
            text.set("text-anchor", anchor)
    tree.write(path, encoding="utf-8", xml_declaration=True)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--content", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--brand-dir")
    a = p.parse_args(argv)
    sys.path.insert(0, str(_brand_dir(a.brand_dir)))
    import brand  # noqa: E402  (found above)

    content = _load(a.content)
    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    alt = " ".join(content["infographic"]["altText"].split())

    fig = render(content, PHONE, brand)
    svg = out / "infographic.svg"
    fig.savefig(svg, format="svg", dpi=DPI, metadata={"Date": None, "Creator": None, "Format": None, "Type": None})
    fig.savefig(out / "infographic.png", format="png", dpi=DPI)
    clean_svg(svg, alt, PHONE)

    import matplotlib.pyplot as plt

    plt.close(fig)
    fig = render(content, A4, brand)
    fig.savefig(out / "infographic-a4.png", format="png", dpi=DPI)
    plt.close(fig)
    for name in ("infographic.svg", "infographic.png", "infographic-a4.png"):
        print(f"wrote {out / name} ({(out / name).stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
