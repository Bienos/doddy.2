"""Doddy's brand for Studio files (Brand Guidelines V2.2, DoddyDesignTokens).

Imported by the doddy-docs and doddy-infographic renderers. Plain Python; matplotlib and reportlab are
imported only by the functions that need them.

Rules this module carries:
- Orange (#FF6A00) is decoration only: bars, rules, dots. It is never a text colour (contrast 2.7:1 on paper).
- Text colours are ink, accent text and secondary text, each at least 4.5:1 on paper.
- No font file ships with the skill: the fonts come from what the container already has (DejaVu Sans,
  bundled with matplotlib), so Polish letters render.
"""
from __future__ import annotations

import os

# ---------------------------------------------------------------- colours

PAPER = "#FFF7E9"      # background (paper and character cream)
INK = "#171715"        # body and headline text
ORANGE = "#FF6A00"     # decoration only, never text
ACCENT_TEXT = "#A64B00"  # the orange family when it has to be text
SECONDARY = "#5E584F"  # captions, source lines, axis labels
NIGHT = "#16171C"      # dark surfaces (not used on paper)
GREEN = "#326746"
MUTED = "#B9AE9D"      # gridlines, quiet fills
QUIET_SURFACE = "#F3E6CF"  # the summary box behind the answer

#: The only colours text may use.
TEXT_COLOURS = (INK, ACCENT_TEXT, SECONDARY)
#: Chart series, in order. Fills, not text.
SERIES = (ORANGE, INK, GREEN, MUTED, ACCENT_TEXT, SECONDARY, "#FFB27A", "#D9CDBB")

# ---------------------------------------------------------------- type scale (px on a 1080-wide canvas)

TYPE = {
    "label": 22,      # small caps-style label at the top
    "headline": 56,   # the headline fact
    "fact": 30,
    "chart_title": 28,
    "chart_text": 22,  # tick labels, value labels, legend
    "source": 22,
}
#: Nothing in the infographic is smaller than this (the server checks it).
MIN_TEXT_PX = 22

# ---------------------------------------------------------------- contrast (WCAG 2.x)


def _channel(c: float) -> float:
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hex_colour: str) -> float:
    h = hex_colour.lstrip("#")
    if len(h) == 3:
        h = "".join(ch * 2 for ch in h)
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b)


def contrast(a: str, b: str) -> float:
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


# ---------------------------------------------------------------- fonts


def font_dirs() -> list[str]:
    """Where DejaVu Sans can be found without downloading anything."""
    dirs = []
    try:
        import matplotlib

        dirs.append(os.path.join(os.path.dirname(matplotlib.__file__), "mpl-data", "fonts", "ttf"))
    except ImportError:
        pass
    dirs += ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/dejavu", "/usr/share/fonts/TTF"]
    return dirs


def find_font(file_name: str) -> str:
    for d in font_dirs():
        path = os.path.join(d, file_name)
        if os.path.isfile(path):
            return path
    raise FileNotFoundError(
        f"{file_name} not found in {font_dirs()}. Doddy's files need DejaVu Sans for Polish letters; "
        "don't fall back to Helvetica."
    )


def register_fonts() -> tuple[str, str]:
    """Registers DejaVu Sans (regular, bold) with reportlab. Returns (regular, bold) font names."""
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    regular, bold = "DoddySans", "DoddySans-Bold"
    if regular not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(TTFont(regular, find_font("DejaVuSans.ttf")))
        pdfmetrics.registerFont(TTFont(bold, find_font("DejaVuSans-Bold.ttf")))
        from reportlab.lib.fonts import addMapping

        addMapping(regular, 0, 0, regular)
        addMapping(regular, 1, 0, bold)
        addMapping(regular, 0, 1, regular)
        addMapping(regular, 1, 1, bold)
    return regular, bold


def apply_theme() -> None:
    """matplotlib defaults for Doddy's charts: paper, ink text, orange first, quiet grid."""
    import matplotlib as mpl
    from cycler import cycler

    mpl.rcParams.update({
        "font.family": "DejaVu Sans",
        "font.size": TYPE["chart_text"],
        "text.color": INK,
        "axes.labelcolor": SECONDARY,
        "axes.edgecolor": MUTED,
        "axes.facecolor": PAPER,
        "figure.facecolor": PAPER,
        "savefig.facecolor": PAPER,
        "axes.prop_cycle": cycler(color=list(SERIES)),
        "axes.grid": False,
        "grid.color": MUTED,
        "grid.linewidth": 1,
        "xtick.color": SECONDARY,
        "ytick.color": SECONDARY,
        "xtick.labelcolor": SECONDARY,
        "ytick.labelcolor": SECONDARY,
        "xtick.labelsize": TYPE["chart_text"],
        "ytick.labelsize": TYPE["chart_text"],
        "axes.spines.top": False,
        "axes.spines.right": False,
        # Real <text> elements in SVG, so the text stays text (and checkable).
        "svg.fonttype": "none",
        # Stable ids, so the same content gives the same SVG.
        "svg.hashsalt": "doddy-studio",
    })


def format_number(value: float, language: str) -> str:
    """12.5 → '12.5' (en) or '12,5' (pl); whole numbers without decimals; thousands spaced."""
    if abs(value - round(value)) < 1e-9:
        text = f"{int(round(value)):,}".replace(",", " " if language == "pl" else ",")
    else:
        text = f"{value:,.1f}"
        if language == "pl":
            text = text.replace(",", " ").replace(".", ",")
    return text
