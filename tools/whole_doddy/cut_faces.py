"""Cut the round faces the island's compact and minimal views draw (ADR-264, ADR-773).

The island used to crop a face out of a whole pose at draw time: a 52 x 79 pt picture, offset
and clipped to 24 pt inside the Dynamic Island's small slot. A Live Activity can't be relied on
to render that (the left compact side stayed an empty grey circle), so the face is cut here
once, as its own small picture, and the view draws it as it is.

Only the owner's pictures are used: each face is a crop of an existing `WholeDoddy_<pose>`
image set (themselves downscaled copies of the pack's 01-transparent-poses), cut to the head
circle that `IslandPose.head` gives, with the pixels outside the circle made transparent.
Nothing is redrawn or recoloured.

    python3 -I tools/whole_doddy/cut_faces.py <repo root>

Each circle is the cream disc of his face plus a 4/400 rim (3 px at the 300 x 450 pictures),
measured from the pictures (12 Nov 2026, decision 2026-11-12-action-button-audio-and-island). Until
then the circle was the whole head outline widened by 6 %, and it took in what touches his head:
the hand cupped at his ear and an orange sound mark in "listening" (the face the island shows
through a whole conversation), arms and neck in "yawn_stretch", a stub of neck under the others.
At 26 pt those read as stray marks on the island. On the black island the rim is all of the
outline that is needed.

Writes `WholeDoddy_face_<pose>.imageset` (art@2x = 52 px, art@3x = 78 px: the compact island
draws the face at 26 pt) in the app and the widget catalogs. Keep HEADS in step with
`IslandPose.head` (IslandPose.swift); scripts/check_island_art.sh checks the image sets exist, the
Swift checks the head boxes.
"""
import json
import os
import sys
from PIL import Image, ImageDraw

APP = "DoddyApp/Resources/Assets.xcassets"
WIDGETS = "DoddyWidgets/Assets.xcassets"
INFO = {"author": "xcode", "version": 1}
# Face centre and diameter as fractions of the picture's width and height (IslandPose.head): the
# cream disc's box, plus the rim.
HEADS = {
    "listening": (201.3 / 400, 150.7 / 600, 157.3 / 400),
    "shush": (204.0 / 400, 140.0 / 600, 208.0 / 400),
    "yawn_stretch": (200.0 / 400, 186.0 / 600, 149.3 / 400),
    "crosslegged": (200.7 / 400, 186.0 / 600, 185.3 / 400),
}
# The rim is already in HEADS.
MARGIN = 1.0
SUPERSAMPLE = 4
# Pixels at 2x and 3x for the 26 pt the compact island draws (the minimal island's 24 pt scales down).
SIZES = (("2x", 52), ("3x", 78))


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
            for scale, size in SIZES:
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
