# Prompt: build Doddy on the Mac and get it onto the owner's iPhone for testing

Written 2026-10-13 for a Claude Code session running **on the owner's Mac with Xcode 26**, in a clone of
`Bienos/doddy.2`. Copy everything below the line into that session.

---

You are working in the repository `Bienos/doddy.2` on my Mac. Read `CLAUDE.md`, then `STATUS.md`, then
`docs/implementation/RUN_ON_YOUR_IPHONE.md`. Those three pages are the rules and the current state; don't read
the rest of `docs/` unless a step below sends you there.

## Goal
Get the integration branch **`claude/zealous-albattani-7ay32v`** built with Xcode and installed on my iPhone so I
can start testing, and tell me exactly what works, what doesn't, and what you had to change. That branch is the
default branch (`claude/loving-dirac-uuxoux` at `e2734941`) plus four merges: the app icon, the island's round
faces, the "Big brain. Small body." share card, and the voice screen with Doddy and a sound wave. `STATUS.md`,
section "Integration branch for device testing", says what was checked on it and gives the hosted CI run.

## Ground rules (they override your habits)
- Work only on `claude/zealous-albattani-7ay32v`. Never push to another branch, never merge into the default
  branch, never open a pull request: those are my decisions after I've talked to Doddy on the phone.
- Change code only to make this branch build and its tests pass. No new features, no refactors, no skipped,
  disabled or quarantined tests. Keep each fix minimal and commit it on its own with a message that says what
  failed and why the fix is right.
- Never claim something was built, run or seen working unless you ran it and have the output. "Not run" is a
  fine answer; a guessed "passed" is not.
- Never commit a signing team, a bundle ID change, an access code, an API key or a `.ppn` file. The codes you
  need are in my Render dashboard; ask me for them, don't guess them, and type them into the app's Settings
  only.
- Don't touch the live ElevenLabs agent or any server. The app's voice runs on OpenAI Realtime by default and
  takes its prompt from the bundled `voice-agent/instructions.md`; the ElevenLabs agent is mine to change.
- Say in one line what you're about to do before each step, and keep going until the app is on the phone or
  you're blocked on something only I can do.

## Steps

1. **Inventory first.** Report: `xcodebuild -version`, `swift --version`, `xcodegen --version` (install with
   `brew install xcodegen` if missing), `git status`, `git branch --show-current`, and whether an iPhone is
   connected (`xcrun devicectl list devices`). Xcode 26 is required (CI uses 26.6; alarms use AlarmKit).

2. **Get the branch.**
   ```sh
   git fetch origin
   git checkout claude/zealous-albattani-7ay32v
   git pull --ff-only origin claude/zealous-albattani-7ay32v
   make project            # xcodegen generate --spec project.yml -> Doddy.xcodeproj (the shipping project, Watch app embedded)
   xcodebuild -list -project Doddy.xcodeproj
   ```
   If `make project` fails, use `make project-iphone` (same app, no Watch app) and say so.

3. **Build for the simulator before the phone**, so a compile error is separated from a signing problem:
   ```sh
   xcodebuild build -project Doddy.xcodeproj -scheme Doddy \
     -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tee /tmp/doddy-build.log | tail -40
   ```
   (Use any installed iPhone simulator name from `xcrun simctl list devices available`.) If it fails: read the
   first errors, fix them minimally on this branch, commit, rebuild. Tell me each error and each fix. The four
   merges that were never compiled before CI are the voice wave (`DoddyApp/Features/Voice/VoiceView.swift`,
   `VoiceWaveView.swift`, `VoiceLevelMeter.swift`, `Shared/IslandArt/IslandPose.swift`) and the island faces
   (`Shared/IslandArt/IslandViews.swift`), so look there first. If the voice wave cannot be made to compile
   within a few small fixes, revert its merge commit (`git revert -m 1 c5462570`) and tell me; the rest of the
   branch doesn't depend on it.

4. **Run the tests the way CI does**, then paste the summary lines (passed, failed, skipped), not the whole log:
   ```sh
   scripts/ci.sh            # Linux-safe checks + xcodebuild test (unit + UI) on the first available simulator
   ```
   A failing test is a failing test: fix the cause or tell me what fails and why, with the assertion text.

