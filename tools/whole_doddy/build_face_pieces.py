"""Cut Doddy's gaze and blink pieces from the owner's pack sheets (ADR-560).

Owner instruction, 20 Oct 2026: "Make blink and gaze". The pack has no picture of him looking
anywhere or blinking, but it has two sheets of heads that do (Q6): 007_doddy_blink_v02.png (open,
half closed, closed, half closed) and 008_doddy_eyes_v01.png (a 3 x 3 grid of the eyes looking
up-left ... down-right). This tool only CUTS the eyes out of those heads and measures them:

  * each eye is cut as ink on a transparent background (the alpha is how dark the sheet's pixel is
    against that head's own fill; the ink is the sheet's ink), nothing is redrawn, recoloured or
    generated;
  * the same measurements are taken from the pack pictures with a front-facing head (sitting
    cross-legged, standing, waving: where each eye is, how big, the head's radius, the paper's
    colour around each eye), so the app can lay a piece over the right place on each picture;
  * the app draws the pieces over the pack's own picture, and only while his eyes are not on you;
    looking at you, he is the picture exactly as the pack drew it.

    python3 -I tools/whole_doddy/build_face_pieces.py <007 blink sheet> <008 eyes sheet> <repo root> [<preview dir>]

Needs Pillow and numpy. Writes DoddyApp/Resources/Assets.xcassets/DoddyEye_*.imageset and
Packages/DoddyCore/Sources/DoddyCore/Eyes/DoddyEyePieces.swift (generated; rerunning this
tool gives the same files). With a preview directory it also writes proof sheets: each picture with
each piece laid on it, at 4x.
"""
import hashlib
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

APP = "DoddyApp/Resources/Assets.xcassets"
INFO = {"author": "xcode", "version": 1}
SWIFT = "Packages/DoddyCore/Sources/DoddyCore/Eyes/DoddyEyePieces.swift"

# The pictures with a front-facing head, by image set: the cross-legged pose (Home's Doddy), and the
# standing breath and wave strips. The jump strip, the listening and thinking poses and the turned
# heads are three-quarter or side views: these front eyes don't fit them.
PICTURES = (
    [("WholeDoddy_crosslegged", "WholeDoddy_crosslegged")]
    + [("DoddyMotion_idle_%d" % n, "DoddyMotion_idle_%d" % n) for n in range(1, 5)]
    + [("DoddyMotion_wave_%d" % n, "DoddyMotion_wave_%d" % n) for n in range(1, 6)]
)

# The reference size of a cut piece: the picture heads are about this many pixels in radius at 3x.
REFERENCE_RADIUS = 64.0
# Pixels of the sheet kept around each cut eye (so its soft edge is whole).
MARGIN = 4
# The cover over a picture's own eye is its box plus this many pixels (of the @3x picture), with an
# edge softened by COVER_BLUR pixels.
COVER_PAD = 6.0
COVER_BLUR = 2.0
INK = 14
DARK = 110


