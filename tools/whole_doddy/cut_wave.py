"""Cut the greeting wave out of the owner's pack (ADR-268).

The pack's only wave is a five-frame strip on paper, 016_doddy_wave_v01.png. This takes frame 4
(open hand with the orange marks) and removes only the paper that touches the frame's edges, so
Doddy's cream face and shoes, which sit inside his black outline, stay. Nothing is redrawn.

    python3 -I tools/whole_doddy/cut_wave.py <path to 016_doddy_wave_v01.png> <output.png>

The output is a 2:3 transparent picture; the WholeDoddy_wave image sets are its Lanczos
downscales (200 x 300 and 300 x 450).
"""
import sys
from collections import deque
from PIL import Image

PAPER = (254, 246, 232)


def is_paper(c, tolerance):
    return sum(abs(c[i] - PAPER[i]) for i in range(3)) < tolerance


def main(source, target):
    im = Image.open(source).convert("RGB")
    width, _ = im.size
    px = im.load()
    # Frames are separated by all-paper columns above the frame numbers (y < 620).
    used = [any(not is_paper(px[x, y], 38) for y in range(0, 620, 2)) for x in range(width)]
    runs, x = [], 0
    while x < width:
        if used[x]:
            start = x
            while x < width and used[x]:
                x += 1
            runs.append((start, x))
        x += 1
    x0, x1 = [r for r in runs if r[1] - r[0] > 40][3]
    rows = [y for y in range(0, 640) if any(not is_paper(px[x, y], 38) for x in range(x0, x1))]
    y0, y1 = rows[0], rows[-1]
    for y in range(y0, y1):
        if all(is_paper(px[x, y], 38) for x in range(x0, x1)):
            y1 = y  # stop above the frame number
            break
    pad = 20
    crop = im.crop((x0 - pad, y0 - pad, x1 + pad, y1 + pad)).convert("RGBA")
    cw, ch = crop.size
    cp = crop.load()
    seen = [[False] * ch for _ in range(cw)]
    queue = deque([(x, y) for x in range(cw) for y in (0, ch - 1)] + [(x, y) for y in range(ch) for x in (0, cw - 1)])
    while queue:
        x, y = queue.popleft()
        if x < 0 or y < 0 or x >= cw or y >= ch or seen[x][y]:
            continue
        seen[x][y] = True
        r, g, b, _ = cp[x, y]
        if not is_paper((r, g, b), 60):
            continue
        cp[x, y] = (r, g, b, 0)
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    out = crop.copy()
    op = out.load()
    for x in range(1, cw - 1):
        for y in range(1, ch - 1):
            r, g, b, a = cp[x, y]
            if a and any(cp[x + dx, y + dy][3] == 0 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                lum = (r + g + b) / 3
                if lum > 140:  # the light fringe next to removed paper fades out
                    op[x, y] = (r, g, b, int(255 * max(0, min(1, (255 - lum) / 115))))
    fw, fh = out.size
    h2 = int(fh / 0.80)
    w2 = int(h2 / 1.5)
    if w2 < fw / 0.9:
        w2 = int(fw / 0.9)
        h2 = int(w2 * 1.5)
    canvas = Image.new("RGBA", (w2, h2), (0, 0, 0, 0))
    canvas.alpha_composite(out, ((w2 - fw) // 2, int(h2 * 0.94) - fh))
    canvas.save(target)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
