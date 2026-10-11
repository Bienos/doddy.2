"""Cut Doddy frames out of a sheet from the owner's pack (ADR-299).

Frame sheets in DODDY-Numbered-Video-Assets-v01 are drawn on paper: strips (one row) or grids.
Frames are separated by all-paper rows and columns. For each frame this removes only the paper
connected to the frame's edges, so Doddy's cream face and shoes, inside his black outline, stay.
Nothing is redrawn or recoloured. Each frame is written as a 2:3 transparent PNG.

    python3 -I tools/whole_doddy/cut_frames.py <sheet.png> <out_prefix> [--rows-max-y N]
        [--shared] [--min-fraction F]

Writes <out_prefix>_1.png, _2.png, ... in reading order (left to right, top to bottom).
Marks under half the tallest frame's height (a printed number, a speck) are skipped;
`--min-fraction` changes that half (0 keeps every mark: the pop strip starts with a dot).
`--rows-max-y` ignores everything below that y: frame numbers printed under a strip, or the
ground line some strips stand on (pass the line's top, so the line itself is left out).
`--shared` (ADR-313) puts every frame on one canvas size with one ground: the strip's own
scale and positions are kept, so an animation doesn't jump or change size between frames. It
also lets a column with a speck or two (motion marks) separate frames.
Without it each frame is fitted to its own canvas (the talking frames, ADR-299).
"""
import sys
from collections import deque
from PIL import Image


def bands(flags, min_len):
    out, i = [], 0
    while i < len(flags):
        if flags[i]:
            start = i
            while i < len(flags) and flags[i]:
                i += 1
            if i - start >= min_len:
                out.append((start, i))
        i += 1
    return out


PAD = 20


def cut(im, box, paper):
    """The frame on its own 2:3 canvas, fitted to the frame."""
    out = cut_out(im, box, paper)
    fw, fh = out.size
    h2 = int(fh / 0.80)
    w2 = int(h2 / 1.5)
    if w2 < fw / 0.9:
        w2 = int(fw / 0.9)
        h2 = int(w2 * 1.5)
    canvas = Image.new("RGBA", (w2, h2), (0, 0, 0, 0))
    canvas.alpha_composite(out, ((w2 - fw) // 2, int(h2 * 0.94) - fh))
    return canvas


def shared(im, boxes, paper):
    """Every frame on one 2:3 canvas size: one scale, one ground (the lowest frame bottom)."""
    ground = max(b[3] for b in boxes)
    top = min(b[1] for b in boxes)
    widest = max(b[2] - b[0] for b in boxes) + 2 * PAD
    h2 = int((ground - top + 2 * PAD) / 0.80)
    w2 = int(h2 / 1.5)
    if w2 < widest / 0.9:
        w2 = int(widest / 0.9)
        h2 = int(w2 * 1.5)
    frames = []
    for box in boxes:
        out = cut_out(im, box, paper)
        # Only the frame's own columns: specks of the next frame's motion marks stay out.
        out.paste((0, 0, 0, 0), (0, 0, PAD, out.height))
        out.paste((0, 0, 0, 0), (out.width - PAD, 0, out.width, out.height))
        canvas = Image.new("RGBA", (w2, h2), (0, 0, 0, 0))
        # The frame keeps its height above the ground (a jump stays in the air).
        canvas.alpha_composite(out, ((w2 - out.width) // 2, int(h2 * 0.94) - (ground - (box[1] - PAD))))
        frames.append(canvas)
    return frames


def cut_out(im, box, paper):
    """The frame with the paper around it removed (only paper touching the edges)."""
    def is_paper(c, tolerance):
        return sum(abs(c[i] - paper[i]) for i in range(3)) < tolerance

    pad = PAD
    x0, y0, x1, y1 = box
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
    return out


def main(source, prefix, max_y=None, together=False, min_fraction=0.5):
    im = Image.open(source).convert("RGB")
    width, height = im.size
    paper = im.getpixel((3, 3))
    limit = max_y or height
    if max_y:
        # Below the limit becomes paper, so a ground line or a number can't stay in a frame
        # or close off the paper between Doddy's legs.
        im.paste(paper, (0, max_y, width, height))
    px = im.load()

    def is_paper(c):
        return sum(abs(c[i] - paper[i]) for i in range(3)) < 38

    row_flags = [any(not is_paper(px[x, y]) for x in range(0, width, 2)) if y < limit else False for y in range(height)]
    frames = []
    for (ry0, ry1) in bands(row_flags, 60):
        # With --shared, a column with a speck or two (motion marks) still separates frames.
        specks = 2 if together else 0
        col_flags = [sum(not is_paper(px[x, y]) for y in range(ry0, ry1, 2)) > specks for x in range(width)]
        for (cx0, cx1) in bands(col_flags, 40):
            rows = [y for y in range(ry0, ry1) if any(not is_paper(px[x, y]) for x in range(cx0, cx1))]
            frames.append((cx0, rows[0], cx1, rows[-1] + 1))
    # A stray mark (a frame number, a speck) is far smaller than a drawn frame.
    tallest = max(y1 - y0 for (_, y0, _, y1) in frames)
    frames = [f for f in frames if f[3] - f[1] >= tallest * min_fraction]
    pictures = shared(im, frames, paper) if together else [cut(im, box, paper) for box in frames]
    for i, picture in enumerate(pictures, 1):
        picture.save(f"{prefix}_{i}.png")
    print(f"{len(frames)} frames")


if __name__ == "__main__":
    args = sys.argv[1:]
    max_y = None
    if "--rows-max-y" in args:
        k = args.index("--rows-max-y")
        max_y = int(args[k + 1])
        del args[k:k + 2]
    together = "--shared" in args
    if together:
        args.remove("--shared")
    min_fraction = 0.5
    if "--min-fraction" in args:
        k = args.index("--min-fraction")
        min_fraction = float(args[k + 1])
        del args[k:k + 2]
    main(args[0], args[1], max_y, together, min_fraction)
