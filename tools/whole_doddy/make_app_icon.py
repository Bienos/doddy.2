"""The app icon: Doddy's face on the brand orange (ADR-565, Brand Guidelines V2.2).

The owner chose "just his face", on orange (option B of four shown). The face is the first head of the
pack's blink sheet, 007_doddy_blink_v02.png (2172 x 724, transparent, four heads: open, half closed,
closed, half closed; SHA-256 1de78fb2…), the same sheet the eyes come from (ADR-560). Tile 1 (x 0–543)
is cut to its ink (alpha above 8), 369 x 363 px: the head, both open eyes, the one brow and the smile.
It is Lanczos-resized to 780 px wide and centred on brand orange #FF6A00 at 1024 px, RGB with no alpha.
The same bytes go to the iPhone and the Watch icon sets. There is no dark appearance: the orange and
the cream face read on a dark Home Screen as they are. The website's favicon (64 px) and touch icon
(180 px) are that icon Lanczos-resized, so the site and the app show the same picture. Nothing is
redrawn or recoloured.

    python3 -I tools/whole_doddy/make_app_icon.py <007_doddy_blink_v02.png> <repo root>
"""
import hashlib
import os
import sys
from PIL import Image

SOURCE_SHA256 = "1de78fb26e69b50cb7984630a5f994f26274307749a961ca2b56f90bcb267a2a"
ORANGE = (0xFF, 0x6A, 0x00)  # brand.orange (Brand Guidelines V2.2 p.20, ADR-556)
TILE = (0, 0, 543, 724)  # the open head, the first of the sheet's four
FACE_WIDTH = 780
SIZE = 1024
TARGETS = [
    "DoddyApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    "DoddyWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
]
SITE_TARGETS = [
    ("site/assets/doddy-favicon.png", 64),
    ("site/assets/doddy-touch-icon.png", 180),
]


def icon(sheet):
    tile = sheet.crop(TILE)
    face = tile.crop(tile.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
    if face.size != (369, 363):
        raise SystemExit(f"expected the open head to be 369 x 363 px, got {face.size}")
    height = round(face.size[1] * FACE_WIDTH / face.size[0])
    face = face.resize((FACE_WIDTH, height), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), ORANGE + (255,))
    canvas.alpha_composite(face, ((SIZE - FACE_WIDTH) // 2, (SIZE - height) // 2))
    return canvas.convert("RGB")


def main(sheet_path, repo):
    digest = hashlib.sha256(open(sheet_path, "rb").read()).hexdigest()
    if digest != SOURCE_SHA256:
        raise SystemExit(f"{sheet_path} has SHA-256 {digest}, expected the pack's {SOURCE_SHA256}")
    sheet = Image.open(sheet_path).convert("RGBA")
    if sheet.size != (2172, 724):
        raise SystemExit(f"expected the 2172 x 724 blink sheet, got {sheet.size}")
    image = icon(sheet)
    for target in TARGETS:
        path = os.path.join(repo, target)
        image.save(path, optimize=True)
        print("wrote", target)
    for target, size in SITE_TARGETS:
        image.resize((size, size), Image.LANCZOS).save(os.path.join(repo, target), optimize=True)
        print("wrote", target)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
