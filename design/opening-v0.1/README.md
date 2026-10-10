# The opening: design preview v0.1

Date: 10 Oct 2026. Status: **design study of a built timeline.** The app's opening (ADR-207, `docs/implementation/OPENING_SCENE_STATUS.md`) is SwiftUI; this page redraws the same timeline in a browser so the cartoon can be looked at before a Mac build.

Open `index.html` in a browser. It is self-contained except for the listening artwork, which it loads from `DoddyApp/Resources/Assets.xcassets/UploadedDoddy_Listening.imageset/art.png` (some browsers block that for `file://` pages; serve the repository root with any static server if the ready pose is missing). The four basketball SVGs from `design/interface-v1.2/assets/` are inlined. No fonts are bundled.

## What it shows
A pen sketches Doddy in, he dribbles, crouches, hops and shoots, the ball flies with a ghost trail, SWISH! with confetti, he pops up ready to talk, then jumps into his exact place on Home while it fades in and the buttons slide in. Tap the phone to skip to the hand-over; after it, the buttons answer taps with a note on what they open in the app. Review switches: quarter speed, Reduce Motion, dark. `?t=1.2` freezes the scene at that second; `?home=1` shows Home after the opening (for comparing the last frame with Home).

The constants are copied one for one from `Packages/DoddyCore/Sources/DoddyCore/OpeningScene.swift`. The Swift is the source of truth and the one that is tested; change this page with it.

## What it does not prove
It is not the app: the Home is a placeholder and nothing listens or talks. SwiftUI's path trimming, the haptic, Dynamic Type and compositing still need the Mac build.
