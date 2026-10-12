#!/usr/bin/env python3
"""Build Doddy's app icons from the owner's pack art (ADR-460).

Source: DoddyApp/Resources/Assets.xcassets/UploadedDoddy_Listening.imageset/art.png, byte-identical to
the pack's doddy_listening_v02.png (SHA-256 checked below). The pose is cropped to a square around the
head and the raised hand and placed, unchanged, on a flat background. Nothing is redrawn or recoloured.

  light: the pose on the pack's paper canvas (#F5EFE2)
  dark:  the pose on a paper disc, on the pack's dark canvas (#1D1C19); the light paper backing the
         pack art already uses in dark mode (docs/design/UPLOADED_MEMORY_ASSETS.md)

Writes the iPhone light and dark icons and the watch icon (1024 x 1024, RGB, no alpha).
Usage: python3 -I tools/make_app_icon.py [--preview OUT.png]
"""
import hashlib
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "DoddyApp/Resources/Assets.xcassets/UploadedDoddy_Listening.imageset/art.png"
SOURCE_SHA256 = "96375303e59d4b5f272805abb896a14ba3fcec37e8420a2dd04ec8b66823bc41"
IPHONE = ROOT / "DoddyApp/Resources/Assets.xcassets/AppIcon.appiconset"
WATCH = ROOT / "DoddyWatch/Assets.xcassets/AppIcon.appiconset"

SIZE = 1024
PAPER = (0xF5, 0xEF, 0xE2)       # UploadedColorRole.canvas, light
DARK = (0x1D, 0x1C, 0x19)        # UploadedColorRole.canvas, dark
# Square crops of the 1024 x 1536 pose, in source pixels: head, raised hand, sparks and shoulders.
# The dark icon's crop is the same one with 95 px more on each side, so the pose fills its smaller disc
# at 80% of the light icon's size and the arms and body run to the disc's edge.
CROP = (150, 120, 910, 880)
DARK_CROP = (55, 25, 1005, 975)


def pose(crop: tuple[int, int, int, int]) -> Image.Image:
    data = SOURCE.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != SOURCE_SHA256:
        sys.exit(f"{SOURCE} is not the pack's doddy_listening_v02.png (sha256 {digest})")
    art = Image.open(SOURCE).convert("RGBA").crop(crop)
    return art.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def light(art: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (SIZE, SIZE), PAPER + (255,))
    canvas.alpha_composite(art)
    return canvas.convert("RGB")


def dark(art: Image.Image) -> Image.Image:
    # The disc is drawn at 4x and scaled down for a smooth edge; the pose is clipped to it.
    inset = 64
    big = Image.new("L", (SIZE * 4, SIZE * 4), 0)
    ImageDraw.Draw(big).ellipse((inset * 4, inset * 4, (SIZE - inset) * 4, (SIZE - inset) * 4), fill=255)
    disc = big.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    paper = Image.new("RGBA", (SIZE, SIZE), PAPER + (255,))
    paper.alpha_composite(art)
    canvas = Image.new("RGBA", (SIZE, SIZE), DARK + (255,))
    canvas.paste(paper, (0, 0), disc)
    return canvas.convert("RGB")


def main() -> None:
    art = pose(CROP)
    icons = {IPHONE / "AppIcon.png": light(art), IPHONE / "AppIcon-dark.png": dark(pose(DARK_CROP)),
             WATCH / "AppIcon.png": light(art)}
    if len(sys.argv) == 3 and sys.argv[1] == "--preview":
        sheet = Image.new("RGB", (SIZE * 2 + 40, SIZE), (128, 128, 128))
        sheet.paste(icons[IPHONE / "AppIcon.png"], (0, 0))
        sheet.paste(icons[IPHONE / "AppIcon-dark.png"], (SIZE + 40, 0))
        sheet.save(sys.argv[2])
        return
    for path, image in icons.items():
        image.save(path, optimize=True)
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