def label(mask):
    """4-connected components of a boolean array: a list of Nx2 arrays of (y, x)."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if seen[y0, x0]:
            continue
        queue = deque([(y0, x0)])
        seen[y0, x0] = True
        pts = []
        while queue:
            y, x = queue.popleft()
            pts.append((y, x))
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        out.append(np.array(pts))
    return out


def box(pts):
    return int(pts[:, 1].min()), int(pts[:, 0].min()), int(pts[:, 1].max()), int(pts[:, 0].max())


def luminance(rgba):
    return rgba[..., 0] * 0.3 + rgba[..., 1] * 0.59 + rgba[..., 2] * 0.11


def heads_of(im, min_eye_area):
    """Every head on a picture or sheet: its interior's box and median fill, and the dark parts
    inside (the eyes, the brow and the mouth), each with its box."""
    rgba = np.asarray(im.convert("RGBA")).astype(int)
    lum = luminance(rgba)
    opaque = rgba[..., 3] > 128
    height, width = lum.shape
    light = opaque & (lum >= DARK)
    interiors = []
    for comp in label(light):
        x0, y0, x1, y1 = box(comp)
        if x0 == 0 or y0 == 0 or x1 == width - 1 or y1 == height - 1:
            continue
        if len(comp) < 3000:
            continue
        interiors.append((comp, (x0, y0, x1, y1)))
    dark_parts = [c for c in label(opaque & (lum < DARK))]
    heads = []
    for comp, (x0, y0, x1, y1) in interiors:
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        rx, ry = (x1 - x0 + 1) / 2, (y1 - y0 + 1) / 2
        fill = np.median(rgba[comp[:, 0], comp[:, 1], :3], axis=0)
        parts = []
        for part in dark_parts:
            px0, py0, px1, py1 = box(part)
            mx, my = part[:, 1].mean(), part[:, 0].mean()
            nx, ny = (mx - cx) / rx, (my - cy) / ry
            if nx * nx + ny * ny > 0.5 or len(part) > 0.15 * len(comp):
                continue
            parts.append(dict(area=len(part), box=(px0, py0, px1, py1), nx=nx, ny=ny))
        eyes = sorted((p for p in parts if abs(p["ny"]) < 0.35 and p["area"] >= min_eye_area),
                      key=lambda p: p["box"][0])
        heads.append(dict(cx=cx, cy=cy, rx=rx, ry=ry, fill=[int(round(v)) for v in fill], eyes=eyes))
    return heads, rgba


def eye_geometry(head, eye):
    x0, y0, x1, y1 = eye["box"]
    return dict(cx=(x0 + x1) / 2, cy=(y0 + y1) / 2, w=x1 - x0 + 1, h=y1 - y0 + 1)


def local_fill(rgba, geo):
    """The paper around an eye: the median colour of a ring just outside it (the pack's fill is
    not quite flat, and a cover of the head's median shows as a faint patch)."""
    h, w = rgba.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    a, b = geo["w"] / 2, geo["h"] / 2

    def inside(extra):
        return ((xx - geo["cx"]) / (a + extra)) ** 2 + ((yy - geo["cy"]) / (b + extra)) ** 2 <= 1

    ring = inside(COVER_PAD + 6) & ~inside(COVER_PAD + 2) & (rgba[..., 3] > 200) & (luminance(rgba) > 200)
    return [int(v) for v in np.median(rgba[ring][:, :3], axis=0)]


def cut_sprite(rgba, head, eye, name, catalog):
    """The eye as ink on transparent, at the reference radius; writes art@2x and art@3x."""
    x0, y0, x1, y1 = eye["box"]
    x0, y0, x1, y1 = x0 - MARGIN, y0 - MARGIN, x1 + MARGIN, y1 + MARGIN
    crop = rgba[y0:y1 + 1, x0:x1 + 1]
    lum = luminance(crop)
    fill_lum = luminance(np.array(head["fill"], dtype=float).reshape(1, 1, 3))[0, 0]
    alpha = np.clip((fill_lum - lum) / (fill_lum - INK), 0, 1)
    out = np.zeros(crop.shape[:2] + (4,), dtype=np.uint8)
    out[..., 0:3] = INK
    out[..., 3] = (alpha * 255).round().astype(np.uint8)
    picture = Image.fromarray(out, "RGBA")
    radius = (head["rx"] + head["ry"]) / 2
    k = REFERENCE_RADIUS / radius
    w3 = max(1, round(picture.width * k))
    h3 = max(1, round(picture.height * k))
    folder = os.path.join(catalog, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    picture.resize((max(1, round(w3 * 2 / 3)), max(1, round(h3 * 2 / 3))), Image.LANCZOS).save(
        os.path.join(folder, "art@2x.png"), optimize=True)
    picture.resize((w3, h3), Image.LANCZOS).save(os.path.join(folder, "art@3x.png"), optimize=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": [
            {"filename": "art@2x.png", "idiom": "universal", "scale": "2x"},
            {"filename": "art@3x.png", "idiom": "universal", "scale": "3x"},
        ], "info": INFO}, f, indent=2)
    return (picture.width / radius, picture.height / radius)  # frame size, in head radii


