"""Build the ADR-299 image sets from the owner's DODDY-Numbered-Video-Assets-v01 pack.

Every picture comes from the pack. Poses and frames are only cut out and downscaled (Lanczos);
the storybook pages, scenery and the watch face are only cropped and downscaled. Nothing is
redrawn, recoloured or generated.

    python3 -I tools/whole_doddy/build_imagesets.py <pack dir> <cuts dir> <repo root> [<strips dir>]

<pack dir> holds the pack's folders as downloaded: poses/ (01-transparent-poses),
world/ (021-036) and the cut outputs in <cuts dir>:
    cut_frames.py numbered/020_doddy_talking_v03.png <cuts>/talking   (6 frames)
    cut_panels.py trans/038_trans_page_v01.png <cuts>/page            (4 panels)
and, for ADR-313, the strips cut with `--shared` into <strips dir> (see STRIPS below).
"""
import json
import os
import sys
from PIL import Image

APP = "DoddyApp/Resources/Assets.xcassets"
WIDGETS = "DoddyWidgets/Assets.xcassets"
WATCH = "DoddyWatchWidgets/Assets.xcassets"
WATCH_APP = "DoddyWatch/Assets.xcassets"
INFO = {"author": "xcode", "version": 1}


def write_json(path, value):
    with open(path, "w") as f:
        json.dump(value, f, indent=2)


