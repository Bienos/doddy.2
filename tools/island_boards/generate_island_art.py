#!/usr/bin/env python3
"""Turns the owner's Dynamic Island state SVGs into Swift drawing data.

Input: design/dynamic-island-v4/02-states/*.svg (byte-identical copies of the owner's
Doddy-Dynamic-Island-v4 pack, see design/dynamic-island-v4/SOURCE.md).
Output: Shared/IslandArt/IslandBoardArt.generated.swift

Only the drawing is taken: shapes, colours, stroke widths and Doddy's face. Text, buttons and
the right-hand signs (voice bars, dots, ticks, times) are left out because the native views draw
them from real state. Doddy's face becomes `.face(... expression)` so the island can change his
expression with the conversation; every expression must be one the pack itself uses.

Run from the repository root:  python3 -I tools/island_boards/generate_island_art.py
`scripts/check_island_art.sh` fails if the committed Swift file differs from a fresh run.
"""
import glob
import math
import os
import re
import sys
import xml.etree.ElementTree as ET

NS = "{http://www.w3.org/2000/svg}"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STATES = os.path.join(ROOT, "design", "dynamic-island-v4", "02-states")
OUT = os.path.join(ROOT, "Shared", "IslandArt", "IslandBoardArt.generated.swift")

# Every face in the pack: (eye ry, brow path, mouth path) -> expression.
FACES = {
    ("3.4", "M3-11Q8-16 12-11", "M-5 8Q4 17 12 5"): "listening",
    ("3.4", "M3-11Q8-16 12-11", "M-6 6Q3 16 12 3Q10 17 3 17Q-3 15-6 6Z"): "speaking",
    ("3.4", "M3-12Q8-18 12-11", "M-4 9Q2 12 8 7"): "thinking",
    ("2.4", "M3-11Q8-16 12-11", "M-5 8Q3 13 10 5"): "calm",
    ("3.4", "M3-11Q8-16 12-11", "M-7 6Q3 18 13 2"): "proud",
    ("3.4", "M3-11Q8-16 12-11", "M-5 9Q3 13 10 6"): "focused",
}
HAND_PATHS = ("M-11 4Q-14-2-9-4", "M-12 5Q-17 0-13-3")

# Where the right-hand signs start (they are drawn natively).
SIGN_X = {"expanded": 200.0, "compact": 177.0, "minimal": 27.0}
FIXED_VIEWBOX = {"compact": (0.0, 0.0, 52.33, 36.67), "minimal": (0.0, 0.0, 45.0, 36.67)}

BOARDS = [
    ("voice", "leanIn"), ("focus", "tinyPromise"),
    ("thought-drop", "thoughtPocket"), ("language-bridge", "languageBridge"),
    ("reminder-pin", "reminderKnot"), ("step-path", "stepStones"),
    ("spoken-mark", "storySpool"), ("calm-pulse", "calmTide"),
]


def num(s):
    return float(s)


def fmt(v):
    v = round(v, 4)
    if v == int(v):
        return "%d" % int(v)
    return repr(v)


def color(value):
    if value is None or value in ("none", "transparent"):
        return "nil"
    m = re.fullmatch(r"#([0-9A-Fa-f]{6})", value)
    if not m:
        sys.exit("unknown colour %r" % value)
    return "0x" + m.group(1).upper()


def paint(el):
    return "IslandPaint(fill: %s, stroke: %s, width: %s)" % (
        color(el.get("fill")), color(el.get("stroke")), fmt(num(el.get("stroke-width", "0"))))


TRANSFORM = re.compile(r"translate\(([-\d.]+) ([-\d.]+)\) scale\(([-\d.]+)\)")


def path_points(d):
    """Rough bounding points of a path (end and control points; arcs add their radii)."""
    tokens = re.findall(r"[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?", d)
    pts, i, cmd, cur = [], 0, None, (0.0, 0.0)
    counts = {"M": 2, "L": 2, "Q": 4, "C": 6, "S": 4, "H": 1, "V": 1, "A": 7, "Z": 0}
    while i < len(tokens):
        t = tokens[i]
        if t.isalpha():
            cmd = t
            i += 1
            if cmd == "Z":
                continue
        n = counts[cmd]
        vals = [float(x) for x in tokens[i:i + n]]
        i += n
        if cmd == "H":
            cur = (vals[0], cur[1])
            pts.append(cur)
        elif cmd == "V":
            cur = (cur[0], vals[0])
            pts.append(cur)
        elif cmd == "A":
            end = (vals[5], vals[6])
            pts += arc_points(cur, vals[0], vals[1], vals[2], vals[3] != 0, vals[4] != 0, end)
            cur = end
        else:
            for k in range(0, n, 2):
                pts.append((vals[k], vals[k + 1]))
            cur = pts[-1]
    return pts


