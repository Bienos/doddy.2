# Motion v2 in the iPhone app: what it takes

Investigation written 18 October 2026; the status below is 20 October. The sections after it are the plan as written, before the build.

**Source of the motion world:** the `design/motion-v2/` handoff (README, BRIEF, DECISIONS, `reference/` engine and prototype, `telemetry/`). Committed with MV1 (owner answer to Q1, 18 Oct 2026): MV1's golden tests read its telemetry.

## Status (20 Oct 2026)

- **Owner answers:** Q1 commit the handoff folder (done); Q7 whole-picture transforms of pack art are allowed (move, scale, rotate, squash), never redrawn, recoloured, cut up or generated; Q9 add `CADisableMinimumFrameDurationOnPhone` in MV2. Every other question took this plan's recommendation; on 20 Oct the owner confirmed the recommendations for Q2, Q3, Q4, Q8, Q10, Q13, Q14, Q15 and Q16 ("Confirm and ok for home") and Home stays at 1.4x (the agent's reading of "ok for home"). Still open: Q6 (blink and eye sheets) and Q11 (larger exports).
- **Built, on stacked branches, not merged:** MV1 `claude/motion-mv1` (engine in DoddyCore, golden tests against all 25 telemetry clips), MV2 surfaces and look, MV3 one Doddy hopping, MV4 riding, MV5 behaviours, MV6 evidence. ADR-545 and ADR-546 in `DECISIONS.md`.
- **Evidence:** hosted macOS (`scripts/ci.sh`) is green on every branch; on MV6 head `85f11836` DoddyCore ran 1239 tests, the app 43, the UI tests 50 (1 skipped), 0 failures, 21 of the UI tests on the motion world.
- **Not run:** anything on a device (80 to 120 Hz, the keyboard, haptics, the system's Reduce Motion and VoiceOver) and any screen recording: `MOTION_V2_DEVICE_CHECKLIST.md`.
- **MV7 (20 Oct, on `claude/motion-mv7`, on top of MV6, not in #107):** the owner said "Make blink and gaze" (Q6). Eyes cut from the pack sheets 007 and 008 are drawn on the front-facing pictures (ADR-547). Not on the three-quarter heads, the kneeling pose or the stretch.

## In short

- **The brief describes an app this repo doesn't have.** It assumes tabs Home / Talk / Memories, a message composer that rides the keyboard, a draft-review strip that rises into a panel, rules between Memories rows and Apple's message composer. This app has Home / Memories / Settings in a custom tab bar, voice as a full-screen cover, typed questions (Ask) as another cover, Memories as rounded cards, and message drafts that leave the app through an `sms:` link. About half the spot table maps cleanly; the rest needs owner decisions (section 7), not navigation changes made by an agent.
- **The palette is already there.** The brief's five colours are within ΔE 1.3 of the current `UploadedColorRole` light values, with the same rust. No token change is needed for the look; dark mode needs the existing cream edge on Doddy's outline.
- **Art is the hard limit.** The owner's pack (as imported) carries the hop (crouch, take-off, peak, landing, recovery), breathing, sitting cross-legged, listening, thinking (kneeling), the wave and talking. It has no independent pupils, blink, squint, head roll, brief-style pointing, brace, shuffle steps or a clean edge-sit. Rule 3 (eyes first) and every gaze-only "noticing" reaction can't be honoured until that art exists. The pack's numbering suggests a blink sheet (007) and an eye-direction sheet (008) may exist unimported; that has to be checked by the owner (Q6).
- **One Doddy needs the existing pictures to change.** Doddy is drawn on at least 20 screens and states today (Home's art box, empty Memories, Settings, problem views, Find, lists, Activity, capture receipt, check-in, voice screen, opening, onboarding, Face ID door). Rule 1 means each becomes the persistent Doddy, stays as a full-screen story that covers him, or is retired (Q4).
- **Recommended architecture:** render him **attached to the surface he stands on** while resting and riding (so scrolls, keyboard, pushes and sheets carry or cover him in the same frame, at 120 Hz, for free), and move him to **one root-level overlay only for crouch-on-a-vanished-surface, flights and fades**. One `@Observable` director owns which of the two draws him in any frame; a pure-Swift engine in DoddyCore decides everything else. A pure global overlay synced to surface frames every frame is the fallback, not the plan (section 4).
- **Milestones:** MV1 (engine in DoddyCore, Linux tests against the telemetry) can start as soon as the questions are answered. Everything after it needs Xcode, and riding, 120 Hz and the keyboard need a device.

## Repository reality

| Thing the brief needs | State in this repo |
|---|---|
| One persistent Doddy across screens | **Missing.** Each screen draws its own picture (`WholeDoddyView`, `UploadedCharacterView`, `DoddyMotionView`, `VoiceDoddyView`, `CandidateCharacterView`). The opening's hand-over to Home's art box (`OpeningSceneView` + `OpeningModel.homeArtBox`, ADR-225) is the only place one Doddy becomes another, and it is the pattern to reuse. |
| Doddy moving | **Partial.** Frame strips from the pack play in place (ADR-313/323/380): idle breaths and the box sit on Home, wave, pop, jump, turn, walk and run on the voice screen. No travel between places, no physics. |
| Motion engine | **Missing** in Swift. The reference engine is JavaScript (`design/motion-v2/reference/engine.js`), deterministic and time-based. |
| Surfaces with measurable edges | **Partial.** Home's art box frame is already measured (`onGeometryChange`, `HomeView.swift` line 99). Nothing else reports its frame. |
| Tests | DoddyCore runs on Linux (934 tests, per STATUS). App code needs Xcode. This container has **no Swift toolchain**, so nothing Swift was run for this plan. |

## 1. Surface map

How to read a surface's frame every frame, in this app's terms:

- **Attached** (recommended, section 4): Doddy is drawn inside the surface's own view, so the render server moves him with it. No per-frame read is needed to ride; the frame is read only to plan flights, with `onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }` (already used on Home).
- **Layout frame:** `onGeometryChange` reports the frame after each layout pass. Inside a `ScrollView` this updates as it scrolls. During UIKit-driven animations (keyboard, navigation push, sheet presentation) it reports the end value, not the in-flight one.
- **In-flight frame:** a 1 × 1 `UIView` probe (`UIViewRepresentable`) inside the surface, read each `CADisplayLink` tick through `layer.presentation()`, converted to the window's presentation layer. Needed only to aim a flight at a surface that a system animation is moving.

### The spot table

| Brief spot (BRIEF.md "His spot on every screen") | Brief position | This app: file, view | Frame | Fit |
|---|---|---|---|---|
| Home: centre of the stage line, 1.4× | x 195, y 470, line 140 wide | `Features/Home/HomeView.swift` lines 81–121: the 210 pt art `Group` inside Home's `ScrollView`, with `SceneryBackdrop(.home)` behind it. There is **no stage line**; the art sits in a box. | Attached slot under the art; global frame from the existing `onGeometryChange` (line 99). | **Partial.** Home scrolls, so the stage is a moving surface (he rides Home's scroll). The heading is above him, not below; the copy "I'm here." / "Tap Doddy to talk" doesn't exist (the brief calls it placeholder). Tapping the picture does nothing today; "Talk to Doddy" is the primary button 24 pt below (lines 133–139). |
| Talk: composer top edge, left of Send; fallback the rail | x 250, centre ≤ 284 | **No Talk tab.** Two candidates: (a) the voice screen, `Features/Voice/VoiceView.swift` (full-screen cover from `RootView.swift` line 302), whose bottom `controls(_:)` bar (lines 1338–1349) holds Mute/End or Talk again, not a text field; (b) Ask, `Features/Ask/AskView.swift` (full-screen cover from Home, `HomeView.swift` line 235), whose `composer` (lines 193–212) is a text field with a Send button. | (a) would need a slot in `VoiceView`; (b) attached slot in Ask's composer. | **Mismatch** (see "Talk" below). |
| Talk, keyboard up: same spot, riding the composer | follows the keyboard | Only Ask's composer rides the keyboard (SwiftUI keyboard avoidance). The voice screen has no keyboard. | Attached: free. For aiming: `keyboardWillChangeFrameNotification` (end frame, duration, curve) or `UIKeyboardLayoutGuide`. | **Only in Ask.** |
| Draft review open: panel top edge, right of the grabber | x 250, y 380 | **None.** The nearest things: a voice action card waiting for a tap (`VoiceSessionController.PendingAction`, e.g. `.message(...)`, drawn by `actionCard` in `VoiceView.swift` line 198), the capture sheet for a shared-text draft (`RootView.swift` line 325) and Home's "Unfinished note" card. | — | **Mismatch.** |
| Memories, no draft: first fully visible rule, right end; fallback next rule, then the rail | x 330 | `Features/Memories/MemoriesView.swift` lines 84–109: a `LazyVStack(spacing: 12)` of `MemoryLinkCard` (`DesignSystem/MemoryJourneyComponents.swift` 214–252), rounded cards whose text runs the full width. **No rules**, and the list starts low (wordmark, heading, scenery strip, Find button, Notes/Lists picker, filters come first). | Attached slot per card (the card scrolls him); velocity and phase from `onScrollGeometryChange` / `onScrollPhaseChange` (iOS 18+). | **Partial.** The brief allows "card tops", but standing on a card's top edge puts his 48 × 108 pt clear zone over the card above, whose text and pin/arrow icons reach x 348. |
| Memories, draft waiting: strip top edge before "Review ›" | x 250, y 652 | **No strip.** The only bar above the tab bar is `UndoDeleteBar` (`RootView.swift` 428–467), shown for a few seconds after a delete. | Attached to the bar. | **Mismatch**, with one partial analogue. |
| Memories detail page: the source block's top rule | x 330 | `Features/Memories/MemoryDetailView.swift`, pushed in Memories' `NavigationStack` (and in Home's, from recent notes and widgets). The source block is inside `MemoryPaperCard` (`MemoryJourneyComponents.swift` 191–212): the 1 pt rule (line 201) sits **under the note's own text**, between it and the source and date lines. | Attached slot in the card. | **Partial.** Standing on that rule puts his clear zone over the note's words. The card's top edge, right end, is clear at default text sizes: the heading above it ("The original is right here.") is left-aligned and about 200 pt wide. |
| Empty Memories: the empty-state heading's baseline, centred; fallback the wordmark perch | centred | `EmptyMemoriesView` (`MemoriesView.swift` 248–262): `UploadedDoddy_Sitting` at 150 pt above "No memories yet" and a Save button. | Attached slot where the picture is. | **Fits**, once the picture becomes him. The wordmark perch needs a cap height of 64 pt; `DoddyWordmark` is `.title` (about 28 pt), so there is no perch. |
| Rapid tab switching: the rail under the selected tab; fallback the strip | y 724 | `DoddyTabBar` (`MemoryJourneyComponents.swift` 254–287): a capsule with three equal buttons, 24 pt side insets, below the `TabView` in a `VStack` (`RootView.swift` 409). The rail is the capsule's flat top edge (about x 54–336). | Layout frame (static), or an attached slot on the bar. | **Fits.** |
| (Not in the brief) Settings | — | `Features/Settings/SettingsView.swift` line 72: a `Form`; its first section shows `UploadedDoddy_Privacy` at 110 pt beside a line of text. | Attached slot in that row, or the rail. | **No spot defined.** |

### The other surfaces the brief names

| Surface | This app | How it behaves |
|---|---|---|
| Stage line | To be added under Home's art (MV2). Uses `Theme.separator` (the brief's rule colour). | Rides Home's scroll. |
| Composer | Ask's `composer` only (unless Talk means the voice screen; Q2). | Rides the keyboard via SwiftUI's keyboard safe area. Ask doesn't use interactive keyboard dismissal today; Capture and Find do (`scrollDismissesKeyboard(.interactively)`). |
| Draft strip and panel | None (Q3). | — |
| List rules | None; cards instead (Q5). | — |
| Source rule | `MemoryPaperCard`'s rule, or its top edge (above). | Covered and uncovered by the real push and pop, including the interactive swipe back, if he is attached on the Memories list. |
| Rail | `DoddyTabBar`'s capsule top. | Static. When `UndoDeleteBar` is showing, the bar above the rail is a moving surface he rides up and down. |
| Sheets | Many app sheets and covers: capture, focus, breathe, tidy-up, wrap-up, look-back, check-in, translator start, data flow, Back Tap setup, the voice cover, Ask, onboarding, the Face ID cover. Two use `.medium` detents (`VoiceView.swift` 94, `ConnectionsView.swift` 49). | They cover him. They are presented above the root view, so an overlay inside `RootView` stays under them by itself. He never rides an app sheet (the brief rides only the draft panel). |
| Keyboard | System keyboard window. | Covers him (layer 1). |
| Apple's message composer | **Not used.** Message drafts open Messages through `OpenLinks.text` (`sms:` URL, `Packages/DoddyCore/Sources/DoddyCore/VoiceTools.swift` 523–545); the app learns nothing back. | Rule 10's "sent" cue can never fire, which is honest by omission. A pleased "sent" reaction would need `MFMessageComposeViewController` (Q8). |

### Each mismatch: options and recommendation

**Talk.** (a) The voice screen is Talk, since a tap on Doddy should talk and Home's tap target opens voice. (b) Ask is Talk, since it is the only composer that rides the keyboard and has a real "thinking" wait. (c) A new Talk tab. **Recommendation:** (a) for the tap and press-and-hold, but leave the voice screen outside the motion world in the first milestones: the persistent Doddy is hidden in the frame the cover starts, and `VoiceDoddyView` stays the voice screen's Doddy. Use (b) as the composer surface for the keyboard behaviours (riding, shuffle, thinking). (c) is a navigation change for the owner only. Bringing `VoiceDoddyView` under the engine later touches `VoiceView.swift` (UI only, not the session) and needs explicit approval.

**Draft review strip and panel.** (a) Leave them out; studies 09, N7, N10 and N13 then have no place in the app. (b) Map "introduce the draft" to the voice screen's pending-action card (he points at the card that waits for your tap), later, with the voice screen. (c) Treat `UndoDeleteBar` as the "strip if showing" for the rail and step-across. (d) Build a real draft strip, a product change. **Recommendation:** (a) now, (c) for the rail, (b) when the voice screen joins. Not (d) without a product decision.

**Memories rows.** (a) Keep the cards and stand on a card's top edge: the clear zone overlaps the card above. (b) Keep the cards but reserve a 66 pt right gutter for him (text column ending at x 288, as in the brief's mock). (c) Ruled rows like the brief, with a 108 pt bottom inset. **Recommendation:** (b). It keeps the owner-approved memory-journey look (10 Oct) and meets the clear zone; (c) changes an approved design.

**Detail page.** **Recommendation:** stand on `MemoryPaperCard`'s top edge at its right end, not on the rule under the note's words. At accessibility text sizes, where the heading reaches his zone, he stays on the Memories list underneath (covered) instead of arriving on the page.

**Settings.** (a) The rail under Settings. (b) The spot where the Privacy picture is now. (c) Hidden on Settings. **Recommendation:** (b). It replaces a picture of him with him and needs no new edge.

**Empty Memories.** **Recommendation:** his spot replaces the sitting picture: cross-legged on a short line where the picture is, looking at the Save button. No wordmark perch.

## 2. Look

| Brief | Current token (`DoddyDesignTokens/UploadedTokens.swift`, light / dark) | Difference |
|---|---|---|
| Cream background #F3EDDF | `canvas` #F5EFE2 / #1D1C19 | ΔE 0.89: not visible |
| Surfaces #EDE4D7 | `quietSurface` #EEE7D9 / #292720 | ΔE 1.25 |
| Rules #D6D0C2 | `separator` #D8D1C3 / #49453D | ΔE 0.57 |
| Ink #0B0B0B | `readingInk` #080808 / #F5EFE2 | ΔE 0.83 |
| Rust #A64B19 | `accentText` #A64B19 / #EC9A68 | Same |
| Head fill #FCF8EF | in the art itself | — |

Contrast with the brief's values: ink on cream 16.9:1, rust on cream 4.94 and on the surface 4.58, muted text #6B655B on the surface 4.59. The current tokens score a little higher (rust on `quietSurface` 4.69), and both pass the 4.5 that `UploadedTokensTests` enforces.

- **What changes:** nothing in the tokens. Keep `UploadedColorRole`. The stage line, card edges and rail use `separator`; the 1.4× Home size and the clear zones are layout, not colour.
- **What conflicts:**
  - Layout, not colour. Home is a long scrolling page with the greeting above Doddy and the buttons below; the brief's Home is a fixed stage with the heading under it. Memories has cards, not rules (section 1).
  - `CANONICAL_DESIGN_DIRECTION.md` still quotes the older Pocket Notebook values (#FFF7E9 / #171715 / #F58A24). The 10 Oct memory-journey selection superseded them for these screens, and the brief agrees with the newer palette.
  - The brief says "match doddy.lol"; the app keeps system fonts and Dynamic Type (CLAUDE.md), which is right.
- **Dark mode:** the brief has no dark palette. Keep the app's dark values. Doddy's black outline on the dark canvas is 1.16:1, invisible, so the moving Doddy must use the existing thin cream edge (`IslandFigureView(edged: true)`, as `WholeDoddyView` and `DoddyMotionView` already do in dark). Not the paper card behind `UploadedCharacterView`, which would read as a sticker sliding around. The stage line and rail use the dark `separator` (1.79:1 on the dark canvas, the same as other hairlines).
- **Scenery:** `SceneryBackdrop(.home)` is behind Doddy's box at 25 % (ADR-308). It can stay under the stage line; nothing in the brief conflicts.
- **Accessibility text sizes:** the app caps character art at 100 pt there (`textSize.isAccessibilitySize`). The brief's 134 pt Home size would ignore that cap (Q12).

## 3. Art

Rule for this section: only the owner's pack. The reference's stick-figure rig (`design/motion-v2/reference/rig.js`) is simulation art; it never ships and nothing is traced from it. Nothing gets drawn or generated. "Transform" below means moving, scaling or rotating a whole pack picture, which redraws nothing, but whether it's allowed is Q7.

Imported sets checked by eye: `WholeDoddy_*` (17), `UploadedDoddy_*` (5), `DoddyMotion_{idle,jump,sit,wave,pop,turn,walk,run}_*` (40), `VoiceDoddy_talking_1…6`. The pack pictures are flattened: eyes, brow, mouth, head and arms can't move separately.

| Brief pose or behaviour | Pack image set that can carry it | Verdict |
|---|---|---|
| Standing at rest, front | `DoddyMotion_idle_1` | Carried |
| Three breaths | `DoddyMotion_idle_1…4` (pack 013, four-frame breathing). Amplitude is the drawing's, not 0.6 pt. | Carried |
| Crouch before a hop | `DoddyMotion_jump_1` (deep crouch, three-quarter view) | Carried; depth fixed by the art |
| Take-off, arms up, legs tucked at the apex | `DoddyMotion_jump_2`, `_3` | Carried |
| Contact squash, settle | `DoddyMotion_jump_4`, `_5` | Carried |
| Slide-through, surface dip, weight response, drag-lean, lean into travel | Transforms of the current picture | Q7 |
| Size change (1.0× ↔ 1.4×) | Transform. The `WholeDoddy_*` and `DoddyMotion_*` sets are 300 × 450 px at @3x: a 134 pt figure needs about 400 px of figure, so they would be upscaled about 15 % and look soft. The originals (1024 × 1536) can be re-exported larger with `tools/whole_doddy/build_imagesets.py`, which cuts and downscales only. | Needs larger exports (Q11) |
| Face turning toward travel | `DoddyMotion_turn_1…3` (front, three-quarter, side) | Partial |
| Pupils moving on their own; "eyes first" on every reaction | None in the app. The pack's numbering in `docs/design/DODDY_VIDEO_ASSET_PROMPTS.md` (004 expressions, 010 props, 011 fx, 012 walk…) places an **eye-direction sheet at 008**, heads only. It was never imported and couldn't be checked from here. | **Drawn from MV7** on the front-facing pictures (ADR-547): the sheet was opened, it is a 3 × 3 grid of heads, cut into eight looks |
| Blink; slow 280 ms blink (thinking, evening welcome) | As above: a **blink sequence at 007** (open, half closed, closed, half closed), heads only | **Drawn from MV7** (ADR-547) |
| Eyes closed in contentment (head rub, stretch hold) | `WholeDoddy_yawn_stretch` has closed eyes but a yawn and raised arms | **Missing** as a calm face |
| Squint on touch | none | **Missing** |
| Moods in brow and mouth (calm, curious, pleased, concerned) | Bodies say mood through whole poses (`fistpump` pleased, `facepalm` "that went wrong", `shrug` "not found"; ADR-299 meanings). The pack's 004 expression sheet (heads: neutral, smile, pleased, worried, unsure, surprised…) is used only in the website mockups. | Partial; heads only |
| Head roll (welcome 5°, introduce −8°, thinking 4°) | none; only a whole-figure tilt | **Missing** |
| Welcome: default (eyes, roll) / after 21:00 (slow blink, roll) / after 3 days (hop in place, pleased) | Today's hello is the wave strip (`DoddyMotion_wave`, ADR-380). The 3-day hop is `DoddyMotion_jump_*`. | Default and evening **missing**; 3-day carried |
| Shuffle: two side-steps, moving foot lifted 3 pt | `DoddyMotion_walk_*` is side-on travel, which rule 5 forbids for moving around | **Missing** |
| Brace: arms out | `WholeDoddy_oneleg_balance` has arms out but one foot lifted, so it can't stand on a moving edge | **Missing** |
| Listening (glove at the ear) | `WholeDoddy_listening`, `UploadedDoddy_Listening` | Carried |
| Thinking (glove at the chin, optional) | `WholeDoddy_kneeling_inspect` (kneeling, glove at chin), already the voice screen's thinking pose | Partial |
| Introduce the draft (arm −40°), trace the source (arm −35°) | `VoiceDoddy_talking_1` (open palm, talking mouth) and `WholeDoddy_reaching_high` (points up) are the closest | **Missing** |
| Sitting cross-legged | `WholeDoddy_crosslegged`, `UploadedDoddy_Sitting` | Pose carried. The sit-down in between is **missing**: the pack's sit strip (017) sits on a cardboard box (ADR-323). |
| Sitting on an edge, legs hanging | `DoddyMotion_sit_5` sits on the box's edge with legs hanging, but the box is drawn into the frame | **Missing**: removing the box would be an edit |
| Standing up from sitting (140 ms) | none | **Missing** |
| Stretch: arms up, on his toes | `WholeDoddy_yawn_stretch` (arms up, eyes closed, feet flat, yawning) | Partial |
| Wave (playful; arm in front of the head) | `DoddyMotion_wave_1…5` | Carried; check the 5 pt glove clearance on the real frames |
| Ducking: crouch and look up | `DoddyMotion_jump_1`, `WholeDoddy_sneaky_crouch`; neither looks up | Partial |
| Talking (voice screen) | `VoiceDoddy_talking_1…6` | Carried (exists today) |
| Concerned while offline; error | `WholeDoddy_facepalm` is too strong for "concerned" | Partial |
| Pleased on "sent" | No sent result exists (section 1) | n/a |
| Peek, wordmark perch | Not in this brief's deliverables | — |

**New owner art needed, at minimum:** a gaze set (pupils in at least 8 directions plus centre, on a front head that can sit on the standing body), a blink, eyes closed in contentment, a squint, two shuffle step poses, a brace, sitting on an edge with legs hanging (no box), standing up from cross-legged, a front pointing arm low (about −40°), and optionally a standing thinking pose with the glove at the chin. For gaze and blink to work on full-body pictures, the head (or at least the eyes) must come as a separate layer that matches every body pose, or the bodies must be redrawn with their heads separate. That is a drawing decision for the owner's illustrator, not something to composite here.

## 4. Architecture

### What has to hold

One Doddy on screen in every frame, including tab changes, pushes, sheets and covers. Soles within ±2 pt of a moving edge (±1 pt on the composer) at 60 and 120 Hz. The interface commits on the tapped frame and never waits for him. Reduce Motion turns travel into fades. VoiceOver never sees him.

### Option A: one global overlay, positioned from surface frames every frame

He is always drawn in one place: a full-screen layer above the tab content. Each surface reports its frame and he is positioned on top of it.

- **Where the overlay lives:**
  - Inside `RootView` (a `ZStack` over `tabs`): sheets, covers, alerts and the keyboard are presented above it and cover him by themselves, but in-tab pushes slide **under** him, so a detail page can't cover him without a mask driven by the push's progress.
  - In its own pass-through `UIWindow`, like `ListeningIndicatorWindow` (ADR-361, `windowLevel = .alert + 1`): it is above every sheet, so each sheet, cover and alert would also need a mask.
- **Reading frames:**
  - `onGeometryChange` gives layout-time frames, which follow scrolling. Keyboard, push, pop and sheet animations run in the render server, so their in-flight positions need presentation-layer probes read on `CADisplayLink`.
  - SwiftUI's `NavigationStack` hides its `UINavigationController`. Push and pop progress, including the interactive swipe back, can only come from probes on the pages (or fragile introspection of `transitionCoordinator`).
- **Timing:**
  - The value read on tick N is applied on tick N, but the render server draws the system animation for tick N's target time, so his position can be a frame behind: about 2.5 pt at 150 pt/s at 60 Hz, more on a fling.
  - Without `CADisableMinimumFrameDurationOnPhone` in Info.plist (it is not there today), a `CADisplayLink` or SwiftUI timeline runs at 60 Hz on ProMotion iPhones while scrolling and the keyboard run at 120. He would visibly trail the content.
- **Strengths:** one physical view; flights and scale changes are trivial; it matches the reference engine exactly.

### Option B: attached to his surface, re-parented for flights (recommended)

At rest and while riding, he is drawn **inside the surface's own view hierarchy**: an `.overlay(alignment: .top)` "slot" on the stage line, the card row, the rail, the composer, the paper card.

- **For free:**
  - Scrolls, the keyboard (through SwiftUI's keyboard safe area), interactive keyboard dismissal (where used), push, interactive pop, sheet presentations and the tab bar all move or cover him in the same render-server frame, at whatever rate the system runs, 120 Hz included.
  - A detail page pushed over his spot covers him in place, and the pop uncovers his left side first, because that is what the real transition does.
- **For travel:**
  - A root-level overlay inside `RootView` draws him only while he crouches on a surface that has just vanished (a tab's content commits in the tapped frame), while he flies, and while he fades.
  - A single `@Observable` director holds `placement = .slot(id) | .overlay` and the current pose. The slot and the overlay read the same value, so the switch happens in one SwiftUI update and never shows zero or two figures.
  - Take-off reads the slot's last global frame (`onGeometryChange`, already used for `homeArtBox`). At landing the overlay aims at the target slot's frame, predicted with a presentation-layer probe only when a system animation is moving it, and hands over on the contact frame.
- **Lifecycle:** `LazyVStack` recycling, filter, sort and delete can remove the slot he stands on. The slot's `onDisappear` tells the director, which moves him to the overlay at the last known frame and then hops or fades him to the fallback spot.
- **Costs:** two render paths for one figure; hand-off alignment must be tested on device; slots need adding to each surface view, which is real but small layout work.

### Comparison

| | A: global overlay | B: attached + flight overlay |
|---|---|---|
| Riding a 120 Hz scroll within ±2 pt | Only with presentation probes, the 120 Hz Info.plist key and same-frame commits; one-frame lag likely on flings | Exact: the system moves him |
| Composer ±1 pt with the keyboard, including interactive dismissal | Needs keyboard-frame tracking per frame; interactive dismissal posts no per-frame notification (`UIKeyboardLayoutGuide` helps) | Exact, if SwiftUI's keyboard safe area follows interactive dismissal (verify on device) |
| Covered in place by a push; pop uncovers left first | Needs a mask driven by push progress | Free |
| Sheets and covers on top of him | Free if the overlay is in `RootView`; masks if it is a separate window | Free |
| Custom tab bar, tab change | Simple: he is already in the overlay | The tapped frame moves him to the overlay (the tab bar's button calls the director in the same transaction as `selectedTab`) |
| Flights, scale in flight, fades | Simple | Simple once in the overlay; hand-off at both ends |
| Risk of two or zero figures | Low (one view) | Controlled by one `placement` value; must be tested at every hand-off |
| Main risk | Lag and jitter while riding, masks everywhere | Hand-off alignment; slots on every surface |

**Recommendation:** B. Riding and covering are most of the brief's rules (4, 6, and the covered-by-a-page behaviour), and B gets them from the system instead of imitating it. A remains the fallback for a surface that can't host a slot.

### APIs

- **SwiftUI:** `onGeometryChange(for:of:action:)`, `coordinateSpace(.global)`, `.overlay(alignment:)` slots, `TimelineView(.animation)` for flights, `@Environment(\.accessibilityReduceMotion)`, `accessibilityHidden(true)`, and `onScrollGeometryChange` / `onScrollPhaseChange` for scroll velocity and phase (**iOS 18+**; the deployment target is iOS 17.0, Q10).
- **UIKit:** a `UIViewRepresentable` probe with `CALayer.presentation()`; `CADisplayLink` with `preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)`, running only while he moves; `keyboardWillChangeFrameNotification` (end frame, duration, curve); `UIKeyboardLayoutGuide`.
- **System state:** `ProcessInfo.isLowPowerModeEnabled` with `NSProcessInfoPowerStateDidChange` (glances off), and the existing `hideCharacterArt` preference (hides him entirely).
- **Info.plist:** `CADisableMinimumFrameDurationOnPhone = YES` for 120 Hz flights (Q9).
- **Honesty inputs, read only:** `VoiceSessionController.phase` (`.listening`, `.thinking`) and `VoiceSessionController.microphone` (read the way `ListeningStop.snapshot()` reads it, `ListeningStop.swift` line 18) for the listening pose. Nothing in the voice session changes.
- **Engine:** pure Swift in `Packages/DoddyCore`, time-based (milliseconds in, state out), so 60 and 120 Hz give the same path. Name its types so they don't clash with the existing `DoddyMotion` strip enum in `Shared/IslandArt/IslandPose.swift`, e.g. `MotionEngine`, `MotionSurface`, `HopPlan`.

### Risks

- **Push and pop progress:** handled by B. A needs the hidden navigation controller.
- **Interactive keyboard dismissal:** Ask doesn't use it today. If it's added, B depends on SwiftUI's safe area tracking the keyboard frame by frame (device check).
- **Custom tab bar:**
  - The `TabView` switch is instant, with no fade, so the old tab's surfaces vanish on the tapped frame. He must already be in the overlay in that same transaction; that needs a call from `DoddyTabBar`'s buttons.
  - The brief's 120 ms content fade doesn't exist here. The interface commits even faster, which rule 2 allows.
  - iPad uses `SidebarLayout` (ADR-430) instead. Keep the motion world iPhone-only first (Q13).
- **ProMotion:** B's riding runs at the system's rate. Overlay flights run at 60 Hz unless the Info.plist key is added. A 60 Hz flight is acceptable; a 60 Hz rider on a 120 Hz scroll is not, which is the main reason for B.
- **Existing tests:** `DoddyUITests/DoddyArtTests.swift` asserts which picture is on screen through `doddy.pose.*` and `doddy.motion.*` markers (ADR-336). Moving those pictures into the persistent Doddy changes what those tests see; the markers should move with him.
- **Battery:** stillness is the default. The display link runs only while he moves or rides, never while idle.

## 5. What can't be honoured yet

| Rule (BRIEF.md "Rules he never breaks") | Why not yet |
|---|---|
| 1. One Doddy | 20+ in-screen pictures of him exist (section "In short"). Until each is converted, retired or confirmed as a full-screen story that covers him (Q4), screens such as empty Memories, problem views and Find's "nothing found" would show two. The voice cover and `VoiceDoddyView` need the hide-at-commit rule (section 1). |
| 3. Eyes first (pupils at 0 ms, 95 % in 88 ms) | The art has no independent pupils or gaze (section 3). Every gaze-only reaction ("Noticing", glances, look-around, eyes following a finger, thinking's eyes up and right) depends on it. Until the art exists, the only honest substitute is a whole-pose change (say, the turn frames), which isn't "eyes first". |
| 4. Feet on something real, ±1 pt on the composer | Achievable with option B, but no measurement exists yet. The ground line has to be computed per picture: `cut_frames.py --shared` gives the strips one ground; the `WholeDoddy_*` poses each have their own figure box (`IslandPose.figure`). Unverified until MV3 on a device. |
| 5. Free travel is one hop | Carried by `DoddyMotion_jump_*`, but the strip is three-quarter view and fixed in depth. The brief's crouch depth (5 pt, 7 pt at 1.4×) and squash range would come from transforms (Q7). |
| 6. Moving surfaces carry him | Home and Memories scroll, Ask's composer and the tab bar can carry him with option B. The draft panel and strip don't exist. Scroll velocity for lily-pad hops needs iOS 18 APIs (Q10). |
| 8. Clear zones | Memories cards (text to x 348) and the rule inside `MemoryPaperCard` break it until the layout changes (Q5). At accessibility text sizes the detail heading can reach his zone. |
| 9. Stillness; one playful moment; welcome once a day | ADR-313/323 play four breaths and then sit on a box every launch, and ADR-380 waves on the first morning visit. The brief says three breaths, sitting cross-legged at 15 s idle, the wave as a playful moment, and a welcome that is eyes plus a head roll. The default and evening welcomes can't be drawn yet (no gaze or blink art). |
| 10. Honest always | The listening pose can be honoured: it is driven only by the session's real `.listening` phase. The "sent" cue can't exist because the app never learns that a message was sent (`sms:` link); nothing shows a sent cue, which is honest. Pleased-on-sent needs `MFMessageComposeViewController` (Q8). Press and hold on Home can't start capture on Home; it can only open the voice screen like a tap. |
| 12. Accessible | Reduce Motion fades, VoiceOver hiding and "Hide Doddy's pictures" can all be honoured. Not yet decided: a real "Talk to Doddy" button over his clear zone would duplicate Home's existing "Talk to Doddy" button for VoiceOver (Q14). |
| 13. Two sizes, one figure | The 1.4× Home size softens the current 300 × 450 px exports (Q11). The accessibility-size cap (100 pt) conflicts with 134 pt (Q12). |
| New behaviours with no art | Brace, shuffle, head rub, squint, introduce-the-draft pointing, trace-the-source, edge-sit and stand-up (section 3). |
| New behaviours with no app state | The draft panel and strip (09, N7, N10, N13), Apple's composer results, the offline banner (no such banner exists; the voice screen shows its own offline card), toasts above his head (no toast system). |

Rules 2, 7 and 11 have no blocker.

## 6. Milestones

Small, reviewable steps; each ends with a report and stops. "Linux" means `make test-core` (`scripts/ci.sh --core-only`). "Xcode" means simulator builds and UI tests. "Device" means a physical iPhone, ProMotion for 120 Hz.

| Step | What | Where it runs | Out |
|---|---|---|---|
| **MV0** (this) | This plan | — | Owner's answers to section 7 |
| **MV1** Engine | Port `reference/engine-core.js` and `engine.js` to pure Swift in `Packages/DoddyCore`: spring with look-ahead, hop planning (crouch lengths, flight time, apex, Hermite path, aim at touchdown, re-plan past 2 pt), mid-air re-target limits, tab-hop cap, scale only in flight, Reduce Motion fades with one invisible frame, calm mode, shuffle decision, lily-pad and rail decisions, brace (DECISIONS.md thresholds), idle and noticing timers. Surfaces enter through a protocol (id, layer, scale, top edge now and ahead, x range, moving). | **Linux.** Golden tests feed the reference layout (`L` in `engine-core.js`) and must reproduce `design/motion-v2/telemetry/` within ±1 ms and ±0.5 pt, e.g. Talk → Memories: crouch 80, flight 401 (formula 419, capped), contact 483 ms after the tap. | Engine and tests. No UI. |
| **MV2** Surfaces and look | Only what Q2–Q5 approve: the 140 pt stage line under Home's art, the Memories right gutter (or rules) and the 108 pt bottom inset, slots and frame reporting on the stage, cards, rail, Ask composer and paper card, the Talk-to-Doddy hit area if Q14 says so. No token change. Doddy doesn't move yet. | **Xcode:** previews, UI tests, screenshots. Linux: the token tests stay green. | Measurable surfaces |
| **MV3** One Doddy, hopping | Director, slots and root overlay (option B), tab hops with 1.4× on Home in flight only, Reduce Motion fades, Hide pictures, VoiceOver hidden. The hide-at-commit rule for every cover and sheet. The existing pictures on the three tabs converted per Q4. Pose mapping from section 3 only, with gaps logged in `docs/design/MOTION_V2_ART_REQUESTS.md`. A DEBUG annotated mode (surface line, clear zone, frame counter) and DEBUG checks (one instance, sole gap, scale rule, clear zone). | **Xcode** for UI tests; **device** for the hand-offs. Compare with reference studies 02, 12, 16 and N1. | Doddy hops between tabs |
| **MV4** Riding | Home's scroll; Memories scroll riding, lily-pad hops and the rail wait (iOS 18 APIs, or the rail only on iOS 17 per Q10); covered in place by detail pushes; arriving on an open detail page; the Ask composer with the keyboard; calm mode; the undo bar as a moving surface. | **Device** (120 Hz, keyboard). Studies N9, 14, 16, J. | He rides what moves |
| **MV5** Behaviours | Only where the art and app state exist: touch-down dip, tap and hold to talk, drag-lean and flick (if Q7 allows transforms), breaths, sitting cross-legged at 15 s, the listening pose from the session's real phase, thinking in Ask, the wave and stretch as playful moments, the 3-day welcome hop. Everything blocked goes to the art-requests doc with its study. | **Xcode + device.** Linux for the timers and budgets. | The living parts that can be drawn |
| **MV6** Evidence | Acceptance checks as DoddyCore tests (logic), UI tests (what the simulator shows), and a device checklist (ProMotion, keyboard dismissal, VoiceOver, Reduce Motion, Low Power, the journey with the debug overlay). The five-person hallway-test script for 1.3×, 1.4× and 1.5×. | All three; nothing marked passed that wasn't run. | Evidence |

Each step updates `STATUS.md`, `docs/platforms/iphone.md` and the ADR log with what the code supports, and nothing beyond it.

## 7. Questions for the owner

Each has a recommended answer. MV1 needs Q1, Q7 and Q9; the rest can wait for MV2–MV5.

1. **Commit `design/motion-v2/` to the repo** (it isn't on this branch)? *Recommended: yes, as design reference next to `design/interface-v1.2/`, so MV1's golden tests can read the telemetry. `reference/rig.js` stays marked simulation-only.*
2. **What is Talk?** The voice screen, Ask, or a new Talk tab (a navigation change)? *Recommended: a tap or hold on him opens the voice screen as today; the voice screen keeps its own `VoiceDoddyView` for now, and the persistent Doddy hides in the frame the cover starts. Ask is the composer surface for keyboard behaviours. Bringing the voice screen under the engine is a later, separately approved change to `VoiceView.swift`'s UI (never the session).*
3. **Draft review strip and panel:** leave out, map to the voice action card later, or build one? *Recommended: leave out now; use `UndoDeleteBar` as the "strip if showing" for the rail; revisit with the voice screen.*
4. **Doddy's existing pictures:** for each, become the persistent Doddy, stay as a full-screen story that covers him, or retire? *Recommended: become him on Home (art box), empty Memories, Settings (Privacy picture), problem views and Find's "nothing found" (he does the pose on his spot); stay as covering stories for the opening, onboarding storybook, Face ID door, Back Tap guide and every sheet or cover (capture pop, check-in wave, voice screen); retire nothing yet.*
5. **Memories rows:** cards with a 66 pt right gutter, cards as they are (clear zone broken), or ruled rows like the brief? *Recommended: keep the approved cards, add the gutter and the 108 pt bottom inset.*
6. **Gaze and blink art:** does the pack have the blink sequence (007) and eye-direction sheet (008)? If yes, may heads from them be used on the pack's bodies, and who makes the head-and-body layers? *Recommended: the owner checks the Drive folder; the pack's illustrator delivers layered heads (or bodies with separate heads) for the standing front pose first. No compositing here. Until then every gaze-only reaction is off, not faked.*
7. **Transforms on pack pictures:** may the engine move, scale, squash (up to about 5 %) and tilt (up to 12° for the drag-lean, 6° in flight) a whole picture? None of it redraws anything, but CLAUDE.md's art rule and the "no invented animation" comment in `UploadedCharacterView` suggest asking. *Recommended: yes, whole-picture transforms only; never moving parts of a picture.*
8. **Apple's message composer:** keep the `sms:` hand-off (no "sent" cue ever), or adopt `MFMessageComposeViewController` to get sent, cancelled or failed? *Recommended: keep the hand-off. Changing the message flow touches the voice tool path and is its own decision.*
9. **120 Hz:** add `CADisableMinimumFrameDurationOnPhone` to Info.plist so flights run at 120 Hz on ProMotion iPhones? *Recommended: yes; the display link runs only while he moves.*
10. **iOS 17:** scroll riding needs iOS 18's scroll geometry and phase APIs. Raise the deployment target, or let iOS 17 skip lily-pad hops (he waits on the rail during any scroll)? *Recommended: keep iOS 17 and use the rail-only fallback there.*
11. **Higher-resolution exports for 1.4×:** re-export the strips and poses from the pack originals at a larger size (cut and downscale only, with `build_imagesets.py`)? *Recommended: yes, for the sets used on Home.*
12. **Accessibility text sizes:** the app shrinks his pictures to 100 pt there; the brief's Home is 134 pt. *Recommended: at accessibility sizes he stays 1.0× on Home (96 pt) and the camera-close size is off.*
13. **iPad:** the sidebar layout has no tab bar or rail. *Recommended: iPhone only first; iPad keeps today's pictures.*
14. **The "Talk to Doddy" hit area over his clear zone:** Home already has a "Talk to Doddy" button. Two elements with the same label confuse VoiceOver. *Recommended: add the hit area for touch, hidden from VoiceOver, and keep the existing button as the accessible one.*
15. **Home's idle and hello (ADR-313/323/380) against the brief:** four breaths, then sitting on the box, and a morning wave, versus three breaths, sitting cross-legged at 15 s idle, the wave as the session's playful moment, and a welcome of eyes plus a head roll. *Recommended: the brief wins, recorded as a new ADR. The welcome stays the wave until the gaze and head art exists, since the default welcome can't be drawn honestly without it.*
16. **"Hey Doddy" and the listening pose:** the wake-word listener keeps the microphone open on Home, possibly for hours. Does that count as "the microphone is live" for the listening pose? *Recommended: no. The listening pose follows only a conversation's capture (`VoiceSessionController.phase == .listening`); wake-word listening is already shown by the listening indicator (ADR-361).*

## Sources read

`CLAUDE.md`, `AGENTS.md`, `STATUS.md`, `DoddyApp/CLAUDE.md`, `docs/platforms/iphone.md`; `design/motion-v2/README.md`, `BRIEF.md`, `DECISIONS.md`, `reference/engine-core.js`, `engine.js`, `scripts.js`. `reference/prototype.html` was opened headlessly in Chromium; the journey study ran with the live checks reporting all passing.

App code read:
- `DoddyApp/App/RootView.swift`
- `DoddyApp/DesignSystem/` (Theme, DoddyMotionView, Components, MemoryJourneyComponents, including `DoddyTabBar`)
- `Features/Home/HomeView.swift`
- `Features/Memories/MemoriesView.swift`, `MemoryDetailView.swift`
- `Features/Ask/AskView.swift`
- `Features/Voice/VoiceView.swift`, `VoiceDoddyView.swift`, `VoiceSessionController.swift` (state model only), `ListeningStop.swift` (read only)
- `Shared/IslandArt/IslandPose.swift`

Design and art:
- `Packages/DoddyCore/Sources/DoddyDesignTokens/` and its tests
- `docs/design/CANONICAL_DESIGN_DIRECTION.md`, `UPLOADED_MEMORY_ASSETS.md`, `DODDY_VIDEO_ASSET_PROMPTS.md`
- `design/website-what-can-doddy-do/README.md` (pack provenance)
- ADR-225, 264, 299, 308, 313, 323, 336, 361, 380, 430 and 457 in `DECISIONS.md`
- Every Doddy image set in `DoddyApp/Resources/Assets.xcassets`, viewed as contact sheets

## Not verified

- No Swift toolchain here, so nothing was compiled or run.
- The pack's unimported files (007, 008, 004) were inferred from the numbering, not seen.
- Whether SwiftUI's keyboard safe area follows interactive dismissal frame by frame on iOS 26/27 is unknown.
- None of the options in section 4 has been prototyped in the app.
