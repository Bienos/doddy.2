"""Crop the four panels of the pack's page-turn storyboard (ADR-299).

038_trans_page_v01.png is four bordered panels on paper with their numbers printed above them.
This finds the panels (the tallest band of non-paper rows, split at all-paper columns) and crops
each one inside its border. Nothing else is changed.

    python3 -I tools/whole_doddy/cut_panels.py <038_trans_page_v01.png> <out_prefix>

Writes <out_prefix>_1.jpg ... _4.jpg.
"""
import sys
from PIL import Image

sys.path.insert(0, __import__("os").path.dirname(__file__))
from cut_frames import bands  # noqa: E402


def main(source, prefix):
    im = Image.open(source).convert("RGB")
    width, height = im.size
    px = im.load()
    paper = px[3, 3]

    def is_paper(c):
        return sum(abs(c[i] - paper[i]) for i in range(3)) < 38

    rows = bands([any(not is_paper(px[x, y]) for x in range(0, width, 2)) for y in range(height)], 20)
    ry0, ry1 = max(rows, key=lambda r: r[1] - r[0])
    cols = bands([any(not is_paper(px[x, y]) for y in range(ry0, ry1, 2)) for x in range(width)], 100)
    inset = 6
    for i, (cx0, cx1) in enumerate(cols, 1):
        im.crop((cx0 + inset, ry0 + inset, cx1 - inset, ry1 - inset)).save(f"{prefix}_{i}.jpg", quality=88)
    print(f"{len(cols)} panels")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
