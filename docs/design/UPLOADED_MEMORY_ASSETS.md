# Owner-supplied memory artwork — 10 October 2026

Source: `/Users/popcorn/Downloads/DODDY-Numbered-Video-Assets-v01.zip`.
The owner explicitly selected this numbered ZIP, then approved the memory-journey
mockups for implementation. No new generated characters, downloaded fonts or outside
art were added. Existing candidate image sets and archived packs remain unchanged.
This records provenance, not an independent commercial-rights determination.

All five native `UploadedDoddy_*.imageset/art.png` files are byte-identical to these
ZIP entries. Prefix for every entry below:

`DODDY-Numbered-Video-Assets-v01/doddy-extra-poses-expressions-v02/doddy-extra-poses-expressions-v02/01-transparent-poses/`

| Native image set | ZIP filename | SHA-256 |
| --- | --- | --- |
| UploadedDoddy_Sitting | doddy_crosslegged_v02.png | f9496932f6944096c626301c00cc49070ea4fc71cbbf6516d27807c12ca58db6 |
| UploadedDoddy_Listening | doddy_listening_v02.png | 96375303e59d4b5f272805abb896a14ba3fcec37e8420a2dd04ec8b66823bc41 |
| UploadedDoddy_Inspect | doddy_kneeling_inspect_v02.png | c9a6d37b6e0ae53f321b6d93961f32688e2819ef3d9d84b8c30e51acf8bf380d |
| UploadedDoddy_Kept | doddy_fistpump_v02.png | c7a1fd158652d6420c67ce51d2e60e6b4808392fc131c108c7e348acf80a0561 |
| UploadedDoddy_Privacy | doddy_shush_v02.png | 69fa189d4e81c86b3387ee4172709a16af2c4b8aca00dd86e28382f20e57140f |

Verified directly by `unzip -p` of each exact ZIP entry piped to `shasum -a 256`,
compared with `shasum -a 256` of the corresponding native PNG; all five pairs match.
Dark appearance adds a light paper backing around the unchanged image. Artwork is
decorative, can be hidden in Settings, and has no invented animation/state behaviour.
The existing development app icon is not replaced or represented as final branding.

## Widget copies (Live Activity, 10 October 2026)

`DoddyWidgets/Assets.xcassets/UploadedDoddy_{Listening,Kept,Sitting}.imageset` hold `art@2x.png`
(107×160 px) and `art@3x.png` (160×240 px): Lanczos downscales of the three files above, with no
crop, recolour or other edit. Live Activity images must stay small; the app keeps the
byte-identical originals. Regenerate from the originals if the ZIP files change.

## Whole Doddy island poses (ADR-264, 11 October 2026)

Owner: "only use assets from these folders" (the Google Drive folder `DODDY-Numbered-Video-Assets-v01`)
and "deploy it" for the Whole Doddy island design. Source: that folder's
`doddy-extra-poses-expressions-v02/doddy-extra-poses-expressions-v02/01-transparent-poses/`, downloaded on
11 October 2026. The five poses already imported above are byte-identical to the Drive copies.

`DoddyApp/Resources/Assets.xcassets` and `DoddyWidgets/Assets.xcassets` each hold
`WholeDoddy_<pose>.imageset` with `art@2x.png` (200×300 px) and `art@3x.png` (300×450 px): Lanczos
downscales of the 1024×1536 originals below, with no crop, recolour or other edit. On the black island
the app draws a 1 pt cream edge around the picture (`islandCreamEdge`); the files are unchanged.
Compact and minimal crop a face from four of them in code (`IslandPose.head`). Regenerate from the
originals if the pack changes. The originals are not stored in the repository.

| Image set | Pack filename | SHA-256 of the original |
| --- | --- | --- |
| WholeDoddy_yawn_stretch | doddy_yawn_stretch_v02.png | a44ab38ca215306813c0d5bef93119e1f94c63544665f42c6fffd9a576371696 |
| WholeDoddy_listening | doddy_listening_v02.png | 96375303e59d4b5f272805abb896a14ba3fcec37e8420a2dd04ec8b66823bc41 |
| WholeDoddy_kneeling_inspect | doddy_kneeling_inspect_v02.png | c9a6d37b6e0ae53f321b6d93961f32688e2819ef3d9d84b8c30e51acf8bf380d |
| WholeDoddy_shrug | doddy_shrug_v02.png | c68edf3ca4ed3c7b9390c97b99ab2136e8ac0638bf3ae4d73af1d384d7ff315f |
| WholeDoddy_shush | doddy_shush_v02.png | 69fa189d4e81c86b3387ee4172709a16af2c4b8aca00dd86e28382f20e57140f |
| WholeDoddy_facepalm | doddy_facepalm_v02.png | 606616ac149aa95a183336dbd51ebd58fded9bdbca451b4c0750df9d0892c771 |
| WholeDoddy_crosslegged | doddy_crosslegged_v02.png | f9496932f6944096c626301c00cc49070ea4fc71cbbf6516d27807c12ca58db6 |
| WholeDoddy_leaning | doddy_leaning_v02.png | 15ff3a4e193931e1978719f03b2ef640f610af8d38c2a405ef600cca187dbcd4 |
| WholeDoddy_reaching_high | doddy_reaching_high_v02.png | ae36fc8d428907d7953c1505314b3d805f22e89157e46b6d05dc49fd57e8a031 |
| WholeDoddy_fistpump | doddy_fistpump_v02.png | c7a1fd158652d6420c67ce51d2e60e6b4808392fc131c108c7e348acf80a0561 |
| WholeDoddy_tiptoe | doddy_tiptoe_v02.png | 3dbb2824f699f0845c4f683daebd3bdee535763a2a321fa84400749647382f56 |

