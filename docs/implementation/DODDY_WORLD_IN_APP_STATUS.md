# Doddy's world in the app (ADR-299) — status

Owner request, 11 October 2026: "Do all" — the eight additions proposed after the greeting wave
(ADR-290). Art: only the owner's `DODDY-Numbered-Video-Assets-v01` pack (CLAUDE.md, "Character art");
provenance, hashes and the exact cuts in `docs/design/UPLOADED_MEMORY_ASSETS.md`.

## What changed
1. **Lock Screen card** (`DoddyWidgets/DoddyVoiceLiveActivity.swift`, `DoddyArt`): the island's Whole Doddy
   pose for the same moment, whatever island style is picked. At the end: fist pump only if a note was
   saved, else cross-legged. No cream edge on the cream card.
2. **Read-aloud island** (`IslandPose.bellyReading`, `DoddyToolAttributes.ContentState.islandStyle`,
   `ToolLiveActivity.styled`): with Whole Doddy, reading → lying on his front with a book, paused →
   cross-legged, finished → fist pump, lost → facepalm. Focus and breathing keep their boards. The style is
   read from Settings each time the state is sent; content from older builds (no style) decodes and shows
   the board.
3. **Empty and error screens**: Find's "no match" → shrug. `ProblemView(showsDoddy: true)` (facepalm) on a
   failed save, and on Home, Memories and Find when notes can't load. `CandidateCharacterView`:
   `Doddy_waving` → wave, `Doddy_approaching` → tiptoe (Back Tap setup, note-reminder sheet).
   New `WholeDoddyView(pose:height:)`: a pose cropped to the figure, cream edge in dark mode.
4. **Scenery** (`SceneryBackdrop`): room on Home, memory library on Memories, coffee shop on the morning
   check-in; day pictures in light mode, night in dark. 40 % opacity, fading out by the bottom, scrolls with
   the page.
5. **Voice screen** (`VoiceDoddyView`, `VoiceScreenArt`): the island's pose for the phase (connecting
   stretch, listening, thinking kneeling, muted or no microphone shush, a card waiting reach, ended fist
   pump, failed facepalm). While speaking, the six frames of strip 020 loop at 0.18 s each in a
   `TimelineView`. They follow the conversation's "speaking" state only; they are **not lip-synced** to the
   audio. Reduce Motion: frame 1, still; poses swap without a fade.
6. **Home Screen widgets** (`WidgetPose`): Talk to Doddy (small) shows the wave instead of the waveform;
   Next reminder (small) shows the reach beside the time. Full-colour rendering only.
7. **Watch complications** (`WatchDoddyFace`, new `DoddyWatchWidgets/Assets.xcassets`): a round crop of the
   listening pose's face in the circular complication when nothing is coming up, and beside "Doddy" in the
   rectangular one. Full-colour faces, and tinted faces on watchOS 11+ (`widgetAccentedRenderingMode`).
8. **Storybook** (`StorybookView` on the welcome of `IntroductionView`): the four panels of 038 cross-fade
   once (1.1 s each) and stay on Doddy waving; not replayed when going back to the welcome. Reduce Motion:
   the last panel only. The ADR-225 opening is untouched.

Every picture is decorative (hidden from VoiceOver) and, in the app, hidden by "Hide Doddy's pictures".

## Files
- Art tools: `tools/whole_doddy/cut_frames.py`, `cut_panels.py`, `build_imagesets.py`.
- Image sets: `WholeDoddy_belly_reading` (app, widgets), `VoiceDoddy_talking_1…6`, `Storybook_page_1…4`,
  `Scenery_home|memory|coffee` (app), `WatchDoddy_face` (watch widgets).
- Code: `Shared/IslandArt/IslandPose.swift`, `IslandScene.swift`, `IslandViews.swift` (`IslandFigureView`),
  `Shared/ToolActivity/DoddyToolAttributes.swift`, `DoddyApp/Features/Tools/ToolLiveActivity.swift`,
  `DoddyApp/DesignSystem/Components.swift`, `MemoryJourneyComponents.swift`, `Features/Voice/VoiceDoddyView.swift`,
  `VoiceView.swift`, `Features/Onboarding/StorybookView.swift`, `IntroductionView.swift`, Home, Memories,
  Find, Capture, morning check-in, `DoddyWidgets/DoddyVoiceLiveActivity.swift`, `HomeWidgets.swift`,
  `DoddyWatchWidgets/DoddyWatchComplications.swift`.
- Checks: `IslandSceneChecks.voiceScreen()` and the read-aloud cases in `tools()`; `check_island_art.sh` now
  also requires the talking frames.

## Verified (Linux, Swift 6.2.1)
- `scripts/check_island_art.sh`: PASS. Planted bugs caught: reading shown as listening, a waiting card not
  shown as the reach, a missing widget picture, a missing talking frame.
- `scripts/ci.sh --core-only`: see the commit message for the run.
- Every changed Swift file parses (`swiftc -parse`).

## Not verified (needs a Mac, an iPhone and a watch)
Checklist 4h, X1–X8. Nothing here has been compiled for iOS or watchOS: the SwiftUI views, the asset
catalogs (JPEG image sets with a dark appearance, the new watch catalog), widget rendering modes, the
`TimelineView` frame rate and its battery cost, and how the scenery reads behind text.

## Privacy and safety
No new data, permissions or network use. The Lock Screen and watch still show no note words. The
read-aloud state carries only the island style name.

## Decisions for the owner
- Whether the scenery should be stronger or weaker than 40 % (X4).
- Whether the talking frames should be faster or slower than 0.18 s per frame (X5).
