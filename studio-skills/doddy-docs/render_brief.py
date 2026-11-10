#!/usr/bin/env python3
"""Doddy Studio research brief: content.json -> brief.pdf (A4).

    python3 render_brief.py --content content.json --out-dir "$OUTPUT_DIR"

The answer first, in a box; one section per sub-question, each point followed by the numbers of the
sources behind it; where sources disagree; how sure the brief is and what is still open; then the
numbered sources with the date each was fetched. Doddy's paper and ink, DejaVu Sans so Polish letters
render. content.json is data: nothing in it is run, and its text is escaped before layout.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape

LABELS = {
    "en": {
        "kicker": "DODDY STUDIO · RESEARCH BRIEF",
        "answer": "The answer",
        "disagree": "Where sources disagree",
        "confidence": "How sure this is",
        "levels": {"high": "High", "medium": "Medium", "low": "Low"},
        "confidence_note": "Doddy's judgement from the sources below; check them before relying on it.",
        "gaps": "What's still open",
        "sources": "Sources",
        "fetched": "fetched",
        "footer": "Made by Doddy Studio, {date}. Doddy is an AI. Every point lists the sources behind it.",
        "page": "Page",
    },
    "pl": {
        "kicker": "DODDY STUDIO · RAPORT",
        "answer": "Odpowiedź",
        "disagree": "Gdzie źródła się różnią",
        "confidence": "Na ile to pewne",
        "levels": {"high": "Wysoka pewność", "medium": "Średnia pewność", "low": "Niska pewność"},
        "confidence_note": "Ocena Doddy’ego na podstawie źródeł poniżej; sprawdź je, zanim na tym oprzesz decyzję.",
        "gaps": "Co pozostaje otwarte",
        "sources": "Źródła",
        "fetched": "pobrano",
        "footer": "Przygotowane przez Doddy Studio, {date}. Doddy to AI. Przy każdym punkcie są numery źródeł.",
        "page": "Strona",
    },
}

MONTHS_EN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


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


def _date(iso: str | None, language: str) -> str:
    try:
        d = datetime.fromisoformat((iso or "").replace("Z", "+00:00"))
    except ValueError:
        return iso or ""
    return f"{d.day:02d}.{d.month:02d}.{d.year}" if language == "pl" else f"{d.day} {MONTHS_EN[d.month - 1]} {d.year}"


def _load(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        content = json.load(f)
    for key in ("title", "answer", "sections", "sources", "claims"):
        if key not in content:
            raise SystemExit(f"content.json has no {key}")
    sources = {s["id"] for s in content["sources"]}
    claims = {c["id"]: c for c in content["claims"]}
    for c in claims.values():
        if c.get("source") not in sources:
            raise SystemExit(f"claim {c.get('id')} names a source that isn't listed")
    for section in content["sections"]:
        for point in section.get("points", []):
            for cid in point.get("claims", []):
                if cid not in claims:
                    raise SystemExit(f"a point names claim {cid}, which isn't in the pack")
    return content


def build(content: dict, out: Path, brand) -> Path:
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_LEFT
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import (
        KeepTogether, ListFlowable, ListItem, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle,
    )

    regular, bold = brand.register_fonts()
    language = content.get("language") if content.get("language") in LABELS else "en"
    L = LABELS[language]
    ink = colors.HexColor(brand.INK)
    secondary = colors.HexColor(brand.SECONDARY)
    accent = colors.HexColor(brand.ACCENT_TEXT)

    def style(name, size, leading, font=regular, colour=ink, space_before=0, space_after=0, **kw):
        return ParagraphStyle(name, fontName=font, fontSize=size, leading=leading, textColor=colour,
                              spaceBefore=space_before, spaceAfter=space_after, alignment=TA_LEFT, **kw)

    S = {
        "kicker": style("kicker", 8.5, 11, bold, secondary, space_after=6),
        "title": style("title", 24, 29, bold, ink, space_after=12),
        "label": style("label", 9, 12, bold, accent, space_after=3),
        "answer": style("answer", 12.5, 18, regular, ink),
        "h2": style("h2", 14, 18, bold, ink, space_before=14, space_after=6),
        "body": style("body", 10.5, 15, regular, ink),
        "small": style("small", 8.5, 12, regular, secondary),
        "source": style("source", 9, 13, regular, ink, space_after=4),
    }

    # Sources are numbered in the order points first use them; unused ones follow.
    claims = {c["id"]: c for c in content["claims"]}
    order: list[str] = []

    def use(cids):
        for cid in cids:
            sid = claims[cid]["source"]
            if sid not in order:
                order.append(sid)

    for section in content["sections"]:
        for point in section.get("points", []):
            use(point.get("claims", []))
    for d in content.get("disagreements", []):
        use([c for c in d.get("claims", []) if c in claims])
    for s in content["sources"]:
        if s["id"] not in order:
            order.append(s["id"])
    number = {sid: i + 1 for i, sid in enumerate(order)}

    def marks(cids) -> str:
        nums = sorted({number[claims[c]["source"]] for c in cids if c in claims})
        if not nums:
            return ""
        return f' <font size="7.5" color="{brand.ACCENT_TEXT}"><super>[{", ".join(map(str, nums))}]</super></font>'

    story = [Paragraph(escape(L["kicker"]), S["kicker"]), Paragraph(escape(content["title"]), S["title"])]

    box = Table([[Paragraph(escape(L["answer"]).upper(), S["label"])], [Paragraph(escape(content["answer"]), S["answer"])]],
                colWidths=[170 * mm])
    box.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor(brand.QUIET_SURFACE)),
        ("LINEBEFORE", (0, 0), (0, -1), 4, colors.HexColor(brand.ORANGE)),
        ("LEFTPADDING", (0, 0), (-1, -1), 12), ("RIGHTPADDING", (0, 0), (-1, -1), 12),
        ("TOPPADDING", (0, 0), (-1, 0), 10), ("BOTTOMPADDING", (0, -1), (-1, -1), 12),
    ]))
    story += [box, Spacer(1, 6)]

    def bullets(items):
        return ListFlowable(
            [ListItem(Paragraph(text, S["body"]), leftIndent=14, value="circle") for text in items],
            bulletType="bullet", start="•", leftIndent=14, bulletColor=colors.HexColor(brand.ORANGE),
            bulletFontName=bold, bulletFontSize=10, spaceBefore=2)

    for section in content["sections"]:
        points = [escape(p["text"]) + marks(p.get("claims", [])) for p in section.get("points", [])]
        story.append(KeepTogether([Paragraph(escape(section["heading"]), S["h2"]), bullets(points)]))

    if content.get("disagreements"):
        items = [escape(d["text"]) + marks(d.get("claims", [])) for d in content["disagreements"]]
        story.append(KeepTogether([Paragraph(escape(L["disagree"]), S["h2"]), bullets(items)]))

    level = L["levels"].get(content.get("confidence", ""), "")
    if level:
        story.append(KeepTogether([
            Paragraph(escape(L["confidence"]), S["h2"]),
            Paragraph(f"<b>{escape(level)}.</b> {escape(L['confidence_note'])}", S["body"]),
        ]))
    if content.get("gaps"):
        story.append(KeepTogether([Paragraph(escape(L["gaps"]), S["h2"]), bullets([escape(g) for g in content["gaps"]])]))

    by_id = {s["id"]: s for s in content["sources"]}
    entries = []
    for sid in order:
        s = by_id[sid]
        url = escape(s["url"])
        entries.append(Paragraph(
            f'<b>{number[sid]}.</b> {escape(s.get("title") or s["url"])}<br/>'
            f'<font color="{brand.SECONDARY}">{url} · {escape(L["fetched"])} {escape(_date(s.get("fetchedAt"), language))}</font>',
            S["source"]))
    # The heading never sits alone at the foot of a page.
    story.append(KeepTogether([Paragraph(escape(L["sources"]), S["h2"]), *entries[:2]]))
    story += entries[2:]

    made = _date(datetime.now(timezone.utc).isoformat(), language)
    footer = L["footer"].format(date=made)

    def page(canvas, doc):
        canvas.saveState()
        w, h = A4
        canvas.setFillColor(colors.HexColor(brand.PAPER))
        canvas.rect(0, 0, w, h, stroke=0, fill=1)
        canvas.setFillColor(colors.HexColor(brand.ORANGE))
        canvas.rect(20 * mm, h - 14 * mm, 18 * mm, 1.6 * mm, stroke=0, fill=1)
        canvas.setFont(regular, 7.5)
        canvas.setFillColor(secondary)
        canvas.drawString(20 * mm, 10 * mm, footer)
        canvas.drawRightString(w - 20 * mm, 10 * mm, f"{L['page']} {doc.page}")
        canvas.restoreState()

    path = out / "brief.pdf"
    doc = SimpleDocTemplate(
        str(path), pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm, topMargin=22 * mm, bottomMargin=20 * mm,
        title=content["title"], author="Doddy Studio", subject=content["answer"][:200], creator="Doddy Studio (doddy-docs)",
        lang=language)
    doc.build(story, onFirstPage=page, onLaterPages=page)
    return path


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--content", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--brand-dir")
    a = p.parse_args(argv)
    sys.path.insert(0, str(_brand_dir(a.brand_dir)))
    import brand  # noqa: E402

    content = _load(a.content)
    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    path = build(content, out, brand)
    print(f"wrote {path} ({path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
