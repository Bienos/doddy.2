# Device test script — six features built on Linux (2026-10-10)

One pass, in order, for branch `claude/sleepy-gates-f9najr`. Everything here was written and tested only on Linux
(`scripts/ci.sh --core-only`: 454 DoddyCore package tests, 123 backend tests, all pass). **None of it has been
compiled with Xcode or run on an iPhone.** Each step names the checklist rows in
`MAC_VERIFICATION_CHECKLIST_2026-10-10.md`, where the full expected results are.

| Feature | Decision | Checklist rows |
|---|---|---|
| Find by meaning | ADR-210 | M12–M16 |
| "Worth keeping?" after a conversation | ADR-211 | V8–V10 |
| Morning brief | ADR-212 | B1–B7 |
| Brief: news, Todoist, Gmail, choosing contents | ADR-213 | B8–B11 |
| Siri reads a note back | ADR-214 | S7–S11 |
| Widgets | ADR-215 | W1–W7 |

**Time:** about 90 minutes, plus fixing whatever doesn't compile. **You need:** a Mac with Xcode and XcodeGen, an
iPhone on iOS 17 or later (iOS 18 for the controls) with a cable, the iPhone online, and for step 6 a paid team that
can register an App Group. Use synthetic notes only, never real codes or addresses.

Stop at the first step that fails and send back what the results section asks for. A later step built on a broken
one tells us nothing.

---

## Step 0 — Record the setup (2 min)
Fill in the top of the results table: commit (`git rev-parse --short HEAD`), Xcode version, iOS version, device model.

## Step 1 — Build, default settings (10–30 min)
1. `git checkout claude/sleepy-gates-f9najr && git pull`
2. `make project` (XcodeGen), then `scripts/ci.sh` (the full run, not `--core-only`). Save the whole output.
3. If it doesn't compile, these are the new places most likely to need a small fix. Fix it, note file, line and
   error, and go on.
   - `DoddyApp/Infrastructure/OnDeviceMeaningEmbedder.swift`: `NLContextualEmbedding(script:)`, the `requestAssets`
     callback, `enumerateTokenVectors` closure types, and Swift 6 rules for a non-Sendable model held by an actor.
   - `DoddyApp/Features/Voice/VoiceView.swift` (`saveSuggestionsCard`): `case .offered where …, .saving:` in a view
     `switch`. `VoiceSessionController.swift`: `if case … { text } else { nil }` inside `compactMap`.
   - `DoddyApp/Features/Memories/FindMemoriesView.swift`: `let` statements inside the `@ViewBuilder` `wordMatches`.
   - `DoddyApp/Features/MorningBrief/*`: `async let` with conditional values (`MorningBriefOnlineCache.fetch`), the
     `compose` closure in `MorningBriefCard.load`, `Link { Label }`.
   - `DoddyApp/Features/Voice/BriefSpeaker.swift`: `@Observable` on an `NSObject` subclass with `nonisolated`
     delegate methods.
   - `DoddyApp/Intents/AskDoddyNoteIntent.swift`: `authenticationPolicy`, `.result(dialog: "\(answer)")`,
     `some IntentResult & ProvidesDialog`.
   - `DoddyWidgets/DoddyHomeWidgets.swift`: `Button(intent:)` with a generic `some AppIntent` parameter,
     `containerBackground(for: .widget) { AccessoryWidgetBackground() }`, `Text("… \(date, style: .time)")`,
     `.redacted(reason: flag ? .placeholder : [])`. The extension now links DoddyCore (`project.yml`).
   - The older list in the checklist's section 1 still applies.
4. Unit and UI tests run as part of `scripts/ci.sh`. Note any failure by name.

**Pass:** app and widget extension build; unit and UI tests pass, or every failure is written down.

## Step 2 — Does find by meaning find the right notes? (10 min) — M12
Run `MeaningSearchCalibrationTests` on the iPhone (Xcode → Test, with the device selected). If it skips because the
model isn't there, stay online, open Doddy once, wait a minute and run it again. **Copy every `[calibration]` line**
into the results: they set the thresholds.

**Pass:** top-1 at least 6 of 8, wrong offers at most 4.

## Step 3 — Memories and find by meaning on the iPhone (10 min) — M13–M16
Install the app on the iPhone. Save the 12 synthetic notes from `MeaningSearchCalibrationTests` (copy them from the
test file). Then M13 (Find "japanese food" → MAYBE RELATED), M15 (switch off, then on), M16 (time the first and second
search; with 200+ notes if you have time, otherwise note the count).

## Step 4 — Voice: suggestions after a conversation (15 min) — V8–V10, then M14
Needs a working voice setup (token server or debug agent). Follow V8, V9 and V10. Then M14: ask Doddy by voice
"where should we go for japanese food?" and note whether he says "might be".
Note in the results how ElevenLabs punctuates and capitalises your Polish and English: the suggestion rules depend on it.

## Step 5 — Morning brief, local (15 min) — B1–B7
Turn on Calendar and Reminders in Settings → Connections first, with a timed event, an all-day event, a reminder from
yesterday and a note reminder later today. Set the brief 2 minutes ahead and follow B1–B7. B2 needs the iPhone locked
when the time comes.

## Step 6 — Siri (10 min) — S7–S11
Follow S7–S11. Do S8 with the iPhone locked. For S11, restart the iPhone, unlock, and ask Siri straight away.

## Step 7 — Widgets without, then with, the App Group (20 min) — W1, then W2–W7
1. With the build from step 1 (no App Group): W1.
2. Rebuild with the App Group (`BUILD_AND_TEST.md` → "Note widgets need an App Group"), reinstall, then W7 first
   (add a note widget before opening Doddy), then W2–W6.

## Step 8 — Brief with news, Todoist and Gmail (15 min, optional today) — B8–B11
Needs a Doddy backend **with this branch's change** (mock mode is enough: `npm run dev` in `backend/`, see
`BUILD_AND_TEST.md` → Connected Apps) and, for B11, the messaging server with a digest from today. A deployed backend
without this branch shows "an older version that can't list them here"; that is expected until it is redeployed.

---

## Results (copy this table into your reply)
| Step / row | Result (pass / fail / skipped) | Notes (error text, timing, what you saw) |
|---|---|---|
| Setup | | commit: · Xcode: · iOS: · device: |
| 1 Build (app) | | |
| 1 Build (widgets) | | |
| 1 Unit + UI tests | | |
| M12 calibration | | paste the `[calibration]` lines |
| M13 | | |
| M14 | | |
| M15 | | |
| M16 | | first search: … s · second: … s · notes: … |
| V8 | | |
| V9 | | |
| V10 | | how transcripts look |
| B1 | | |
| B2 | | |
| B3 | | |
| B4 | | |
| B5 | | |
| B6 | | |
| B7 | | |
| S7 | | |
| S8 | | |
| S9 | | |
| S10 | | |
| S11 | | time to answer: … s |
| W1 | | |
| W7 | | |
| W2 | | |
| W3 | | |
| W4 | | |
| W5 | | |
| W6 | | |
| B8 | | |
| B9 | | |
| B10 | | |
| B11 | | |

**Send back:** this table, the full `scripts/ci.sh` output from step 1 (or at least every `error:` line), any fixes you
made (file, line, change), and screenshots of anything that looks wrong. Nothing in this script sends real data
anywhere beyond what the features already do; use synthetic notes throughout.
