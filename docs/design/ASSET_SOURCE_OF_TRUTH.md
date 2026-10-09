# Asset source of truth — DODDY Video Asset Library

**Owner instruction (2026-10-09):** the Google Drive folder below is the owner's **source of truth for Doddy assets**.

- **Drive folder:** <https://drive.google.com/drive/folders/1inLT9oV7wx7UM4P6nxP8yU1-29JV0_ee?usp=share_link>
- **Package name:** `DODDY-Numbered-Video-Assets-v01`
- **Authority inside the folder:** `000_Asset_Index.csv` (fast lookup) and `000_Manifest.json` (exhaustive inventory). If this page, the guide below and the live folder disagree, those two files win.

## Rules for agents

1. Look up assets in the Drive library first. Do not regenerate, redraw, rename or substitute a Doddy asset when the library already has one.
2. **Do not copy the PNG/SVG binaries into this repo** unless the owner asks for a specific file. Rights/licensing are not documented in the library (the guide itself says not to infer licensing from a filename), and the repo rule against committing unreviewed binaries still applies.
3. When a file is imported on request, keep its original `NNN_category_subject_variant_vNN` name and record the asset number, version and Drive source in the commit and in `design/` manifest notes.
4. A version suffix (`v01`, `v02`, `v03`) is not a guarantee two files are interchangeable — check the index or the image.
5. Do not describe library art (storyboards, end cards, scenes) as implemented app functionality.

## Relationship to the in-app design references

| Material | Role now |
|---|---|
| Drive `DODDY-Numbered-Video-Assets-v01` | **Owner source of truth for Doddy assets** (character poses/expressions, worlds, foregrounds, transitions, video templates). |
| `design/interface-v1.2/` (Pocket Notebook) | Still the screen/layout/token reference for the native UI. Its character SVGs are what the app currently ships. |
| `design/ios-ready-asset-catalog/` | PNG exports of the v1.2 SVGs used by the current build. |
| `assets/brand_candidate/` | Historical; unchanged. |

**Open (owner to confirm):** whether the in-app character art should be replaced by library poses (e.g. `013_doddy_idle_v01`, `016_doddy_wave_v01`, `020_doddy_talking_v03`). The library is rendered PNG video art; using it in the app needs transparent, light/dark-safe exports at iOS sizes. Until the owner picks, the app keeps its current v1.2 art.

## Access status (2026-10-09)

**Imported (2026-10-09).** The full Drive folder is in `design/video-asset-library-v01/`, including the root numbered set, the index, manifest, prompts, the Word kit and the ZIP, plus three sub-packages under `packages/`:

- `doddy-complete-scenery-16x9-v06/` — scenery (originals, home, neighbourhood, nature, seasons, European capitals).
- `doddy-extra-poses-expressions-v02/` — transparent poses, pose sheets, expression sheets, paper poses.
- `Doddy-Dynamic-Island-v4/` — "Little Instruments" V4 board set. The owner's guide said this folder was empty; it isn't. Its README says these are **static design mockups**; native actions and motion are not implemented.

Verification: the 44 root PNGs match the SHA-256 hashes in `000_Asset_Index.csv`/`000_Manifest.json`; the Dynamic Island `SHA256SUMS.txt` passes. The root `045_tpl_safearea_exact_v01.svg` has no recorded hash. PNGs and the ZIP are stored with Git LFS (see `.gitattributes`).

Still open: the guide's file list and the folder differ in places (`001`–`003`, `009`, `010` and the three sub-packages are not in the guide). Treat the manifest as authoritative.

---

## Owner-supplied guide (text verbatim, headings demoted one level)

### Doddy Video Asset Library

#### What this folder is

`DODDY-Numbered-Video-Assets-v01` is a numbered production-asset library for making Doddy video scenes. It contains PNG and SVG artwork, scene worlds, foreground layers, transitions, templates, documentation, source prompts, a CSV index, a JSON manifest, a Word overview, and a ZIP package.

The most complete machine-readable inventory is `000_Manifest.json`; the fastest human-readable lookup is `000_Asset_Index.csv`. Use those two files if this guide and the live folder ever differ.

