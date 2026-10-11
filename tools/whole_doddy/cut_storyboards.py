"""Crop the panels of the pack's storyboards (ADR-380).

037 (phone), 039 (door) and 040 (ink) are one row of four panels; 041 (keys) is a 2 x 3 grid.
Panels are separated by paper. This finds the rows of panels (bands of non-paper rows taller
than a fifth of the sheet, so a row of printed numbers above the panels is skipped), splits each
at all-paper columns, and crops each panel inside its edge. Where a panel number is printed
inside the panel's top-left corner, `--trim-top F` drops that fraction of the panel's height
from the top. Where that would cut into Doddy's head, `--sides` (one letter per panel, t or l)
trims `--trim-left F` of the width from the left instead. Nothing else is changed: no
redrawing, no recolouring.

    python3 -I tools/whole_doddy/cut_storyboards.py <sheet.png> <out_prefix> [--trim-top F]
        [--trim-left F --sides tlltll]

Writes <out_prefix>_1.jpg ... in reading order.
"""
import sys
from PIL import Image

sys.path.insert(0, __import__("os").path.dirname(__file__))
from cut_frames import bands  # noqa: E402


def main(argv):
    source, prefix = argv[0], argv[1]
    def option(name, default):
        return argv[argv.index(name) + 1] if name in argv else default
    trim_top, trim_left = float(option("--trim-top", 0)), float(option("--trim-left", 0))
    sides = option("--sides", "")
    im = Image.open(source).convert("RGB")
    width, height = im.size
    px = im.load()
    paper = px[3, 3]

    def is_paper(c):
        return sum(abs(c[i] - paper[i]) for i in range(3)) < 38

    rows = bands([any(not is_paper(px[x, y]) for x in range(0, width, 2)) for y in range(height)], height // 5)
    inset = 8
    n = 0
    for ry0, ry1 in rows:
        cols = bands([any(not is_paper(px[x, y]) for y in range(ry0, ry1, 2)) for x in range(width)], width // 8)
        for cx0, cx1 in cols:
            side = sides[n] if n < len(sides) else "t"
            top = ry0 + inset + (round((ry1 - ry0) * trim_top) if side == "t" else 0)
            left = cx0 + inset + (round((cx1 - cx0) * trim_left) if side == "l" else 0)
            n += 1
            im.crop((left, top, cx1 - inset, ry1 - inset)).save(f"{prefix}_{n}.jpg", quality=88)
    print(f"{n} panels")


if __name__ == "__main__":
    main(sys.argv[1:])
