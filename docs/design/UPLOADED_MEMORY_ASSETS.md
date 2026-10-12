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

## Doddy moving, and outside the app (ADR-313, 11 October 2026)

Owner: "do all" (the lists proposed after ADR-308). Same Drive folder; originals not stored here.
`tools/whole_doddy/build_imagesets.py <pack> <cuts> <repo> <strips>` rebuilds these sets (the ADR-299
sets come out byte-identical). The strips are cut with `cut_frames.py --shared`: the paper below
the ground line (or the printed numbers) is painted paper first, only paper touching each frame's
edges is removed, and every frame of a strip goes on one canvas size with one ground, so nothing
jumps between frames. Nothing is redrawn or recoloured.

| Image set(s) | Pack file | SHA-256 of the original | What was done |
| --- | --- | --- | --- |
| `WholeDoddy_basketball_dribble` (app, widgets) | 01-transparent-poses/doddy_basketball_dribble_v02.png | 2e1d8f08f7c239a6fa68d77ba2f4d9163078f87fe051b86b34cdf3051ae13624 | Lanczos to 200×300 and 300×450 |
| `WholeDoddy_oneleg_balance` (app, widgets) | 01-transparent-poses/doddy_oneleg_balance_v02.png | 8aa54d224682cee586e06db0afc81304364f08dc48263675c5cd3d50154e58cc | as above (back after ADR-290 removed it as the greeting) |
| `DoddyMotion_walk_1` … `_8` | 012_doddy_walk_v01.png | dc5f4bfc2caaef3b2665bfa6c0f4bd66a47dbf858f68ac3be4c32454964802f8 | `cut_frames.py --shared --rows-max-y 567`; Lanczos to 200×300 / 300×450 |
| `DoddyMotion_run_1` … `_6` | 014_doddy_run_v01.png | 9b6b9dddcaada8b85156a75869c8d9fbb61f9aeff4c62501629cc30b0e137813 | `--shared --rows-max-y 568` |
| `DoddyMotion_jump_1` … `_5` | 015_doddy_jump_v01.png | 4904739cd7352b767d05c9edfc0a44966e6e632f198672922c5905ba0488df0b | `--shared --rows-max-y 596 --min-fraction 0.3` |
| `DoddyMotion_turn_3` | 018_doddy_turn_v01.png | abbcaf3b2f9be352bdf9b3e4accffd1b2121486ab83cd544342198be2018bed3 | `--shared --rows-max-y 605`; frame 3 only |
| `DoddyMotion_pop_1` … `_4` | 019_doddy_pop_v01.png | 2581da049ae7c3cf01ec2c1e814ae55543d3bc0b73779260e8ce32250265ee48 | `--shared --rows-max-y 640 --min-fraction 0` (the dot of frame 1 is too small to be a frame; frames 2–5 are used) |
| `DoddyMotion_idle_1` … `_4` | 013_doddy_idle_v01.png | 50877e133ccb35b542a14acdbe307c63ea6c2dadc5317d6ec3abee8acf606441 | `--shared --rows-max-y 760` |
| `Scenery_court` (day / night) | 025_world_court_day_v01.png / 026_world_court_night_v01.png | a9822a0398b7d9d3e76e28d781bc2533a2e919031fad9d0bbcb58db9274fca80 / 50409221750bea584d5c24fa305c5db961a97b9d81b9ed1617487d24c6fd539e | Lanczos to 780 px wide; JPEG |
| `Scenery_rooftop` (one picture) | 034_world_rooftop_night_v01.png | 59f377c8db058966f8e66889104876ad9600b22e4bc891c20b71b3aff072175e | as above; the pack has no day rooftop |
| `WidgetDoddy_face` (widgets) | 01-transparent-poses/doddy_listening_v02.png | 96375303e59d4b5f272805abb896a14ba3fcec37e8420a2dd04ec8b66823bc41 | the watch face's 470×470 crop, Lanczos to 120×120 and 180×180 |

The notification picture, the list share card and Siri's panel use image sets already listed above
(`WholeDoddy_reaching_high`, `_wave`, and the poses). Not used: the foreground layers (024, 027,
030, 033, 035), which sit below the part of each picture the strips show.

## Alarm, shopping, notifications, Settings and the watch app (ADR-323, 11 October 2026)

Owner: "do all except 8 and 9". Same pack; `build_imagesets.py` (with the strips folder) rebuilds these
too, and the earlier sets come out byte-identical.