#### Quick start

| If you need | Start here |
| --- | --- |
| A Doddy pose, face, mouth, eyes, or action | Search `doddy_` in the root folder; see the character list below. |
| A setting / background | Search `world_`; choose the matching day or night version. |
| A foreground overlay | Search `_fg_`; pair it with its matching `world_*` scene. |
| A transition | Search `trans_`. |
| Captions, end card, or safe-area guides | Search `tpl_`. |
| Prompt / generation history | Open `000_Source_Prompts.md`. |
| Exact inventory or technical lookup | Open `000_Asset_Index.csv` or `000_Manifest.json`. |
| A transferable bundle | Use `DODDY-Numbered-Video-Assets-v01.zip`. |

#### Folder map

```text
DODDY-Numbered-Video-Assets-v01/
├── Doddy-Dynamic-Island-v4/             # currently empty in the reviewed folder
├── doddy-complete-scenery-16x9-v06/     # separate scenery package
├── doddy-extra-poses-expressions-v02/   # separate pose/expression package
├── README.md                             # existing high-level README
├── 000_README.md                         # numbered-package instructions
├── 000_Source_Prompts.md                 # source / generation prompts
├── 000_Asset_Index.csv                   # compact asset lookup table
├── 000_Manifest.json                     # detailed inventory / metadata
├── Doddy-Video-Asset-Kit-and-Index.docx  # Word overview and index
├── DODDY-Numbered-Video-Assets-v01.zip   # bundled package
└── numbered artwork and templates         # assets 004–045 visible in root
```

#### Naming system

`NNN_category_subject_variant_vNN.ext`

- `NNN` is the numbered asset slot, for example `020`.
- `doddy` identifies the character asset family.
- `world` identifies a setting/background family.
- `_fg_` identifies a foreground layer intended to sit above the matching world.
- `trans` identifies a transition visual.
- `tpl` identifies a production template.
- `v01`, `v02`, `v03` are version identifiers. They do **not** automatically mean an item is safe to substitute for another version; check the index or visual result first.
- `.png` is a rendered image. `045_tpl_safearea_exact_v01.svg` is an editable vector safe-area guide.

#### Asset catalogue

##### Character assets

| Asset | Use |
| --- | --- |
| `004_doddy_expr_front_v02.png` | Front-facing expression sheet / pose. |
| `005_doddy_expr_34_v02.png` | Expression variant. |
| `006_doddy_mouths_v02.png` | Mouth shapes. |
| `007_doddy_blink_v02.png` | Blink state. |
| `008_doddy_eyes_v01.png` | Eye asset. |
| `011_doddy_fx_v01.png` | Character effects. |
| `012_doddy_walk_v01.png` | Walking pose/action. |
| `013_doddy_idle_v01.png` | Idle pose. |
| `014_doddy_run_v01.png` | Running pose/action. |
| `015_doddy_jump_v01.png` | Jumping pose/action. |
| `016_doddy_wave_v01.png` | Waving pose. |
| `017_doddy_sit_v01.png` | Sitting pose. |
| `018_doddy_turn_v01.png` | Turning pose/action. |
| `019_doddy_pop_v01.png` | Pop-in visual. |
| `020_doddy_talking_v03.png` | Talking visual. |

##### Worlds and background scenes

| World | Backgrounds | Foreground / placement companions |
| --- | --- | --- |
| Home | `022_world_home_day_v01.png`, `023_world_home_night_v01.png` | `024_world_home_fg_v01.png`, `036_world_home_placement_v01.png` |
| Court | `025_world_court_day_v01.png`, `026_world_court_night_v01.png` | `027_world_court_fg_v01.png` |
| Coffee | `028_world_coffee_day_v01.png`, `029_world_coffee_night_v01.png` | `030_world_coffee_fg_v01.png` |
| Memory | `031_world_memory_day_v01.png`, `032_world_memory_night_v01.png` | `033_world_memory_fg_v01.png` |
| Rooftop | `034_world_rooftop_night_v01.png` | `035_world_rooftop_fg_v01.png` |