def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def main():
    blink_path, eyes_path, root = sys.argv[1], sys.argv[2], sys.argv[3]
    preview = sys.argv[4] if len(sys.argv) > 4 else None
    catalog = os.path.join(root, APP)

    # Sheet 008: the 3 x 3 grid of gazes; row 0 up, column 0 left. Sheet 007: open, half, closed, half.
    grid, grid_rgba = heads_of(Image.open(eyes_path), 300)
    assert len(grid) == 9, "expected 9 heads on the eye sheet, found %d" % len(grid)
    grid.sort(key=lambda h: round(h["cy"] / 300))
    rows = [sorted(grid[i * 3:(i + 1) * 3], key=lambda h: h["cx"]) for i in range(3)]
    blinks, blink_rgba = heads_of(Image.open(blink_path), 300)
    assert len(blinks) == 4, "expected 4 heads on the blink sheet, found %d" % len(blinks)
    blinks.sort(key=lambda h: h["cx"])

    def rel(head, eye):
        g = eye_geometry(head, eye)
        r = (head["rx"] + head["ry"]) / 2
        return dict(x=(g["cx"] - head["cx"]) / r, y=(g["cy"] - head["cy"]) / r, w=g["w"] / r, h=g["h"] / r)

    pieces = []
    centre = rows[1][1]
    assert len(centre["eyes"]) == 2
    neutral = [rel(centre, e) for e in centre["eyes"]]
    for row in range(3):
        for col in range(3):
            if (row, col) == (1, 1):
                continue
            head = rows[row][col]
            assert len(head["eyes"]) == 2, "gaze tile %d,%d has %d eyes" % (row, col, len(head["eyes"]))
            rels = [rel(head, e) for e in head["eyes"]]
            # The sheet moves the two eyes by slightly different amounts (and sometimes at
            # different heights); he looks with both eyes together, so each cell moves the pair by
            # the mean of the two shifts and the eyes stay level.
            mdx = sum(r["x"] - n["x"] for r, n in zip(rels, neutral)) / 2
            mdy = sum(r["y"] - n["y"] for r, n in zip(rels, neutral)) / 2
            for side, eye in zip(("L", "R"), head["eyes"]):
                i = 0 if side == "L" else 1
                name = "DoddyEye_g%d%d_%s" % (row, col, side)
                fw, fh = cut_sprite(grid_rgba, head, eye, name, catalog)
                pieces.append(dict(asset=name, cell=".gaze(column: %d, row: %d)" % (col, row), side=side,
                                   dx=mdx, dy=mdy, w=fw, h=fh, nw=neutral[i]["w"], nh=neutral[i]["h"]))
    open_head = blinks[0]
    assert len(open_head["eyes"]) == 2
    open_eyes = [rel(open_head, e) for e in open_head["eyes"]]
    for cell, index in (("half", 1), ("closed", 2)):
        head = blinks[index]
        assert len(head["eyes"]) == 2, "blink tile %s has %d eyes" % (cell, len(head["eyes"]))
        for side, eye in zip(("L", "R"), head["eyes"]):
            i = 0 if side == "L" else 1
            r = rel(head, eye)
            name = "DoddyEye_%s_%s" % (cell, side)
            fw, fh = cut_sprite(blink_rgba, head, eye, name, catalog)
            pieces.append(dict(asset=name, cell=".%s" % cell, side=side,
                               dx=r["x"] - open_eyes[i]["x"], dy=r["y"] - open_eyes[i]["y"],
                               w=fw, h=fh, nw=0.0, nh=0.0))

    # The body pictures: where each eye is on them.
    fits = []
    for key, asset in PICTURES:
        path = os.path.join(catalog, asset + ".imageset", "art@3x.png")
        heads, rgba = heads_of(Image.open(path), 60)
        assert heads, "no head found on " + asset
        head = max(heads, key=lambda h: h["rx"])
        assert len(head["eyes"]) == 2, "%s has %d eyes" % (asset, len(head["eyes"]))
        radius = (head["rx"] + head["ry"]) / 2
        eyes = [eye_geometry(head, e) for e in head["eyes"]]
        for geo in eyes:
            geo["fill"] = local_fill(rgba, geo)
        fits.append(dict(key=key, asset=asset, radius=radius, eyes=eyes, head=head))

    with open(os.path.join(root, SWIFT), "w") as f:
        f.write("// Generated by tools/whole_doddy/build_face_pieces.py (ADR-560); rerunning it\n")
        f.write("// gives this file again, so don't edit it by hand. The pieces are eyes cut from the owner's pack\n")
        f.write("// sheets (sha256 007: %s, 008: %s).\n" % (sha(blink_path), sha(eyes_path)))
        f.write("// Lengths on a piece are in head radii; on a fit, in pixels of the picture's @3x file (300 x 450).\n")
        f.write("\n")
        f.write("extension DoddyEyes {\n")
        f.write("    /// The cover over a picture's own eye is its box plus `coverPad`, its edge softened by `coverBlur` (pixels of the @3x picture).\n")
        f.write("    static let coverPad = %.1f, coverBlur = %.1f\n\n" % (COVER_PAD, COVER_BLUR))
        f.write("    static let pieces: [Piece] = [\n")
        for p in pieces:
            f.write('        Piece(asset: "%s", cell: %s, side: .%s, dx: %.4f, dy: %.4f, w: %.4f, h: %.4f, normW: %.4f, normH: %.4f),\n'
                    % (p["asset"], p["cell"], "left" if p["side"] == "L" else "right", p["dx"], p["dy"], p["w"], p["h"], p["nw"], p["nh"]))
        f.write("    ]\n\n")
        f.write("    static let fits: [String: Fit] = [\n")
        for fit in fits:
            l, r = fit["eyes"]
            f.write('        "%s": Fit(radius: %.2f,\n' % (fit["key"], fit["radius"]))
            f.write("                  left: Eye(x: %.1f, y: %.1f, w: %.1f, h: %.1f, fill: [%d, %d, %d]),\n" % (l["cx"], l["cy"], l["w"], l["h"], *l["fill"]))
            f.write("                  right: Eye(x: %.1f, y: %.1f, w: %.1f, h: %.1f, fill: [%d, %d, %d])),\n" % (r["cx"], r["cy"], r["w"], r["h"], *r["fill"]))
        f.write("    ]\n}\n")

    if preview:
        os.makedirs(preview, exist_ok=True)
        write_previews(preview, catalog, pieces, fits)
    print("pieces: %d, pictures: %d" % (len(pieces), len(fits)))


