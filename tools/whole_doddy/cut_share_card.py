"""Cut the brain-carrying Doddy out of the owner's "Big brain. Small body." card (ADR-444).

The owner supplied the card as one flat picture: lettering on the left, Doddy carrying a giant brain
on the right, all on paper. This removes only the paper that touches the picture's edges (so the
cream face, shoes and the pink brain, inside their black outlines, stay), then keeps the marks whose
centre is right of the lettering (and the brain's two motion marks above it): Doddy, the brain, the sweat drops, the motion and orange marks and
the ground strokes. The lettering is set as live text by the share cards instead. Nothing is redrawn.

    python3 -I tools/whole_doddy/cut_share_card.py <owner card image> <output.png>

The output is a transparent PNG cropped to the kept marks. It is the ShareDoddy_big_brain image set's
art@3x.png unchanged; art@2x.png is its Lanczos downscale to two thirds.
"""
import sys
from collections import deque
from PIL import Image

SPLIT_X = 556  # the lettering's marks are centred left of this column; Doddy's right of it
MOTION_X = 515  # ...except the brain's two top-left motion marks, centred between these columns
LETTERING_TOP = 125  # and above this row, where no lettering near the brain reaches


def is_paper(c):
    return min(c) > 200 and max(c) - min(c) < 45


def main(source, target):
    im = Image.open(source).convert("RGBA")
    w, h = im.size
    # The supplied screenshot ends in a few all-dark columns (a window edge, not art): crop them off.
    while all(sum(im.getpixel((w - 1, y))[:3]) < 180 for y in range(0, h, 7)):
        w -= 1
    im = im.crop((0, 0, w, h))
    px = im.load()
    paper = [[False] * h for _ in range(w)]
    queue = deque([(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)])
    while queue:
        x, y = queue.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or paper[x][y] or not is_paper(px[x, y][:3]):
            continue
        paper[x][y] = True
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

    # Group what is left into marks (8-connected) and keep those centred right of the lettering.
    keep = [[False] * h for _ in range(w)]
    seen = [[False] * h for _ in range(w)]
    for sx in range(w):
        for sy in range(h):
            if paper[sx][sy] or seen[sx][sy]:
                continue
            mark, queue = [], deque([(sx, sy)])
            seen[sx][sy] = True
            while queue:
                x, y = queue.popleft()
                mark.append((x, y))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and not paper[nx][ny] and not seen[nx][ny]:
                            seen[nx][ny] = True
                            queue.append((nx, ny))
            centre = sum(x for x, _ in mark) / len(mark)
            # The two motion marks at the brain's top left sit above the lettering's top line.
            if centre > SPLIT_X or (centre > MOTION_X and max(y for _, y in mark) < LETTERING_TOP):
                for x, y in mark:
                    keep[x][y] = True

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for x in range(w):
        for y in range(h):
            if not keep[x][y]:
                continue
            r, g, b, _ = px[x, y]
            alpha = 255
            touches_paper = any(paper[x + dx][y + dy] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                                if 0 <= x + dx < w and 0 <= y + dy < h)
            lum = (r + g + b) / 3
            if touches_paper and lum > 140:  # the light fringe next to removed paper fades out
                alpha = int(255 * max(0, min(1, (255 - lum) / 115)))
            op[x, y] = (r, g, b, alpha)
    box = out.getbbox()
    pad = 8
    out.crop((box[0] - pad, max(0, box[1] - pad), min(w, box[2] + pad), min(h, box[3] + pad))).save(target)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