Also present: `021_world_styleframe_v01.png`, a world style reference.

##### Transitions

| Asset | Use |
| --- | --- |
| `037_trans_phone_v01.png` | Phone transition. |
| `038_trans_page_v01.png` | Page transition. |
| `039_trans_door_v01.png` | Door transition. |
| `040_trans_ink_v01.png` | Ink transition. |

##### Templates and production guides

| Asset | Use |
| --- | --- |
| `041_rw_keys_storyboard_v01.png` | Storyboard / key visual reference. |
| `042_tpl_safearea_v01.png` | Safe-area template. |
| `043_tpl_endcard_v01.png` | End-card template. |
| `044_tpl_caption_v01.png` | Caption template. |
| `045_tpl_safearea_exact_v01.svg` | Editable exact safe-area template. |

#### How to find the right file

1. Use Drive search from this folder and enter the smallest useful keyword: `doddy`, `world`, `court`, `coffee`, `memory`, `rooftop`, `fg`, `trans`, `tpl`, `caption`, or `safearea`.
2. For a scene, first choose the `world_*_day_*` or `world_*_night_*` background. Then search that same world name plus `fg` to find its foreground layer.
3. For a character moment, use `doddy_` plus the action (`talking`, `wave`, `walk`, `jump`, `sit`, `run`, `turn`, `blink`) rather than browsing visually.
4. For production overlays, search `tpl_`. Use the SVG safe-area file when an editable guide is needed; use the PNG when a rendered reference is enough.
5. If the filename does not make the use clear, filter the CSV index by the number or filename, then cross-check `000_Manifest.json`.

#### Recommended video workflow

1. Choose a world and time-of-day background.
2. Add the matching foreground layer if that scene has one.
3. Place the required Doddy pose or facial/mouth asset over the world.
4. Use `036_world_home_placement_v01.png` only as a placement companion for the home scene; do not assume it applies to the other worlds.
5. Use a `trans_*` asset between scene beats where it visually fits.
6. Apply the safe-area and caption templates before finalising titles or captions.
7. Use the end-card template for the final frame.
8. Check the README, CSV index, manifest, and source prompts before regenerating, renaming, or replacing an asset.

#### Important documentation and packages

| File | Why to open it |
| --- | --- |
| `README.md` | Existing high-level guide for the folder. |
| `000_README.md` | Instructions tied to the numbered package. |
| `000_Asset_Index.csv` | Fastest sortable source of truth for finding an exact asset. |
| `000_Manifest.json` | Detailed inventory and metadata; use it to audit completeness. |
| `000_Source_Prompts.md` | Prompt history for reuse, iteration, or provenance checks. |
| `Doddy-Video-Asset-Kit-and-Index.docx` | Portable human-readable kit and index. |
| `DODDY-Numbered-Video-Assets-v01.zip` | Transfer/export bundle; do not treat it as a separate source of truth. |

#### Known gaps and safeguards

- The reviewed `Doddy-Dynamic-Island-v4` subfolder was empty at review time.
- The exact contents of the two sibling packages (`doddy-complete-scenery-16x9-v06` and `doddy-extra-poses-expressions-v02`) should be checked directly before relying on them; they are intentionally kept separate from the numbered root set.
- This guide documents filenames visible in the reviewed folder. The CSV index and JSON manifest remain the authority for a fully exhaustive, revision-accurate record.
- Do not infer application compatibility, layer order, licensing, or an asset's generation method solely from a filename.

#### Maintenance rules

- Keep the `NNN_category_subject_variant_vNN.ext` pattern for new numbered root assets.
- Increment the version only when publishing a distinct revision; do not silently overwrite an existing version.
- Add new root assets to both `000_Asset_Index.csv` and `000_Manifest.json` in the same change.
- Update `000_Source_Prompts.md` when an asset is generated or materially regenerated from a new prompt.
- Keep reusable source files, rendered exports, templates, and ZIP bundles clearly distinguished.
- Update this guide whenever folders are added, removed, or re-scoped.