5. **Put it on my iPhone.** Open `Doddy.xcodeproj` in Xcode. Signing: click the blue Doddy project, and for
   each of the targets **Doddy, DoddyWidgets, DoddyShare, DoddyWatch, DoddyWatchWidgets** open
   *Signing & Capabilities* and choose my team, leaving "Automatically manage signing" on (it registers the app
   IDs and the App Group `group.com.bienos.doddy2.dev`). I'll be at the Mac for this; tell me when you need me
   to click. `make project` rewrites the project file, so the team has to be chosen again after it. Then:
   iPhone plugged in and trusted, Settings → Privacy & Security → Developer Mode on, choose the iPhone at the
   top of Xcode, Product → Run. If you'd rather do it from the terminal:
   ```sh
   xcodebuild build -project Doddy.xcodeproj -scheme Doddy -destination 'platform=iOS,name=<my iPhone's name>' \
     -allowProvisioningUpdates 2>&1 | tail -30
   ```
   The bundle ID stays the development placeholder `com.bienos.doddy2.dev`. Don't change it.

6. **Point the app at its servers** (the app ships with no addresses). In the app's Settings, type:

   | Settings section | Field | Value |
   | --- | --- | --- |
   | Voice | Token server | `https://doddy-voice-token.onrender.com/api/voice-token` |
   | Voice | Access code | one of `DODDY_ACCESS_CODES` on Render → doddy-voice-token → Environment (ask me) |
   | Ask Doddy | Gateway address | `https://doddy-gateway.onrender.com` |
   | Ask Doddy | Invite code | one of `GATEWAY_INVITE_CODES` on Render → doddy-gateway → Environment (ask me) |
   | Connected Apps server (development) | Server address | `https://doddy-yaci.onrender.com` |
   | Messages from Doddy | Server (development) | `https://doddy-messaging-zw1n.onrender.com` |

   All four are on Render's free plan: the first request after about 15 idle minutes takes 30 to 60 seconds,
   and the app waits 15 seconds for a voice pass, so the first voice start after a quiet spell can fail; try
   again a minute later. With the token server field empty the app uses ElevenLabs' development agent directly.

7. **First tests, in this order**, and write each result into the **Result log** of
   `docs/implementation/MAC_VERIFICATION_CHECKLIST_2026-10-10.md` (Xcode version, iPhone and iOS version, what
   happened). A feature counts as "seen working" only from that log.
   1. The introduction and Home's first visit (checklist 4t, 4p, 4r, 4s), then one real conversation on the
      default voice: save a note by voice, ask for it back (section 5).
   2. The new voice screen: Doddy and the sound wave, the status line under them, "Show transcript" shows the
      words and "Hide transcript" hides them, the wave moves when I speak and when Doddy speaks (ADR-463, 464).
      With Reduce Motion on, the bars stand still.
   3. The Dynamic Island compact and minimal views show a round face (checklist W3).
   4. Settings: the "Big brain. Small body." card appears and can be shared (ADR-462), and the app icon on the
      Home Screen is Doddy from my pack (ADR-460).
   5. Then the rest: sections 1, 2, 3, 4, 4b, 5, 6 and the 13 October features 4o to 4s (action status, session
      recovery, Stop listening, unfinished notes, Listen until I finish), 4u ("Hey Doddy", which needs a `.ppn`
      keyword file picked in Settings and my Picovoice AccessKey; skip if I haven't given them), 4v ("Ask me
      about it"), 4q (the guided first conversation).
   If a conversation won't start, look at `docs/platforms/iphone.md`, "To debug a voice problem", before
   changing anything, and show me the first lines of the Xcode console around the failure.

8. **Commit and push** every fix and the filled-in Result log to `claude/zealous-albattani-7ay32v`
   (`git push -u origin claude/zealous-albattani-7ay32v`). Don't commit `Doddy.xcodeproj` (it's generated) unless
   I say so.

9. **Report**, in this shape and nothing else: files changed; what was seen working on the phone (from the log);
   what was not run or not seen; the exact test commands and their summary lines; failures with their text;
   privacy or security risks you noticed; decisions only I can make; and the next thing you recommend. Then
   stop. Merging into the default branch, closing PR #67 and #48, and anything with the live agent are mine.