SS = 4


def lay(fit, pieces, cell):
    """The picture with a cell's pieces laid on it (what the app draws), at 4x supersampling."""
    path = os.path.join(sys.argv[3], APP, fit["asset"] + ".imageset", "art@3x.png")
    base = Image.open(path).convert("RGBA")
    big = base.resize((base.width * SS, base.height * SS), Image.LANCZOS)
    if cell is None:
        return big
    for e in fit["eyes"]:
        cover = Image.new("RGBA", big.size, tuple(e["fill"]) + (0,))
        mask = Image.new("L", big.size, 0)
        ImageDraw.Draw(mask).ellipse([(e["cx"] - e["w"] / 2 - COVER_PAD) * SS, (e["cy"] - e["h"] / 2 - COVER_PAD) * SS,
                                      (e["cx"] + e["w"] / 2 + COVER_PAD) * SS, (e["cy"] + e["h"] / 2 + COVER_PAD) * SS], fill=255)
        cover.putalpha(mask.filter(ImageFilter.GaussianBlur(COVER_BLUR * SS)))
        big.alpha_composite(cover)
    for i, side in enumerate(("L", "R")):
        piece = next(p for p in pieces if p["cell"] == cell and p["side"] == side)
        e = fit["eyes"][i]
        r = fit["radius"]
        if piece["nw"] > 0:
            w = piece["w"] / piece["nw"] * e["w"]
            h = piece["h"] / piece["nh"] * e["h"]
        else:
            w, h = piece["w"] * r, piece["h"] * r
        cx, cy = e["cx"] + piece["dx"] * r, e["cy"] + piece["dy"] * r
        sprite = Image.open(os.path.join(sys.argv[3], APP, piece["asset"] + ".imageset", "art@3x.png")).convert("RGBA")
        sprite = sprite.resize((max(1, round(w * SS)), max(1, round(h * SS))), Image.LANCZOS)
        big.alpha_composite(sprite, (round((cx - w / 2) * SS), round((cy - h / 2) * SS)))
    return big


def write_previews(folder, catalog, pieces, fits):
    cells = [None] + [".gaze(column: %d, row: %d)" % (c, r) for r in range(3) for c in range(3) if (r, c) != (1, 1)] + [".half", ".closed"]
    names = ["as drawn"] + ["g%d%d" % (r, c) for r in range(3) for c in range(3) if (r, c) != (1, 1)] + ["half", "closed"]
    for fit in fits:
        tiles = []
        r = fit["radius"]
        hx, hy = fit["head"]["cx"], fit["head"]["cy"]
        for cell in cells:
            im = lay(fit, pieces, cell)
            box_ = (int((hx - r * 1.1) * SS), int((hy - r * 1.1) * SS), int((hx + r * 1.1) * SS), int((hy + r * 1.1) * SS))
            tiles.append(im.crop(box_))
        w, h = tiles[0].size
        sheet = Image.new("RGBA", (w * 4, h * 3), (243, 237, 223, 255))
        for i, t in enumerate(tiles):
            sheet.alpha_composite(t, ((i % 4) * w, (i // 4) * h))
        sheet.convert("RGB").save(os.path.join(folder, fit["key"].replace(":", "_") + ".png"))
    print("previews:", folder, "order:", ", ".join(names))


if __name__ == "__main__":
    main()