def scaled_set(catalog, name, picture, size2x):
    """art@2x and art@3x, Lanczos downscales of one picture."""
    folder = os.path.join(catalog, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    w, h = size2x
    picture.resize((w, h), Image.LANCZOS).save(os.path.join(folder, "art@2x.png"), optimize=True)
    picture.resize((w * 3 // 2, h * 3 // 2), Image.LANCZOS).save(os.path.join(folder, "art@3x.png"), optimize=True)
    write_json(os.path.join(folder, "Contents.json"), {"images": [
        {"filename": "art@2x.png", "idiom": "universal", "scale": "2x"},
        {"filename": "art@3x.png", "idiom": "universal", "scale": "3x"},
    ], "info": INFO})


def photo_set(catalog, name, day, night=None, width=None):
    """One JPEG per appearance (single scale); the night picture is the dark appearance."""
    folder = os.path.join(catalog, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    images = []
    for picture, filename, dark in ((day, "day.jpg", False), (night, "night.jpg", True)):
        if picture is None:
            continue
        if width and picture.width > width:
            picture = picture.resize((width, round(picture.height * width / picture.width)), Image.LANCZOS)
        picture.convert("RGB").save(os.path.join(folder, filename), quality=84, optimize=True)
        entry = {"filename": filename, "idiom": "universal"}
        if dark:
            entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        images.append(entry)
    write_json(os.path.join(folder, "Contents.json"), {"images": images, "info": INFO})


def main(pack, cuts, root, strips=None):
    app, widgets, watch = (os.path.join(root, c) for c in (APP, WIDGETS, WATCH))

    # 2. Read aloud: the belly-reading pose, same frame and sizes as the other WholeDoddy poses.
    reading = Image.open(os.path.join(pack, "poses/doddy_belly_reading_v02.png")).convert("RGBA")
    for catalog in (app, widgets):
        scaled_set(catalog, "WholeDoddy_belly_reading", reading, (200, 300))

    # 5. Talking: the six frames of 020, in the same 2:3 frame as the poses.
    for i in range(1, 7):
        frame = Image.open(os.path.join(cuts, f"talking_{i}.png")).convert("RGBA")
        scaled_set(app, f"VoiceDoddy_talking_{i}", frame, (200, 300))

    # 8. Storybook: the four panels of 038's page turn.
    for i in range(1, 5):
        photo_set(app, f"Storybook_page_{i}", Image.open(os.path.join(cuts, f"page_{i}.jpg")))

    # 4. Scenery: day and night of each place (the night picture is the dark appearance).
    world = os.path.join(pack, "world")
    for name, day, night in (("home", "022_world_home_day_v01", "023_world_home_night_v01"),
                             ("memory", "031_world_memory_day_v01", "032_world_memory_night_v01"),
                             ("coffee", "028_world_coffee_day_v01", "029_world_coffee_night_v01")):
        photo_set(app, f"Scenery_{name}", Image.open(os.path.join(world, f"{day}.png")),
                  Image.open(os.path.join(world, f"{night}.png")), width=780)

    # 7. Watch: a square crop of the listening pose's face (head centre 514, 387; a 470 square
    # in the 1024 x 1536 original). Crop only.
    listening = Image.open(os.path.join(pack, "poses/doddy_listening_v02.png")).convert("RGBA")
    face = listening.crop((514 - 235, 387 - 235, 514 + 235, 387 + 235))
    os.makedirs(watch, exist_ok=True)
    write_json(os.path.join(watch, "Contents.json"), {"info": INFO})
    folder = os.path.join(watch, "WatchDoddy_face.imageset")
    os.makedirs(folder, exist_ok=True)
    face.resize((96, 96), Image.LANCZOS).save(os.path.join(folder, "face@2x.png"), optimize=True)
    write_json(os.path.join(folder, "Contents.json"), {"images": [
        {"filename": "face@2x.png", "idiom": "universal", "scale": "2x"},
    ], "info": INFO})
    if strips:
        build_313(pack, strips, app, widgets)
        build_314(pack, root, app, widgets)
        build_324(strips, root, app, widgets)
    print("done")


# ADR-313: the strips, cut with tools/whole_doddy/cut_frames.py --shared, and which frames the
# app uses: (strip, sheet, --rows-max-y, extra flags, frames used).
STRIPS = [
    ("walk", "012_doddy_walk_v01", 567, [], range(1, 9)),
    ("run", "014_doddy_run_v01", 568, [], range(1, 7)),
    ("jump", "015_doddy_jump_v01", 596, ["--min-fraction", "0.3"], range(1, 6)),
    ("turn", "018_doddy_turn_v01", 605, [], range(1, 4)),
    ("pop", "019_doddy_pop_v01", 640, ["--min-fraction", "0"], range(1, 5)),
    ("idle", "013_doddy_idle_v01", 760, [], range(1, 5)),
    # ADR-323: he sits down on a box after the idle breaths.
    ("sit", "017_doddy_sit_v01", 582, [], range(1, 6)),
]


def build_313(pack, strips, app, widgets):
    # Focus and breathing islands: two more poses from 01-transparent-poses.
    for name in ("basketball_dribble", "oneleg_balance"):
        pose = Image.open(os.path.join(pack, f"poses/doddy_{name}_v02.png")).convert("RGBA")
        for catalog in (app, widgets):
            scaled_set(catalog, f"WholeDoddy_{name}", pose, (200, 300))
    # Strip frames, app only.
    for strip, _, _, _, used in STRIPS:
        for i in used:
            frame = Image.open(os.path.join(strips, f"{strip}_{i}.png")).convert("RGBA")
            scaled_set(app, f"DoddyMotion_{strip}_{i}", frame, (200, 300))
    # Scenery: the court (day / night) for focus, the rooftop (night only) for the look-back.
    world = os.path.join(pack, "world")
    photo_set(app, "Scenery_court", Image.open(os.path.join(world, "025_world_court_day_v01.png")),
              Image.open(os.path.join(world, "026_world_court_night_v01.png")), width=780)
    photo_set(app, "Scenery_rooftop", Image.open(os.path.join(world, "034_world_rooftop_night_v01.png")), width=780)
    # The Lock Screen widget's face: the watch face's crop, at iPhone sizes.
    listening = Image.open(os.path.join(pack, "poses/doddy_listening_v02.png")).convert("RGBA")
    face = listening.crop((514 - 235, 387 - 235, 514 + 235, 387 + 235))
    scaled_set(widgets, "WidgetDoddy_face", face, (120, 120))


def build_314(pack, root, app, widgets):
    """ADR-323: the "Pause all connections" pose, and two poses for the watch app itself."""
    crouch = Image.open(os.path.join(pack, "poses/doddy_sneaky_crouch_v02.png")).convert("RGBA")
    for catalog in (app, widgets):
        scaled_set(catalog, "WholeDoddy_sneaky_crouch", crouch, (200, 300))
    watch_app = os.path.join(root, WATCH_APP)
    os.makedirs(watch_app, exist_ok=True)
    write_json(os.path.join(watch_app, "Contents.json"), {"info": INFO})
    for name in ("crosslegged", "fistpump"):
        pose = Image.open(os.path.join(pack, f"poses/doddy_{name}_v02.png")).convert("RGBA")
        folder = os.path.join(watch_app, f"WatchDoddy_{name}.imageset")
        os.makedirs(folder, exist_ok=True)
        pose.resize((120, 180), Image.LANCZOS).save(os.path.join(folder, "art@2x.png"), optimize=True)
        write_json(os.path.join(folder, "Contents.json"), {"images": [
            {"filename": "art@2x.png", "idiom": "universal", "scale": "2x"},
        ], "info": INFO})


def build_324(strips, root, app, widgets):
    """ADR-331: Doddy turned away (frame 5 of the turn strip) for notes hidden from widgets and
    the watch."""
    away = Image.open(os.path.join(strips, "turn_5.png")).convert("RGBA")
    for catalog in (app, widgets):
        scaled_set(catalog, "WholeDoddy_turned_away", away, (200, 300))
    folder = os.path.join(root, WATCH_APP, "WatchDoddy_turned_away.imageset")
    os.makedirs(folder, exist_ok=True)
    away.resize((120, 180), Image.LANCZOS).save(os.path.join(folder, "art@2x.png"), optimize=True)
    write_json(os.path.join(folder, "Contents.json"), {"images": [
        {"filename": "art@2x.png", "idiom": "universal", "scale": "2x"},
    ], "info": INFO})


if __name__ == "__main__":
    main(*sys.argv[1:5])
