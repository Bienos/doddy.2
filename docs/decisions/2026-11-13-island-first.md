# The Action Button puts the island up first, before anything that waits

- **Date:** 2026-11-13
- **Decided by:** owner (Pat, 13 Nov 2026, with a photo of the small island: Doddy's face and his waves): "action button powinien od razu to pokazywać, tylko szybko żeby było, zależy mi na szybkości, więc trzeba usunąć jakieś rzeczy czy coś, weź zobacz". The change below is the session's reading of that from the code; nothing was seen on a phone.
- **Status:** applied in the pull request of branch `claude/optimistic-keller-4r9elt`. Not verified on a device.
- **Replaces:** nothing. Follows `2026-11-10-action-button-start` and `2026-11-12-action-button-audio-and-island`.

## Why
Read from the code (no phone, no Xcode in the session). Before this change the island was asked for only when the conversation reached its own "Connecting…" (`VoiceSessionController.start`, `phase = .connecting` → `syncIsland` → `Activity.request`). Between the press and that line ran, one after the other:
1. a wait for the notes store, up to 2 s on a cold launch (`IntentStores.waitForStore`, polled every 40 ms);
2. a restore of the older voice login over the network, for those who are not signed in with a Doddy account;
3. the profile read from the database when no screen had loaded it yet (`ProfileStore.load`: two reads, and a write when the onboarding was skipped), which is the usual case when iOS starts Doddy just for the press;
4. a new controller, Home taking hold of it, and a task that runs on the main actor's next turn;
5. inside `start`: the audio-session claim, the one-at-a-time gate, keeping the last conversation's log, resetting several dozen fields, the invoice draft, the learning cards, then an `await` for the microphone permission.

None of these changes what the island shows ("Connecting…"), so the island waited for work it doesn't need. How long that took on a phone is not known: the timing line had no stage for it.

What was kept, and why:
- **The waves are not shown before Doddy hears.** The photo shows the waves, which mean he is listening or speaking. They still come only with the provider's events (constitution: never claim listening before it is true; `IslandScene.voiceSign`). The island shows his face and the three dots while he connects, as before.
- **Unlocking first** (`requiresAuthentication`): the conversation hands the agent the saved notes, so a locked iPhone still asks for Face ID before anything starts.
- **The connect itself** (token, ElevenLabs room, first audio) is unchanged: the token shelf and the network preparation already shorten it, and nothing measured says what else to cut.

## Decision
- `TalkInIsland.start` runs the checks that need only the iPhone first, none of which waits: terms, Face ID lock, Live Activities, microphone, and (for a signed-in Doddy account, which needs no restore) the account and voice-data gate. Then it puts the island up at once as "Connecting…" with the greeting Doddy will open with, as the conversation shows it while it connects (`showIslandFirst`). Only then does it wait for the store, the restore when needed, the profile and the conversation's set-up.
- The conversation takes that island over at its own "Connecting…" (`VoiceLiveActivity.show` updates the activity that is up). Its first update follows at least 0.5 s later (ADR-604's pacing) with the name in the greeting if the profile wasn't loaded yet, and the conversation's own start time.
- Every way out of the press after the island is up (a refusal, a failure before the conversation's "Connecting…", a cancel, the 4 s timeout, a conversation that started meanwhile) ends the island at once unless a conversation is connecting or live (`TalkIslandFirst.afterwards`, DoddyCore). An island the press didn't put up (one already showing, or one iOS refused) is never ended by it; if iOS refuses it, the conversation asks again and says so as before.
- The "Open Doddy faster" bookkeeping (`noteShortcutRan`) moves after the island.
- The timing line gains a first stage, `island shown`: `talk start timing: island shown 0.03 s · account … · profile … · island … · connect … · total …`.
- `VoiceSessionController.swift` and `VoiceLiveActivity.swift` are not changed.

## Consequences
- The island should come up as soon as iOS hands the press to Doddy, instead of after the store, the profile and the set-up. On a cold launch the app's own start (`DoddyApp.init`) still runs first; that is the next thing to measure if the island is still late.
- A press refused after the island is up (no notes store, voice not available in this build, an older voice login that can't be restored) shows the island for a moment and then says why, as before. With a Doddy account every common refusal is checked before the island.
- One more Live Activity update per start (the conversation's state after the press's). Nothing new is shown on the Lock Screen: the same "Connecting…" and greeting as before, a moment earlier.

## How to read the log
Console.app, subsystem `com.bienos.doddy2.dev`, category `voice-audio`, one press:
- `talk in the island: island shown before the set-up` (or `refused by iOS`);
- `talk start timing: island shown … · account … · profile … · island … · connect … · total …`. `island shown` is the time from the intent's `perform()` starting to the island, not from the press: loading the app comes before it, see the launch line below; the old `island` stage is now the time until the audio session is up;
- after a refused press: `talk in the island: the press's island was ended, no conversation took it over`.

## Evidence
- `make test-core` with Swift 6.1.2 on Linux (Ubuntu 24.04): 3150 tests, 0 failures, including the new `TalkStartRulesTests` (2) and `VoiceStartTimelineTests` (1) cases and the updated stage-word test.
- `scripts/ci.sh --only checks`: every check PASS; "Studio skills: renderers on samples" NOT RUN (no reportlab or matplotlib here), so the group reports BLOCKED.
- `swiftc -parse` on `TalkInIsland.swift`: syntax only.
- **The app is not compiled here** (no Xcode); the hosted Mac job builds it. Nothing was seen on a phone.

## Follow-up: the launch line (13 Nov 2026)
The start timeline begins when the intent's `perform()` runs, so it cannot see the time iOS needs to start Doddy for a press (loading the libraries, `DoddyApp.init`). A second line says it: `talk start launch: process age 1.20 s (fresh launch) · before app init 0.60 s · app init 0.15 s`. `process age` is the time from the process's start (the kernel's own record) to the press; under 15 s it counts as a fresh launch, and then it is split into the time before `DoddyApp.init` began and `init` itself. For a process that was already running it says only its age (`already running`). Logging only, fixed words and seconds (`TalkLaunchTiming`, DoddyCore; `LaunchWork.launchTiming`, `ProcessStart`). Reading both lines after one press: if `process age` of a fresh launch is large and `island shown` small, the delay is iOS loading the app, not the start; if `before app init` dominates, it is loading the libraries; if `app init` does, it is the work in `init`.
