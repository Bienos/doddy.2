# V3 status — Doddy in the Dynamic Island
Date: 2026-10-09. Owner request: "it opens app [with] double back tap, now live island". ADRs 053–054 in `DECISIONS.md`.

## What it does
- Start a conversation as before (Talk to Doddy, Double Back Tap, Action Button). You can now go Home or open another app: the conversation keeps running and Doddy appears in the **Dynamic Island** (and as a banner on the **Lock Screen**).
- Island design (ADR-238, ADR-239): the owner's V4 boards (`design/dynamic-island-v4/`), drawn from the pack's own SVGs. Default **Lean In**; Settings → Voice → Dynamic Island style also offers Orbit, Ink Ripple, Negative Space, Editorial, Abstract Horizon and Here With You. While a note, plan or reminder is in play the island switches to Thought Pocket, Step Stones or Reminder Knot (ADR-240); while Doddy translates, to Language Bridge with the language pair only (ADR-244). Doddy's face with the pack's own expressions (listening smile, open mouth when speaking, brow up when thinking or waiting, calm when connecting/muted/lost), his cupped hand and an orange arc while he can hear you.
- Compact island: face + hand on the left; on the right five voice bars (listening/speaking), three dots (thinking/connecting) or a symbol (mic-slash = muted, hand = confirm a note in the app, warning = lost).
- Minimal (another activity is running): face + three bars or dots.
- Long-press the island (expanded, the "big" one): "VOICE ● LIVE" and the time beside the camera; big Doddy with hand and arc, the status in 21 pt with a second line, **Mute/Unmute** and **Stop** pills, and the voice bars.
- Lock Screen: the same, as a card that follows the phone's light/dark setting (paper in light, Night in dark). Muted: mic-slash, "Doddy can't hear you", Unmute is the main button, no orange. After End: a "Conversation ended" card with the notes you saved and the total time, removed after 2 minutes (ADR-106).
- Tap the island to jump back into the app (e.g. to Save or Don't save a note Doddy proposed).
- The island disappears the moment the conversation ends (End, Close, connection lost, failure). A stale one from a killed app is removed at the next launch.
- **If iOS stops Doddy in the background** (reports exist of background recording being ended after ~50 s), the island does not keep saying "Listening": every update carries a 90 s stale date, a heartbeat refreshes it every 40 s while the app is alive, and once stale the island shows "Lost Doddy — open the app" with a **Dismiss** button only (ADR-055). Dismiss works even when the app process is gone.

## How
| Piece | Where |
|---|---|
| Activity type + labels/symbols | `Shared/VoiceActivity/DoddyVoiceAttributes.swift` (app + extension) |
| Mute / End buttons | `Shared/VoiceActivity/VoiceActivityIntents.swift`: `LiveActivityIntent`s; the app registers handlers in `VoiceSessionController.start`. On iOS 27+ they are pinned to the app process (`allowedExecutionTargets = .main`, ADR-128); the widget extension's copy has no handlers |
| Island + Lock Screen UI | `DoddyWidgets/` widget extension (target `com.bienos.doddy2.dev.widgets`); art = owner-approved `UploadedDoddy_Listening` / `_Kept` / `_Sitting` (numbered ZIP poses, downscaled for the widget); light/dark colour sets in `DoddyWidgets/Assets.xcassets` (ADR-106) |
| Start / update / end | `DoddyApp/Features/Voice/VoiceLiveActivity.swift`, driven by `didSet` on phase, mute and pending save in `VoiceSessionController` |
| Background audio + Live Activities | `Config/Doddy-Info.plist` (`UIBackgroundModes: audio`, `NSSupportsLiveActivities`) |
| Keep running in background | `VoiceView` no longer ends the conversation on `scenePhase == .background` |
| Stale date + heartbeat; stale rendering; End fallback | `VoiceLiveActivity` (`staleAfter`, `heartbeatEvery`), `DoddyWidgets/DoddyVoiceLiveActivity.swift` (`context.isStale`), `EndDoddyConversationIntent` ends leftover activities |

## Verified
Linux only: capability guard passes (now also scans `DoddyWidgets/`, `Shared/`, `Config/`); plists and asset JSON parse. **The app, the widget extension and the Shared files have not been compiled** (ActivityKit/WidgetKit are Apple-only). See the bottom of this file for the Swift package test run of 2026-10-09 (second session).

## To check on the iPhone
1. Build: `git pull && make project`, then set **Team** for **both** targets, `Doddy` and `DoddyWidgets` (Signing & Capabilities).
2. Start a conversation, press Home: island shows Doddy; talk — status changes listening → thinking → speaking.
3. Keep talking from another app for 2+ minutes (reports exist of iOS killing background recording after ~50 s).
4. Long-press island → Mute (status "Muted", Doddy can't hear you) → Unmute → End (island disappears, app shows "Conversation ended").
5. From another app ask "remember that my locker code is 1234": island shows the hand / "Confirm in Doddy"; tap it, Save.
6. Lock the phone mid-conversation: Lock Screen banner with Mute/End.
7. Settings → Doddy → Live Activities off: conversation still continues in the background, no island.
8. **Stale island.** Start a conversation, go Home, then force-quit Doddy from the app switcher. Within about 90 s the island must change to "Lost Doddy — open the app" (yellow warning symbol, no Mute). Tap **Dismiss**: the island goes away. Then open Doddy: no island appears.
9. **Heartbeat.** Keep a conversation running from another app for 3+ minutes without saying anything: the island must *not* turn stale while Doddy is still connected (the heartbeat refreshes it every 40 s). If it does, note the time it took: that is the point where iOS stopped the app, and the "Lost Doddy" state is the correct outcome.
10. **Lock Screen stale state.** Same as 8 with the phone locked: the banner shows the warning text and only Dismiss.
11. **Light and dark (ADR-106).** Lock the phone mid-conversation in Light mode: paper card, dark text, orange waveform. Switch to Dark mode (Control Centre): Night card, light text, Doddy on a small paper backing. The island looks the same in both: Doddy on a paper backing on black.
12. **Muted.** Mute from the Lock Screen: orange disappears, "Muted · Doddy can't hear you", Unmute is the filled button.
13. **Ended card.** Save one note, then tap End on the Lock Screen: the card changes to fist-pump Doddy (sitting Doddy if nothing was saved), "Conversation ended", "Doddy isn't listening · 1 note saved · m:ss total", Open Doddy. It disappears after about 2 minutes; the island is gone at once. A failed connection instead removes the card at once.
14. **Art.** The island no longer uses the full-body pose (too small at 26 pt): it draws the Lean In face from the owner's pack (ADR-238). **Whole Doddy (the default style) since ADR-615:** the compact island shows only his head (26 pt), the expanded island all of him with a 1.5 pt cream edge and a faint light, with bolder waves; while he talks they stay in the band under his status, start beside him and spread to the right. Check: the head is centred beside the camera, his feet aren't cut at the bottom of the expanded island, the faint light isn't cut hard, the talking waves don't hide "Speaking", the pills read in full ("Mute", "Open", "Stop", or without symbols), and the waves look like smooth lines at arm's length. Pictures of the views: the `island-screenshots` artifact of the hosted Mac job. The Lock Screen keeps the pose art at 52 pt, from 160/240 px-tall downscales of the pack images; if it looks soft, ask design for a native small export of the same poses.
15. **Lean In island (ADR-238).** Compare the island against `design/dynamic-island-v4/01-boards/01-voice.svg`: listening (smile, hand, orange arc, bars, "VOICE ● LIVE"), speaking (open mouth), thinking (brow up, dots), muted (calm face, no hand, no orange, mic-slash, Unmute is the cream pill), Confirm in Doddy (brow up, hand symbol), lost (calm face, yellow line, Dismiss only). Check the face is centred and nothing touches the camera; the pills are tappable (the board's 34 pt pill sits in a proposed 44 pt target, not proven); the time does not push the label off; minimal shows face + bars beside another app's activity. Text sizes are fixed points from the board, so check the largest text setting too.
16. **Styles (ADR-239).** Settings → Voice → Dynamic Island style: the previews show all seven; pick each in turn, start a conversation, go Home and compare the island with its board in `design/dynamic-island-v4/01-boards/` (Orbit 05, Ink Ripple 06, Negative Space 07, Editorial 09, Abstract Horizon 10, Here With You 04). Check that orange turns grey when muted, and Here With You's compact shows the time.
17a. **Cards and results (ADR-616).** From another app ask Doddy to text someone: the island says "A text to check", the expanded island has Show (cream) instead of Open, the Lock Screen has Show in Doddy; tap Show: Doddy opens with the card (half height); nothing was sent; tap Open in Messages, press Send yourself. Repeat with a BLIK transfer ("A transfer to check"), an email, Maps, a calendar change. Ask for a document (make_document): "Your document is ready" (or "Making your document") for about 8 s, Show opens the conversation with its button. End the conversation, then tap an old island link from the Lock Screen if one is left: Doddy opens on Home and starts nothing. Nothing a card says (a name, a number, a message, an amount) ever shows on the island or the Lock Screen.
17. **Moments (ADR-240).** From another app: ask Doddy to remember something → Thought Pocket "Save this note?"; tap the island, Save → "Note saved" for about 8 s, then back to the voice style. Ask for two changes at once → Step Stones "Plan ready"; confirm → "Doing the plan · Step i of N". Ask for a reminder → Reminder Knot; Add → "Adding reminder" then "Reminder set" for about 8 s. Lock the phone during each: nothing the note or reminder says appears on the island.
18. **Focus (ADR-241).** Home → Focus, 15 min, type a line, Start. Go Home: Tiny Promise with the countdown ticking and your line. Pause from the island (time stops, "Paused"), Resume, then lock the phone: Lock Screen card with Pause/Stop. Let it run out with the app in the background: the island says "Time's up" and a "Focus done" notification arrives. Force-quit Doddy mid-focus, then tap Pause on the island: it still works (iOS starts Doddy for it). Turn notifications off for Doddy and start one: the screen says there may be no alert.
19. **Breathing (ADR-242).** Home → Breathe, 1 min: the tide drawing and "Breathe in"/"Breathe out" switch every 4/6 s; Reduce Motion on: no scaling, words still switch. Go Home: the island shows "Breathing" and the time left, no In/Out. After the minute: "Breathing done".
20. **Read aloud (ADR-243).** Open a note → Read aloud: iPhone voice reads it (a Polish note in a Polish voice if one is installed). Go Home: Story Spool "Reading aloud · Your note", no words of the note. Pause/Resume/Stop from the island. Start a conversation while it reads: reading stops. Force-quit while reading: within about 90 s the island says "Stopped".
21. **Translating (ADR-244).** Home → Translate, face to face, English and French, Start; go Home. The island shows Language Bridge: "TRANSLATE ● LIVE", "Translating", "EN ⇄ FR", "EN" and "FR" in the two bubbles (centred, not clipped, black on cream; compare `design/dynamic-island-v4/02-states/language-bridge-0-expanded.svg`), compact "⇄ FR", minimal "FR" beside another app's activity. Talk both ways for a minute, with the phone locked and unlocked: **no word of what either person said ever appears on the island or the Lock Screen**, only the codes. Repeat with "Detect when they talk": "EN ⇄ ?" until they speak, then their code. Listen only, Italian: "IT → EN". Turn on "Noisy place: hold to talk": between holds the orange line is grey. Say "stop translating": the island goes back to your voice style. It never shows "Translation ready" or "Hear it". Three-letter codes (e.g. `ast` if offered) fit in the bubbles at the largest text setting.

## Verified on Linux — 2026-10-09 (second session, after ADR-055)
| Step | Result |
|---|---|
| Environment | Ubuntu 24.04 x86_64, Swift 6.1.2 toolchain (downloaded for this run; not part of the repo) |
| `scripts/check_forbidden_capabilities.sh` | PASS (scans `DoddyApp`, `DoddyWidgets`, `Shared`, `Config`; microphone the only permission) |
| `scripts/verify_imported_pack.py` | PASS (259 files match the manifest, no font binaries) |
| `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT` | PASS: **49 tests, 0 failures** (DoddyCore 40 incl. BackTapSetup and VoiceContext; DoddyDesignTokens 7; DoddyPersistence 2 on real SQLite) |
| `swiftc -parse` on every file in `DoddyApp/`, `DoddyWidgets/`, `Shared/`, `DoddyTests/`, `DoddyUITests/` | PASS, 27 files (syntax only; ActivityKit/WidgetKit/SwiftUI cannot be type-checked on Linux) |
| `Config/*.plist` | parse as valid plists |
| iOS app build, widget extension build, unit + UI tests | **NOT RUN** (no Xcode here) — items 1–10 above are the owner's device checklist |

## Go live (2026-10-10, owner: "go live with dynamic island")

**Where it stands.** The island is not behind a flag, a setting or the offline fixture: every real
conversation drives it (`VoiceSessionController.syncIsland`, from `phase`, `pendingAction` and
`isMuted`). There is nothing left to switch on in code. What stops it from being called live is
evidence: the current line has never been compiled with Xcode, and the one Mac run on an earlier
revision (`NATIVE_BASELINE_REPORT.md`, iOS 27 simulator) rendered the island but left the system
**Unmute** button red; the fix for that (ADR-131: `allowedExecutionTargets = .main` on iOS 27+) has not
been compiled or run since.

**Done in this session (Linux, no Xcode).**
- The two island intents now log which process performed them and whether a conversation handler was
  there (`IslandIntentLog`, `Shared/VoiceActivity/VoiceActivityIntents.swift`; Console subsystem
  `com.bienos.doddy2`, category `island`). This is the step ADR-131 named for a red re-run: it tells
  "iOS routed the tap to the widget extension" apart from "the handler was never registered" and
  "nothing ran". Only the bundle identifier and a yes/no are logged, never conversation content.
- Hosted macOS CI (ADR-123) is recorded as never having started a step: all 58 runs, the Ubuntu job
  included, fail in seconds with no runner and no logs (`BUILD_AND_TEST.md`). Fixing that is an
  account setting (billing or Actions policy), not a workflow change.
- PR #9 ("V3: Dynamic Island Live Activity…", branch `claude/admiring-bohr-0xn7fa`) is an earlier,
  superseded cut of this feature: different types (`DoddyShared`, `VoiceActivityBridge`), ADR numbers
  038–041 that now belong to other decisions, and a stricter rule (conversation ends when the Live
  Activity is not showing) that ADR-054 replaced. Merging it would conflict and regress; it should be
  closed, not merged.

**Owner steps to go live, in order.**
1. Make the Mac build run: either get a hosted run to start (see `BUILD_AND_TEST.md`, "Hosted macOS
   CI") or build locally: `git pull`, `make project`, set **Team** on `Doddy` and `DoddyWidgets`.
2. Run `DoddyTests/IslandBaselineTests` (4 tests) and
   `DoddyUITests/MemoryBaselineTests/testNativeIslandOfflineFixtureCanStartMuteAndEnd` on an
   iPhone simulator with a Dynamic Island. Green = ADR-131 holds. Red = read the `island` Console
   line: "`…widgets`" means the pin did not route and the fallback is a Darwin-notification relay from
   the extension to the app (separate ticket, not built); "handler: no" in the app process means the
   handler path, not routing.
3. Device checks 1–14 above on an iPhone 14 Pro or later, with the owner's ElevenLabs agent (paid
   minutes): especially 3 (2+ minutes in another app), 8–9 (stale and heartbeat) and 13 (ended card).
4. Only then change the ADR-053/055/106/131 rows from "unbuilt" to built, with the date, Xcode and
   device, and record the results in `MAC_VERIFICATION_CHECKLIST_2026-10-10.md`.

**Still not "live" after that:** no TestFlight or App Store build, the dev agent is public (ADR-034),
no legal review, and the background-audio behaviour on a real iPhone (research §3's ~50 s reports)
is unknown until step 3.

### Verified on Linux — 2026-10-10 (this session)
| Step | Result |
|---|---|
| Environment | Ubuntu 24.04 x86_64, Swift 6.1.2 toolchain (downloaded for this run; not part of the repo), Node 22.22 |
| `scripts/ci.sh --core-only` | PASS: pack integrity, capability guard, voice and phone agent specs, blog pages, Swift package tests (371 tests, 0 failures), app logic type-check (8 files), voice token server 63, backend, gateway, messaging server 13 (database tests SKIPPED: no `TEST_DATABASE_URL`) |
| `scripts/check_forbidden_capabilities.sh` after the intent change | PASS (`import os` and the log line are allowed; no new permission, no networking) |
| `swiftc -parse -swift-version 6` on every file in `DoddyApp/`, `DoddyWidgets/`, `Shared/`, `DoddyTests/`, `DoddyUITests/` | PASS, 85 files (syntax only) |
| iOS app build, widget extension build, unit + UI tests, device checks | **NOT RUN** (no Xcode here; hosted CI never starts) |

### Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run (Linux) | Gaps / claims to limit |
|---|---|---|---|
| DOD-08 verified_status_and_receipts | The island shows only states from SDK events; a stale date (90 s) and heartbeat (40 s) make it say "Lost Doddy" instead of "Listening" when the app is gone (ADR-055); "Conversation ended" carries the saved count from actual Save taps | None runnable on Linux (`IslandBaselineTests` need a simulator) | Not compiled; device behaviour unknown |
| DOD-07 scoped_action_approval | Mute and End are the only island actions; both run the conversation's own handlers; nothing is saved or sent from the island; "Confirm in Doddy" sends the user to the on-screen card | — | — |
| DOD-11 observable_privacy | No conversation text in the activity; the new log holds a bundle identifier and a yes/no only (`privacy: .public` on those two values, nothing else) | Guard PASS | Logs are readable in Console on a connected Mac; that is the point, and they contain nothing personal |
| Honest capability claims (T35/T42) | This document and the ADR rows keep "unbuilt / not run"; the user-facing text in `VoiceView` already says iOS may stop Doddy in the background | — | Do not describe the island as working until step 3 above is recorded |

## Since 22 Oct: one "Talk to Doddy" control that follows Settings (ADR-579)
The section below is ADR-577's. Since ADR-579 the "Talk to Doddy" control itself starts in the Dynamic
Island by default (Settings › Action Button: Dynamic Island, Open App or Automatic), a second press ends
the conversation, "Small island" is Settings › "Expand when Doddy speaks", and a failed start leaves a
"Conversation stopped" card on the Lock Screen. Root cause, flow and the 16-row device matrix:
`ACTION_BUTTON_ISLAND.md`. Device check A below now applies to "Talk to Doddy".

## Talk in the Island, and an island that opens up (ADR-577, 2026-10-20)

> **Changed 22 Oct (ADR-593):** the Action Button opens Doddy again. Owner: "make it so when I press
> the Action Button the Doddy app opens, not the Dynamic Island alone with Doddy." The control below
> (`TalkInIslandControl`, kind `com.bienos.doddy2.talk-island`) now runs `TalkToDoddyIntent` and is
> named "Talk to Doddy", so an Action Button already set to it opens Doddy after the update with
> nothing to change. `TalkInIslandIntent` and everything it starts are unchanged and stay in the
> Shortcuts app as "Talk in the Island"; no control runs it. The island still opens up when Doddy
> speaks once you leave the app. The steps and checks below describe ADR-577 as it was.
Owner: "The live island stuff is just so bad. It's not expanding, it's not doing anything really",
and "The Action Button should open the Doddy Dynamic Island, the big expanded one, when he starts
talking, not open the app. I don't want to hold it."

**Why it did nothing.**
- Every way in opened the app: `TalkToDoddyIntent` has `openAppWhenRun = true`, and the voice
  screen is a full-screen cover. iOS shows an app's Live Activity in the Dynamic Island only while
  that app isn't the one on screen, so for the whole time you talked in Doddy there was no island.
- The only request to open the island up (`VoiceLiveActivity.openForGreeting`, an alert update) was
  sent from `VoiceView` right after the conversation connected, with the voice screen in front, so
  iOS never showed it; and only for shortcut starts. No other update carried an alert, so after you
  left the app the island stayed the small strip unless you touched and held it.
- While Doddy said "Hey Pat, what's up?" the island said "Speaking": the greeting was shown only
  while connecting and listening.
- There was no way to start without the app: every conversation started on the voice screen.

**What changed.**
- **"Talk in the Island"** (`Shared/Shortcuts/TalkInIslandIntent.swift`, iOS 18+): an
  `AudioRecordingIntent` and `LiveActivityIntent` with `openAppWhenRun = false`, run in the app's
  process. The new control `DoddyWidgets/TalkInIslandControl.swift` runs it, so the Action Button can
  (Settings › Action Button › Controls). `TalkInIsland.start()` (`DoddyApp/Features/Voice/`) starts
  the conversation with the greeting and `withoutOpeningApp`, after the checks that need no screen:
  voice available, the Face ID lock off, Live Activities on, the microphone already allowed, voice
  signed in (or the Debug connection) with the voice data notice accepted. A refusal is one sentence
  saying what to open; nothing starts. It requires the iPhone unlocked (the conversation has your
  notes). It is not an App Shortcut: the App Shortcuts list can't hold an iOS 18 intent in an app
  that still runs on iOS 17 (reported crash on iOS 17 with `if #available` in the builder).
- **Before connecting,** a start without opening checks that the island is really up (iOS stops a
  recording started this way without one) and takes the audio session with the conversation's own
  settings. If iOS refuses, the conversation fails with "iOS didn't let Doddy start the microphone
  without opening him…" instead of connecting deaf. Console, `com.bienos.doddy2.dev` / `voice-audio`:
  "audio session taken without opening" or "…refused…, code N".
- **The island opens up when Doddy starts speaking** (`IslandExpansion`, DoddyCore): his first
  words, then the start of each answer to something you said, never twice in one answer, not within
  20 s of the last (each plays the alert sound), never while Doddy is on screen, not while
  translating, and never with Settings › Back Tap and Siri › "Small island". This applies to every
  conversation, so one started in the app opens up too once you leave it.
- **The greeting stays while he says it:** "Hey Pat, what's up?" and the wave, instead of
  "Speaking" and the shrug, until you first speak.
- **Tapping the island** (or the Open pill) brings Doddy forward with the conversation's screen,
  which takes the running conversation (`ShortcutRouter.showConversationStartedElsewhere`); with the
  Face ID lock, after the unlock.

**On the iPhone (owner).**
1. Open Doddy once and start a conversation from Home, so voice is set up and the microphone allowed.
2. iPhone Settings › Doddy › Live Activities: on.
3. Settings › Action Button › swipe to **Controls** › tap the control under it › search "Doddy" ›
   **Talk in the Island**. (iOS fires the Action Button on its own short press-and-hold; that is
   iOS's, not Doddy's. Let go and talk: there is nothing to hold while you speak.)
4. Press it from the Home Screen or another app: Doddy should say "Hey Pat, what's up?" with the
   big island open, then you ask and he answers, with the island opening again as he answers.

**Device checks, not run.** On an iPhone 15 Pro or later, iOS 18 or later:
- A. Doddy not running (swiped away): press the Action Button. Pass: island appears, opens up with
  "Hey Pat, what's up?" and the wave, Doddy speaks it, hears a question and answers. If the
  microphone is refused, the Console line above says "refused" with its code: that is iOS's rule,
  and "Talk to Doddy" (which opens the app) is the fallback.
- B. Doddy in the background after an earlier conversation: the same.
- C. Two minutes in another app: the island stays; it opens up at each answer, at most every 20 s.
- D. Tap the island: Doddy opens on the conversation; Close ends it.
- E. "Small island" in Settings: the island never opens up by itself.
- F. Live Activities off, or Face ID lock on: the press says why and nothing starts (no microphone dot).
- G. Locked iPhone: iOS asks to unlock before Doddy starts.
- H. The alert sound while Doddy listens: check it doesn't cut into his answer (the provider hears
  it as speech). If it does, keep only the greeting's opening (one line in `IslandExpansion`).
- I. The free (Personal) team build, `make project-iphone`: Live Activities need no entitlement, so
  the island and the control should work there too; check it.

**Verified on Linux (20 Oct).** Swift 6.1.2: DoddyCore `swift test` 1273 tests, 0 failures (6 new
`IslandExpansionTests`); `scripts/check_island_art.sh` PASS (new checks: greeting while speaking,
wave while saying it); `scripts/typecheck_app_logic.sh` PASS (25 files, incl. `ShortcutRouter` and
`VoiceConfig`); capability guard, platform specs and string catalogs PASS; `swiftc -parse` on every
edited Swift file. **App, widget extension, intent and control not compiled (no Xcode); nothing run
on a simulator or device.** The new `IslandBaselineTests` case needs a simulator.

| Rule | What enforces it here | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-08 verified_status_and_receipts | A start without opening proceeds only if `Activity.request` returned an activity and iOS gave the audio session; otherwise it fails with what to do | Linux checks above | Whether iOS allows the background microphone is unknown until check A |
| DOD-11 observable_privacy | `.requiresAuthentication`; refused while the Face ID lock is on; island and alert carry the status and greeting only; logs name the check and an error code only | Guard PASS | The greeting's name shows on the Lock Screen, as before |
| DOD-07 scoped_action_approval | The control starts a conversation only; cards still wait for a tap in the app | — | — |
| Honest capability claims | This section says "not run" for every device behaviour | — | Don't call the Action Button path working until check A passes |