| Image set(s) | Pack file | SHA-256 of the original | What was done |
| --- | --- | --- | --- |
| `DoddyMotion_sit_1` … `_5` | 017_doddy_sit_v01.png | 3dfd164d649d4ee62bb68a3578b3f483d773c540f14d00200f727918fd7d7ca6 | `cut_frames.py --shared --rows-max-y 582` (above the ground line); Lanczos to 200×300 / 300×450 |
| `DoddyMotion_turn_1`, `_2` | 018_doddy_turn_v01.png | abbcaf3b2f9be352bdf9b3e4accffd1b2121486ab83cd544342198be2018bed3 | as `_3` (ADR-313) |
| `WholeDoddy_sneaky_crouch` (app, widgets) | 01-transparent-poses/doddy_sneaky_crouch_v02.png | 06a0fa781670c90896309307a045ab658bcb78be22cd00443fe505cf755b55b3 | Lanczos to 200×300 and 300×450 |
| `WatchDoddy_crosslegged` (watch app) | 01-transparent-poses/doddy_crosslegged_v02.png | f9496932f6944096c626301c00cc49070ea4fc71cbbf6516d27807c12ca58db6 | Lanczos to 120×180 (@2x) |
| `WatchDoddy_fistpump` (watch app) | 01-transparent-poses/doddy_fistpump_v02.png | c7a1fd158652d6420c67ce51d2e60e6b4808392fc131c108c7e348acf80a0561 | as above |

The alarm, shopping and notification pictures use image sets already listed (`WholeDoddy_yawn_stretch`,
`_tiptoe`, `_crosslegged`, `_wave`). In the pack's sit strip Doddy sits on a cardboard box.

## Turned away, for hidden notes (ADR-331, 11 October 2026)

`WholeDoddy_turned_away` (app and widgets; 200×300 and 300×450) and `WatchDoddy_turned_away` (watch
app; 120×180 @2x) are frame 5 of `018_doddy_turn_v01.png` (SHA-256 above, ADR-313), cut by
`cut_frames.py --shared --rows-max-y 605` like the other turn frames and downscaled with Lanczos.
Nothing redrawn.

## The whole wave and four storyboards (ADR-380, 11 October 2026)

Owner: "do all". Same pack. `build_imagesets.py` (with the strips folder; see its docstring for the cut
commands) rebuilds these. Storyboard panels are cropped inside their borders only (the printed panel
number is cropped away); nothing is redrawn, recoloured or generated.

| Image set(s) | Pack file | SHA-256 of the original | What was done |
| --- | --- | --- | --- |
| `DoddyMotion_wave_1` … `_5` | 016_doddy_wave_v01.png | 817a2b87f220eb74c2006de13ec87b87b4114e358099d8ba69e5b15c2cdc98cd | `cut_frames.py --shared --rows-max-y 620` (above the frame numbers); Lanczos to 200×300 / 300×450 |
| `Story_phone_1` … `_4` | 037_trans_phone_v01.png | 66c2f0848383e18fd537530f78aa1ad146307dd4c462c0126934777e238149f0 | `cut_storyboards.py --trim-top 0.09`; resized to 420 wide, JPEG |
| `Story_door_1` … `_4` | 039_trans_door_v01.png | 357d5844abbb908ecf82255fe3e5474a5508b8ac7b9805efc545919aefcc8705 | `cut_storyboards.py --trim-top 0.09`; as above |
| `Story_ink_1` … `_4` | 040_trans_ink_v01.png | 4db68b4f02005ebcc76e330d9e740592b842fe14a982c553dceb27fb32782999 | `cut_storyboards.py` (numbers sit outside the panels); as above |
| `Story_keys_1` … `_6` | 041_rw_keys_storyboard_v01.png | 846b0999e562902dda957686b9459b4ca698226dced27c65515750d9ba32be50 | `cut_storyboards.py --trim-top 0.13 --trim-left 0.13 --sides tlltll` (panel numbers sit inside the corner; panels 2, 3, 5 and 6 are trimmed at the left so Doddy's head isn't cut); as above |

Not used: the five `*_fg_v01.png` foreground layers (024, 027, 030, 033, 035). They are not imported
(ADR-380 explains why), and the umbrella pose still waits on the owner's weather decision.

## App icon (ADR-460, 12 October 2026)

Owner: "pick [the] app icon" from the pack, for a first Xcode build on the owner's iPhone. This replaces the
note in the first section that the development app icon is not replaced: the v1.3 candidate (ADR-050) is
gone from `AppIcon.appiconset`.

Source: `DoddyApp/Resources/Assets.xcassets/UploadedDoddy_Listening.imageset/art.png`, byte-identical to the
pack's `doddy_listening_v02.png` (SHA-256 `96375303e59d4b5f272805abb896a14ba3fcec37e8420a2dd04ec8b66823bc41`,
table above). `tools/make_app_icon.py` checks that hash, then writes three 1024×1024 RGB PNGs with no alpha:

| File | What it is |
| --- | --- |
| `DoddyApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | source pixels (150, 120)–(910, 880), Lanczos to 1024, on paper `#F5EFE2` |
| `DoddyApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-dark.png` | source pixels (55, 25)–(1005, 975), Lanczos to 1024, clipped to a paper disc (64 px inset) on `#1D1C19` |
| `DoddyWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | the same file as the iPhone light icon |

Crop, scale and placement only: no line, colour or shape of the pose is changed, and nothing is generated.
Run `python3 -I tools/make_app_icon.py` again if the pose file changes. This records provenance, not a
commercial-rights or brand-master decision.
