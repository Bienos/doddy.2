# Doddy moves, and shows up outside the app (ADR-313) — status

Owner request, 11 October 2026: "do all" for the two lists proposed after ADR-308. Left out on
purpose: weather poses (umbrella) and alternate app icons, which need an owner decision (a weather
source and location; the app icon). Art: only the owner's pack; provenance in
`docs/design/UPLOADED_MEMORY_ASSETS.md`.

## What changed
**In the app**
1. Focus and breathing islands (Whole Doddy): dribbling and balancing on one leg; paused
   cross-legged; done fist pump (`DoddyToolAttributes.wholeDoddyPose`).
2. Focus screen: a court strip with Doddy dribbling, cross-legged when paused, fist pump when the
   time ran out, none when stopped early.
3. Weekly look-back: a rooftop strip with Doddy cross-legged.
4. Voice screen: walks while connecting, runs while a plan's steps run (`VoiceScreenArt.motion`).
   The island keeps the stretch while connecting: Live Activities can't play frames.
5. Save receipt: the pop strip once, then the existing fist pump. The receipt only exists after a
   confirmed save.
6. Lists: the jump once when the last open item is ticked while the list is on screen.
7. What Doddy did: the turned-back frame beside an undone entry.
8. Home: four idle breaths once per launch, only when the opening (ADR-225) doesn't play; it waits
   0.6 s so an opening about to start wins.
9. Empty states: Lists, What Doddy did and Tidy Up show Doddy cross-legged.

**Outside the app**
10. Lock Screen Talk to Doddy (circular): Doddy's face (`WidgetDoddy_face`).
11. "Doddy, resting" (`DoddyRestWidget`, small): for StandBy; the stretch pose and the next
    reminder's time only. Tinted Home Screens leave the drawing out.
12. Note reminders: the reaching pose as the notification's picture (`NotificationArt`). Same
    words; no picture with Hide Doddy's pictures or if the copy fails (the reminder is never held up).
13. Lists: "Share as a picture" (`ListShareCard`): the open items as on "Share as text", on cream,
    with Doddy waving (the pack has no pose holding a list). Rendered only when a share target asks.
14. Siri, "Ask Doddy what I saved": a snippet with the pose for the answer
    (`SiriNoteLookup.pose(forAnswer:)`). The spoken answer is unchanged.

**Not done:** scenery parallax. The pack's foreground layers sit in the lower part of each picture;
since ADR-308 the strips show the upper part, so nothing visible would move.

All motion is `DoddyMotion` (`Shared/IslandArt/IslandPose.swift`) drawn by `DoddyMotionView`: loops
loop, once-only strips rest on their last frame and stop their timeline; Reduce Motion shows one
still frame. Every picture is decorative, hidden from VoiceOver and by Hide Doddy's pictures.

## Verified (Linux, Swift 6.2.1)
- `scripts/check_island_art.sh`: PASS, with new checks for the focus and breathing poses, the
  voice-screen motions and the strip timing, and every new image set required. Planted bugs caught:
  connecting not walking, breathing not balancing, a missing strip frame, a missing widget pose.
- `scripts/ci.sh --core-only`: see the commit message for the run.
- `swiftc -parse` on every changed Swift file; Polish catalog and pack integrity checks.

## Not verified (needs a Mac, an iPhone and Siri)
Checklist 4i, Y1–Y12. Nothing here has been compiled for iOS: the SwiftUI views, `ImageRenderer`
for the share card, the App Intent snippet, notification attachments, Lock Screen and StandBy
rendering, frame rates and battery cost.

## Privacy and safety
No new data, permissions or network use. The StandBy widget and the Lock Screen show no note words.
A notification's picture adds no text. The share card holds exactly what "Share as text" sends, and
only when the user shares it.

## ADR-323 additions (owner: "do all except 8 and 9")
1. Alarm snooze (ADR-283): cream Lock Screen card with Doddy stretching awake; same pose on the island.
2. Shopping mode (ADR-257): Doddy on tiptoe on the island and the cream card.
3. Pictures on the morning check-in, evening wrap-up, weekly look-back and birthday notifications.
4. Home: after the breaths he sits down on his box (strip 017) and stays there that launch; an opening
   takes him off it, so the ADR-225 hand-over is unchanged.
5. Settings: the crouching pose beside the "Pause all connections" footer while paused.
6. Watch app: cross-legged on the "open Doddy on your iPhone" screen; fist pump on a confirmed save.
7. What Doddy did: the turn plays once for an entry undone while the screen is open.

Not built (need the owner's decision): weather (umbrella pose; a weather source and location) and
app icon choices (brand). Known gap: widgets, Live Activities and the watch don't read Hide Doddy's
pictures. Checklist 4j, Z1–Z7. Not compiled for iOS or watchOS.
