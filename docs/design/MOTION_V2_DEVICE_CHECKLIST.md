# Motion v2: checks only a device can do

MV6 (19 Oct 2026). What the simulator and Linux can't show about the one persistent Doddy
(docs/design/MOTION_V2_PLAN.md section 6, "Device"). None of this has been run: no device was
available to the agent, and the hosted Mac build has no screen recording. Each line says what
to look for and where it is decided in code, so a failure points at a file.

Build: `make project-iphone`, scheme `Doddy`, a Debug build on a ProMotion iPhone (13 Pro or
later). For the annotated mode add `-doddyMotionDebug YES` to the scheme's arguments: it draws
his surfaces, his clear zone, a frame counter, the flights count and the DEBUG checks' count
(top of the screen; the count should stay 0).

| # | Check | Look for | Decided in |
|---|---|---|---|
| D1 | 120 Hz while he moves | The debug frame counter rises about 120 a second during a hop; it stops when he is still (stillness is the default: no display link) | `DoddyClock.swift` (80–120 Hz range), `CADisableMinimumFrameDurationOnPhone` in `Config/Doddy-Info.plist` |
| D2 | Hand-off alignment at 120 Hz | Tap a tab: he crouches where he stood, flies, lands. No jump of a point or two when the flight starts (slot → overlay) or ends (overlay → slot), no frame with two of him or none | `DoddyDirector.publish`, `MotionHost.placement`, `DoddySlotFigure`, `DoddyOverlay` |
| D3 | Riding Home's scroll | Scroll Home: he moves with the stage line exactly, at 120 Hz, no lag or float | Option B (he is drawn inside the stage's slot) |
| D4 | Riding the Memories list | With 6+ notes, scroll slowly: he rides his card, then one lily-pad hop to a card coming up; fling: he waits on the rail, then one hop back when it settles. iOS 17 device: any scroll sends him to the rail (Q10) | `MotionRiding.swift`, `DoddyScrollReporter` |
| D5 | Ask's composer and the keyboard | Open Ask: he comes up with the cover on the composer, left of Send; tap the field: he rides up with the keyboard with no gap under his feet; close: he is on Home's stage | `MotionHost.talkOpened/talkClosing`, `AskView` |
| D6 | Keyboard interactive dismissal | Ask doesn't use interactive dismissal today; if it is added, drag the keyboard down slowly: he follows the composer frame by frame | Option B; nothing to change unless it lags |
| D7 | The undo bar | Delete a note while he waits on the rail (tap tabs quickly first): the bar appears under him and lifts him; when it times out he is set down on the rail | `MotionHost.panelChanged` |
| D8 | A note's page | On Memories, open the card he stands on: the page covers him where he is; swipe back slowly: he is uncovered with the list, never drawn over the page | `DoddyDirector.pageChanged`, `MotionEngine.pagePushed` |
| D9 | Touch on him | Tap him on Home: the voice screen opens. Touch and hold: nothing until you let go, then the voice screen. Drag sideways: he leans; flick up: one hop in place | `DoddyTouchArea`, `MotionBehaviours.swift` |
| D10 | Haptics | None are played by the motion code (none were built). If the brief's touch or landing haptics are added later, feel them here | — |
| D11 | Reduce Motion (Settings › Accessibility › Motion) | Every move is a fade at the new spot; never a flight; no breaths, no playful moment, no dip | `MotionEngine.startFade`, `RootView` (`setReduceMotion`) |
| D12 | VoiceOver | Swipe through Home, Memories and Settings: nothing reads Doddy; "Talk to Doddy" is there. His touch area is skipped | `DoddyFigureView` (accessibilityHidden), `DoddyTouchArea` |
| D13 | "Hide Doddy's pictures" (Settings) | No Doddy anywhere, no stage line, no gap where he stood, cards full width again | `RootView.motionWorldOn`, each screen's `isActive` branch |
| D14 | Low Power Mode | No breaths; the debug frame counter stays still while he stands | `DoddyClock` (`setLowPower`) |
| D15 | Accessibility text sizes | Largest size: 1.0× on Home (Q12); the note page has no spot for him (he stays covered on the list) | `RootView` (`setHomeScale`), `MemoryDetailView` |
| D16 | Dark appearance | His outline has the island's thin cream edge on dark backgrounds | `DoddyFigureView` (`islandCreamEdge`) |
| D17 | 1.4× softness | On Home, at 1.4×, is the picture visibly soft? (the exports are 300 × 450 px, Q11) | `docs/design/MOTION_V2_ART_REQUESTS.md` |
| D18 | The journey with the debug overlay | Home → Memories → a note → back → scroll → Settings → Home → Ask → type → close, then a quick run of tab taps: checks stay 0 | `MotionChecks.swift` |
| D19 | Battery | Leave Home open 10 minutes: the frame counter barely moves after the first minute (breaths, the sit, the playful moment, then still) | `MotionEngine.isStill`, `nextDue` |
| D20 | Gaze (MV7, ADR-560) | On Home, put a finger down away from him (and drag it): his eyes follow it, one of eight looks, level, and come back to you 300 ms after the finger lifts. They are small (2 to 3 pt at normal size, 3 to 4 pt on Home); is that readable, or too subtle? | `MotionFace`, `MotionEngine.gazeVector` |
| D21 | Blink and squint | Put a finger on him: eyes half closed while it is down. Stroke his head slowly: eyes close, open after. After 21:00 (set the clock, delete `home.lastWaveDay`): one slow blink during the welcome wave. No blink at any other time while he stands still. | `MotionFace.choose`, `MotionEngine.homeTouchDown`, `startRub` |
| D22 | The seam | Look at his face from 20 cm at 1.4× on Home with the eyes looking away and when they blink: is any lighter patch or ring visible around where his own eye was? Do the two eyes stay level and the same size as his own eyes? Also in dark appearance | `MotionFace.layers` (`coverPad`, `coverBlur`), `build_face_pieces.py` |
| D23 | Where eyes are not drawn | During a hop (the hop strip), while listening, while thinking in Ask and in the stretch his eyes stay as the picture drew them; none of these should show a patch or a double eye | `MotionFace.fits` has only front-facing pictures |
| D24 | Back from the background, and rotation | On Home, go to the Home Screen, open the App Switcher (also once with the phone held sideways), wait 10 s and open Doddy again: he is in the middle of the stage, under "I'm here.", and doesn't hop. Then turn the phone sideways and back on Home: he stays in the middle each way. With `-doddyMotionDebug YES` the trail shows no "clear zone" hop. Before the fix (owner, 20 Oct) he came back with a hop to about 36 pt right of the middle | `MotionHost.surfaceMoved`, `MotionEngine.surfaceShifted`, `MotionLayout.carriedX` |

## Hallway test: his size on Home (1.3×, 1.4×, 1.5×)

Not required before merge: on 20 Oct the owner said "ok for home", read as keeping 1.4× (the brief's size). Keep this script for if anyone questions the size, or D17 finds the picture too soft.

Plan section 6, MV6: five people, one at a time, about five minutes each. Nobody is told what is
being tested.

1. Build three Debug builds, identical except `MotionHost`'s `scene.homeScale` default and
   `RootView`'s `setHomeScale` value: 1.3, 1.4 (the brief's), 1.5. Label them A, B, C in a random
   order per person, written down before you start.
2. Give the phone on Home. Say: "This is an app with a little character in it. Use it for a
   minute: look around the tabs and come back."
3. After a minute, on Home, ask: "Did anything on this screen feel too big, too small, or in the
   way?" Write the answer word for word.
4. Show the other two builds on Home, 20 seconds each, and ask: "Which of the three feels most
   right for him?" Then: "Did any of them cover something you wanted to read?"
5. Record, per person: build order, first-minute answer, the pick, anything covered.

Decide only on agreement: if four of five pick the same size, take it; otherwise keep 1.4× (the
brief). Note whether anyone mentioned the picture looking soft (Q11).