### The greeting wave (ADR-290)

`WholeDoddy_wave` is the one Whole Doddy picture that is not a straight downscale. The pack's only
wave is `016_doddy_wave_v01.png` (in the folder's root and in `DODDY-Numbered-Video-Assets-v01.zip`;
SHA-256 `817a2b87f220eb74c2006de13ec87b87b4114e358099d8ba69e5b15c2cdc98cd`), five frames on paper.
`tools/whole_doddy/cut_wave.py` takes frame 4 (open hand with the orange marks) and removes only
the paper connected to the frame's edges; Doddy's face and shoes, inside his outline, keep their
cream. Nothing is redrawn or recoloured; the light fringe next to removed paper fades out. The cut-out
(488 × 733, SHA-256 `20b648fd3de622db8b3ba102f45e3c1d05ce5fce699b388e7c9038fd9bbe5976`) is then
Lanczos-downscaled to 200 × 300 and 300 × 450 like the others. `WholeDoddy_oneleg_balance`, the
greeting before this, was removed.


## More of Doddy's world in the app (ADR-299, 11 October 2026)

Owner: "Do all" (the eight additions proposed after the wave). Every picture is from the same Drive
folder, downloaded on 11 October 2026; the originals are not stored in the repository.
`tools/whole_doddy/build_imagesets.py` rebuilds every image set below from them (after the two
cutters), so they can be regenerated if the pack changes. Nothing is redrawn, recoloured or generated:
poses and frames are cut out and downscaled; pages, scenery and the watch face are cropped and
downscaled.

| Image set(s) | Pack file | SHA-256 of the original | What was done |
| --- | --- | --- | --- |
| `WholeDoddy_belly_reading` (app and widgets) | 01-transparent-poses/doddy_belly_reading_v02.png | a7aadce203c3687d89d03b8f2d8d38188cb45675ae011aac975dceb33ba69b7c | Lanczos to 200×300 and 300×450, like the other poses |
| `VoiceDoddy_talking_1` … `_6` (app) | 020_doddy_talking_v03.png (1254×1254, six frames on paper) | bf817e0d4aa7a0f4d892ec013ac69562c021b65a3ff8b6a29624279063556851 | `cut_frames.py`: frames found at all-paper rows and columns; only the paper touching each frame's edges removed (the cream face and shoes stay); placed on a 2:3 transparent canvas; Lanczos to 200×300 and 300×450 |
| `Storybook_page_1` … `_4` (app) | 038_trans_page_v01.png (1942×809, four bordered panels) | 11816f914ecf07361e60c0bb626de2983ef00b7deae56f3267555771381ca34a | `cut_panels.py`: each panel cropped 6 px inside its border (about 457×695); JPEG |
| `Scenery_home` (day / night appearance) | 022_world_home_day_v01.png / 023_world_home_night_v01.png | b197008f3f5c9593af44ef35b83c93360972039f21669d3c4b8e86f2aca55d1d / 4bad5b1a4928c4fc80c9c0f58d477c6936c7daecba5a8fbce336c88c7218e374 | Lanczos from 941 to 780 px wide; JPEG; night is the dark appearance |
| `Scenery_memory` | 031_world_memory_day_v01.png / 032_world_memory_night_v01.png | f094c1d60aee4b5a0d5d1fb5312c0fa56e4c741c4b5a69f459c8daad6fe7521d / 225c45007b279cb6a890ec4aa181f38af0c473d0b9af50d326d5944d9cb0d378 | as above |
| `Scenery_coffee` | 028_world_coffee_day_v01.png / 029_world_coffee_night_v01.png | 15191a0263cc3cabee9d5e41aaecfebe0c62f393f66c28c82153303bd5eeb8f0 / 9ef98509db55d713649828b256ae06f157c9238094658c54a87ecc558d0e69b3 | as above |
| `WatchDoddy_face` (watch widgets) | 01-transparent-poses/doddy_listening_v02.png | 96375303e59d4b5f272805abb896a14ba3fcec37e8420a2dd04ec8b66823bc41 | 470×470 crop around the head (centre 514, 387), Lanczos to 96×96 |

The 038 panels are a storyboard for a video transition; the app shows them as still pictures with
cross-fades (no page-curl animation is drawn). The other transitions (037, 039–041) and the world's
foreground layers (024, 027, 030, 033, 035) are not used.