def arc_points(p0, rx, ry, rotation, large, sweep, p1, samples=48):
    """Points along an SVG arc (SVG spec, Appendix B.2.4 centre conversion)."""
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0 or p0 == p1:
        return [p1]
    phi = math.radians(rotation)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
    x1, y1 = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num_ = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    coef = math.sqrt(max(0.0, num_) / den)
    if large == sweep:
        coef = -coef
    cxp, cyp = coef * rx * y1 / ry, -coef * ry * x1 / rx
    cx = cp * cxp - sp * cyp + (p0[0] + p1[0]) / 2
    cy = sp * cxp + cp * cyp + (p0[1] + p1[1]) / 2

    def ang(ux, uy, vx, vy):
        return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    t1 = ang(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
    dt = ang((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    if sweep and dt < 0:
        dt += 2 * math.pi
    out = []
    for i in range(samples + 1):
        t = t1 + dt * i / samples
        ex, ey = rx * math.cos(t), ry * math.sin(t)
        out.append((cp * ex - sp * ey + cx, sp * ex + cp * ey + cy))
    return out


class Art:
    def __init__(self, presentation):
        self.presentation = presentation
        self.points = []

    def add_box(self, x0, y0, x1, y1, tf, pad=0.0):
        tx, ty, s = tf
        for x, y in ((x0, y0), (x1, y1)):
            self.points.append((tx + s * x - pad, ty + s * y - pad))
            self.points.append((tx + s * x + pad, ty + s * y + pad))

    def is_sign(self, x, el=None):
        if x < SIGN_X[self.presentation]:
            return False
        if self.presentation != "minimal" or el is None:
            return True
        # Minimal keeps the pack's own marks (knot, check, rings); only the voice bars and the
        # thinking dots are left to the native view.
        tag = el.tag.replace(NS, "")
        if tag == "rect":
            return num(el.get("width")) <= 2.5
        if tag == "circle":
            return num(el.get("r")) <= 2
        return tag == "text"

    def element(self, el, tf, depth):
        tag = el.tag.replace(NS, "")
        pad = num(el.get("stroke-width", "0")) / 2
        if tag in ("text", "title", "style"):
            return None
        if el.get("data-hit-target") or el.get("data-control"):
            return None
        if tag == "g":
            m = TRANSFORM.fullmatch(el.get("transform", ""))
            if not m:
                sys.exit("unexpected group %r" % el.attrib)
            x, y, s = (num(v) for v in m.groups())
            ax, ay, as_ = tf[0] + tf[2] * x, tf[1] + tf[2] * y, tf[2] * s
            if depth == 0 and self.is_sign(ax, el):
                return None
            kids = list(el)
            if kids and kids[0].tag == NS + "circle" and kids[0].get("r") == "20":
                eyes = kids[2].get("ry")
                brow = kids[4].get("d")
                mouth = kids[5].get("d")
                key = (eyes, brow, mouth)
                if key not in FACES or kids[3].get("ry") != eyes or len(kids) != 6:
                    sys.exit("face not in the pack's list: %r" % (key,))
                self.add_box(-20.7, -20.7, 20.7, 20.7, (ax, ay, as_))
                return ".face(x: %s, y: %s, scale: %s, .%s)" % (fmt(x), fmt(y), fmt(s), FACES[key])
            role = "hand" if kids and (kids[0].get("d") or "").startswith(HAND_PATHS) else "other"
            inner = [self.element(k, (ax, ay, as_), depth + 1) for k in kids]
            inner = [i for i in inner if i]
            if not inner:
                return None
            return ".group(x: %s, y: %s, scale: %s, role: .%s, [%s])" % (
                fmt(x), fmt(y), fmt(s), role, ", ".join(inner))
        if tag == "path":
            d = el.get("d")
            pts = path_points(d)
            xs = [tf[0] + tf[2] * p[0] for p in pts]
            if depth == 0 and self.is_sign(min(xs), el):
                return None
            for p in pts:
                self.add_box(p[0], p[1], p[0], p[1], tf, pad)
            return ".path(%s, %s)" % (swift_string(d), paint(el))
        if tag == "circle":
            cx, cy, r = num(el.get("cx")), num(el.get("cy")), num(el.get("r"))
            if depth == 0 and self.is_sign(tf[0] + tf[2] * cx, el):
                return None
            self.add_box(cx - r, cy - r, cx + r, cy + r, tf, pad)
            return ".ellipse(cx: %s, cy: %s, rx: %s, ry: %s, %s)" % (fmt(cx), fmt(cy), fmt(r), fmt(r), paint(el))
        if tag == "ellipse":
            cx, cy = num(el.get("cx")), num(el.get("cy"))
            rx, ry = num(el.get("rx")), num(el.get("ry"))
            if depth == 0 and self.is_sign(tf[0] + tf[2] * cx, el):
                return None
            self.add_box(cx - rx, cy - ry, cx + rx, cy + ry, tf, pad)
            return ".ellipse(cx: %s, cy: %s, rx: %s, ry: %s, %s)" % (fmt(cx), fmt(cy), fmt(rx), fmt(ry), paint(el))
        if tag == "rect":
            x, y = num(el.get("x")), num(el.get("y"))
            w, h = num(el.get("width")), num(el.get("height"))
            if depth == 0 and self.is_sign(tf[0] + tf[2] * x, el):
                return None
            self.add_box(x, y, x + w, y + h, tf, pad)
            return ".rect(x: %s, y: %s, width: %s, height: %s, radius: %s, %s)" % (
                fmt(x), fmt(y), fmt(w), fmt(h), fmt(num(el.get("rx", "0"))), paint(el))
        sys.exit("unexpected element %s" % tag)

    def view_box(self):
        if self.presentation in FIXED_VIEWBOX:
            return FIXED_VIEWBOX[self.presentation]
        xs = [p[0] for p in self.points]
        ys = [p[1] for p in self.points]
        x0, y0 = min(xs) - 1, min(ys) - 1
        return (x0, y0, max(xs) + 1 - x0, max(ys) + 1 - y0)


def swift_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def convert(path, presentation):
    root = ET.parse(path).getroot()
    content = next(g for g in root.iter(NS + "g") if g.get("data-content"))
    art = Art(presentation)
    items = [art.element(el, (0.0, 0.0, 1.0), 0) for el in content]
    items = [i for i in items if i]
    vb = art.view_box() if art.points or presentation in FIXED_VIEWBOX else (0, 0, 1, 1)
    return "IslandArt(viewBox: IslandRect(x: %s, y: %s, width: %s, height: %s), elements: [\n            %s,\n        ])" % (
        fmt(vb[0]), fmt(vb[1]), fmt(vb[2]), fmt(vb[3]), ",\n            ".join(items))


def main():
    lines = [
        "// GENERATED by tools/island_boards/generate_island_art.py from",
        "// design/dynamic-island-v4/02-states (the owner's Doddy-Dynamic-Island-v4 pack). Do not edit.",
        "",
        "/// One drawing per board, scenario and presentation: the pack's shapes in its own",
        "/// coordinates, without text, buttons or right-hand signs.",
        "enum IslandBoardArt {",
        "    static func art(_ board: IslandBoard, scenario: Int, _ presentation: IslandPresentation) -> IslandArt {",
        "        switch (board, scenario == 0, presentation) {",
    ]
    bodies = []
    for prefix, name in BOARDS:
        for scenario in (0, 1):
            for presentation in ("expanded", "compact", "minimal"):
                f = os.path.join(STATES, "%s-%d-%s.svg" % (prefix, scenario, presentation))
                if not os.path.exists(f):
                    sys.exit("missing %s" % f)
                ident = "%s%d%s" % (name, scenario, presentation.capitalize())
                lines.append("        case (.%s, %s, .%s): %s" % (name, "true" if scenario == 0 else "false", presentation, ident))
                bodies.append("    private static let %s = %s\n" % (ident, convert(f, presentation)))
    lines += ["        }", "    }", ""]
    lines += bodies
    lines += ["}", ""]
    with open(OUT, "w") as out:
        out.write("\n".join(lines))
    print("wrote %s (%d drawings)" % (os.path.relpath(OUT, ROOT), len(bodies)))


if __name__ == "__main__":
    main()
