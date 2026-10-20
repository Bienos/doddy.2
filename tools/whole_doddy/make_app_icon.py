"""The app icon from the pack's wave frame (ADR-547, Brand Guidelines V2.2).

The owner chose frame 4 of 016_doddy_wave_v01.png (the pack's only wave) for the icon. Start from
cut_wave.py's output (488 x 733, transparent; SHA-256 20b648fd…). A 410 px square of it, x 35–445
and y 95–505 (the head, the waving hand and the orange marks, cut at the torso: the same framing
as the website's favicon and touch icon), is placed on brand paper #FFF7E9 and Lanczos-resized to
1024 px, RGB with no alpha. The same bytes go to the iPhone and the Watch icon sets. There is no
dark appearance: the pack's ink would vanish on night, and recolouring it is not allowed.
Nothing is redrawn or recoloured.

    python3 -I tools/whole_doddy/make_app_icon.py <wave cut-out png> <repo root>
"""
import os
import sys
from PIL import Image

PAPER = (0xFF, 0xF7, 0xE9)  # brand.paper (Brand Guidelines V2.2 p.20, ADR-546)
X0, Y0, SIDE = 35, 95, 410
SIZE = 1024
TARGETS = [
    "DoddyApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    "DoddyWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
]


def icon(cut):
    region = cut.crop((X0, Y0, X0 + SIDE, Y0 + SIDE))
    canvas = Image.new("RGBA", (SIDE, SIDE), PAPER + (255,))
    canvas.alpha_composite(region)
    return canvas.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)


def main(cut_path, repo):
    cut = Image.open(cut_path).convert("RGBA")
    if cut.size != (488, 733):
        raise SystemExit(f"expected cut_wave.py's 488 x 733 output, got {cut.size}")
    image = icon(cut)
    for target in TARGETS:
        path = os.path.join(repo, target)
        image.save(path, optimize=True)
        print("wrote", target)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
