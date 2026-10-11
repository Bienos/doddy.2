# Whole Doddy island style (ADR-264)
Date: 2026-10-11. Owner: "suggest more tailored designs … with his whole body", "only use assets from these
folders", "make them transparent not white colour on black", "deploy it". The design canvas the owner reviewed
is a private Artifact in the owner's account.

**Built on Linux only. The iOS app has not been compiled or run with this change.**

## What ships
- Settings → Voice → Dynamic Island style gains **Whole Doddy**, next to the V4 styles. Since ADR-267 it is the
  default and listed first; a style the user already picked is kept.
- With it chosen, the expanded voice island draws Doddy's whole body from the owner's pose pack, one pose per state:

| State | Pose |
|---|---|
| Connecting | Stretch (getting ready) |
| Listening | Hand at his ear |
| Thinking | Kneeling, hand on chin |
| Speaking | Open hands |
| Muted | Finger to his lips |
| Lost (stale) | Hand on his head |
| Hey Doddy waiting / paused | Cross-legged / leaning on his box |
| Hey Doddy greeting | A wave (ADR-290, cut from the pack's wave strip) |
| "Save this note?", a reminder waiting or being added | Reaching high |
| Saved, reminder set, ended | Fist pump (only after the store or Reminders confirmed it) |
| A plan waiting or running | Tiptoe |
| Translating | Language Bridge, as in every style |

- Compact and minimal show a round face cropped from the same pictures: listening while live, shush when muted,
  eyes closed (from the stretch) while Hey Doddy waits or is paused, otherwise the cross-legged smile.
- The island stays black: iOS draws it and apps can't change it. The black outlines get a 1 pt cream edge; there is
  no panel. Orange still means "Doddy can hear you" (LIVE, the bars, the keyline).
- Unchanged here: the V4 styles and the focus and breathing islands. Since ADR-299 the Lock Screen card and the
  read-aloud island use the poses too (`DODDY_WORLD_IN_APP_STATUS.md`).

## Files
- `Shared/IslandArt/IslandPose.swift`: the poses, their figure boxes, the face poses and head positions.
- `Shared/IslandArt/IslandScene.swift`: `IslandStyle.wholeDoddy`, `IslandScene.pose`, `ContentState.wholeDoddyPose`.
- `Shared/IslandArt/IslandViews.swift`: `IslandPoseView`, `IslandPoseFaceView`, `islandCreamEdge`; the expanded,
  compact and minimal views use them when the scene has a pose.
- `DoddyApp/Resources/Assets.xcassets`, `DoddyWidgets/Assets.xcassets`: 12 `WholeDoddy_*` image sets.
  Provenance and hashes in `docs/design/UPLOADED_MEMORY_ASSETS.md`.
- `DoddyApp/Features/Settings/IslandStyleView.swift`: the footnote.
- Checks: `tools/island_boards/IslandSceneChecks.swift` (`wholeDoddy()`), `IslandArtCheck.swift`
  (`--pose-assets`), `scripts/check_island_art.sh` (every picture in both catalogs).

## Verified (Linux, Swift 6.2.1)
- `scripts/check_island_art.sh`: PASS, including the Whole Doddy checks. Planted bugs caught: a wrong pose for
  speaking, and a missing picture in the widget catalog.
- `scripts/ci.sh --core-only`: see the commit message for the run.
- Every changed Swift file parses.

## Not verified (needs a Mac and an iPhone)
Checklist W1–W6: that it compiles (SwiftUI `Image` from the widget's catalog, the shadows), how the poses read at
island size, the cream edge, the face crops, and memory use in the widget extension.

## Decisions for the owner
- ~~Whether Whole Doddy should become the default style~~: yes (owner, 2026-10-11, ADR-267).
- ~~A cut-out wave for the greeting~~: done (owner: "use the wave pose for the greeting", ADR-290).
