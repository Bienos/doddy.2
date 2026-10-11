"""Cut the round faces the island's compact and minimal views draw (ADR-264).

The island used to crop a face out of a whole pose at draw time: a 52 x 79 pt picture, offset
and clipped to 24 pt inside the Dynamic Island's small slot. A Live Activity can't be relied on
to render that (the left compact side stayed an empty grey circle), so the face is cut here
once, as its own small picture, and the view draws it as it is.

Only the owner's pictures are used: each face is a crop of an existing `WholeDoddy_<pose>`
image set (themselves downscaled copies of the pack's 01-transparent-poses), cut to the head
circle that `IslandPose.head` gives, with the pixels outside the circle made transparent.
Nothing is redrawn or recoloured.

    python3 -I tools/whole_doddy/cut_faces.py <repo root>

Writes `WholeDoddy_face_<pose>.imageset` (art@2x = 48 px, art@3x = 72 px) in the app and the
widget catalogs. Keep HEADS in step with `IslandPose.head` (IslandPose.swift);
scripts/check_island_art.sh checks the image sets exist, the Swift checks the head boxes.
"""
import json
import os
import sys
from PIL import Image, ImageDraw

APP = "DoddyApp/Resources/Assets.xcassets"
WIDGETS = "DoddyWidgets/Assets.xcassets"
INFO = {"author": "xcode", "version": 1}
# Head centre and diameter as fractions of the picture's width and height (IslandPose.head).
HEADS = {
    "listening": (205 / 400, 152 / 600, 172 / 400),
    "shush": (203 / 400, 140 / 600, 190 / 400),
    "yawn_stretch": (201 / 400, 212 / 600, 160 / 400),
    "crosslegged": (200 / 400, 179 / 600, 196 / 400),
}
# The circle is a little wider than the head, as in the view that cropped it (diameter * 1.06).
MARGIN = 1.06
SUPERSAMPLE = 4


def face(picture, head):
    x, y, d = head
    side = d * picture.width * MARGIN
    cx, cy = x * picture.width, y * picture.height
    box = (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2)
    return picture.crop(tuple(round(v) for v in box)), side


def round_mask(size):
    big = Image.new("L", (size * SUPERSAMPLE, size * SUPERSAMPLE), 0)
    ImageDraw.Draw(big).ellipse((0, 0, size * SUPERSAMPLE - 1, size * SUPERSAMPLE - 1), fill=255)
    return big.resize((size, size), Image.LANCZOS)


def main(root):
    for pose, head in HEADS.items():
        source = Image.open(os.path.join(root, WIDGETS, f"WholeDoddy_{pose}.imageset", "art@3x.png")).convert("RGBA")
        crop, _ = face(source, head)
        for catalog in (APP, WIDGETS):
            folder = os.path.join(root, catalog, f"WholeDoddy_face_{pose}.imageset")
            os.makedirs(folder, exist_ok=True)
            for scale, size in (("2x", 48), ("3x", 72)):
                picture = crop.resize((size, size), Image.LANCZOS)
                alpha = Image.composite(picture.getchannel("A"), Image.new("L", (size, size), 0), round_mask(size))
                picture.putalpha(alpha)
                picture.save(os.path.join(folder, f"art@{scale}.png"), optimize=True)
            with open(os.path.join(folder, "Contents.json"), "w") as f:
                json.dump({"images": [
                    {"filename": "art@2x.png", "idiom": "universal", "scale": "2x"},
                    {"filename": "art@3x.png", "idiom": "universal", "scale": "3x"},
                ], "info": INFO}, f, indent=2)
        print(f"WholeDoddy_face_{pose}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
