# Paste this entire prompt into Claude Code opened at the `Bienos/doddy.2` root ON A MAC WITH XCODE

You are the lead Apple-platforms engineer for DODDY V2. The goal is to take the code that already exists for iPhone, iPad and Apple Watch, compile it, run it on simulators and fix what breaks. After that you do an iPad layout pass and a Mac spike. Most of this code was written on Linux and **has never been compiled**. Your job is to make it real, prove it, and report honestly. It is not a rewrite.

Work through the five phases below **in order**. Each phase has a gate. Don't start a phase until the one before it has passed. If a gate can't be passed, stop and report.

## Mandatory first steps

1. Print `pwd`, `git remote -v`, `git branch --show-current`, `git status --short`, `sw_vers`, `xcodebuild -version`, `swift --version`, `xcodegen --version`, and `xcrun simctl list devices available`.
   - **STOP** if this is not `Bienos/doddy.2`, if the working tree has changes you didn't make, or if `xcodebuild` is missing.
   - Without Xcode none of this work can be verified. Report every phase as **BLOCKED / NOT RUN** and change nothing.
2. Create a working branch from the current default branch, for example `apple-platforms/<date>`. Commit in small units, one or more per phase. Don't push to the default branch, and don't open a PR unless the owner asks.
3. Read these before changing anything:
   - `CLAUDE.md` and `AGENTS.md` (the constitution section), plus `docs/trust/REPO_ALIGNMENT.md`;
   - `DECISIONS.md`, especially ADR-013, 123, 137, 232, 262, 287 and 337;
   - `docs/implementation/FIRST_BUILD_GUIDE.md`, the whole file. Its "most likely to need a fix" lists are your compile-error map;
   - `docs/implementation/MAC_VERIFICATION_CHECKLIST_2026-10-10.md`;
   - `docs/implementation/APPLE_WATCH_STATUS.md` and `docs/implementation/WATCH_COMPLICATIONS_STATUS.md`;
   - `docs/design/CANONICAL_DESIGN_DIRECTION.md` and `docs/design/UPLOADED_MEMORY_ASSETS.md`.

## Ground rules (apply to every phase)

**Scope**
- Fix what is broken. Don't add features beyond what each phase names.
- Compile fixes are minimal: the smallest change that compiles and keeps the behaviour the status doc describes.

**Tests**
- Never skip, disable, or weaken a test, or change its expected value, to get green.
- If a test is wrong, say why in the report and in an ADR, and fix it on its own.

**Honest reporting**
- **PASS** means you ran it and saw it pass. **NOT RUN** means you didn't run it.
- **Simulator only** means it isn't proven on a device.
- Never write "works on Apple Watch" or "works on iPad" from a simulator alone. The microphone, Back Tap, Dynamic Island, real watch faces, Always On and dictation stay **NOT RUN** until someone checks them on a device.

**Art and fonts**
- Doddy art comes **only** from the owner's imported pack: the `UploadedDoddy_*` and `WholeDoddy_*` image sets. See `CLAUDE.md` under "Character art".
- A pose that isn't imported yet becomes an owner decision. Never draw, generate, or borrow one from `design/interface-v1.2/assets`, `design/ios-ready-asset-catalog` or `assets/brand_candidate`.
- Don't add font binaries.

**Signing and secrets**
- Don't commit a team ID, provisioning profile, certificate, API key or `.xcodeproj`. ADR-013 still holds: the project is generated from `project.yml`.

**Constitution**
- Every "Saved", "Ticked" or "Done" the user sees still comes only from a read-back or provider answer (DOD-08).
- Nothing new is stored or sent off the device without the existing switches (DOD-11).

**Records**
- New decisions get ADRs numbered from **341** upward in `DECISIONS.md`. Check the highest number first in case it has moved.
- Update the matching status doc in the same commit as the code.

---

## Phase 1: iPhone app builds and its tests pass

The gate for everything else. M1-and-later work is not trustworthy until this passes (see `DECISIONS.md`, the "Run the Mac verification" item).

1. Run `xcodegen generate --spec project.yml`, then `scripts/ci.sh` (the full run, **not** `--core-only`). Save the full output.
2. Fix compile errors one at a time, starting from the risk lists in `FIRST_BUILD_GUIDE.md`. For each fix, record:
   - file and line;
   - the compiler error;
   - what you changed.
3. Expect build failures from the watch and widget targets too, because the app embeds them. Fix them here as well, but only enough to compile. Behaviour checks belong to Phase 3.
4. Run the unit and UI tests on an iPhone simulator until they pass.
5. Work through `MAC_VERIFICATION_CHECKLIST_2026-10-10.md`. Tick only what a simulator can prove. Mark everything else **Device needed**.

**Gate:**
- `scripts/ci.sh` ends in PASS on an iPhone simulator;
- the checklist table is filled in with the Xcode version and simulator name;
- `FIRST_BUILD_GUIDE.md` says the first build is no longer BLOCKED.

If it can't get green, stop here and report.

## Phase 2: the same app on iPad (ADR-337, as built)

No redesign in this phase. Prove that the iPad support already declared works.

1. Run the tests on iPad simulators: `DODDY_DESTINATION='platform=iOS Simulator,name=<iPad>' scripts/ci.sh`.
   - Cover at least the smallest current iPad mini, an 11-inch iPad Air and a 13-inch iPad Pro.
   - If `scripts/ci.sh` doesn't honour `DODDY_DESTINATION`, fix the script; don't work around it.
2. On each iPad, take screenshots of every tab in:
   - portrait and landscape;
   - Split View at about 1/3 and 1/2 width;
   - Slide Over.

   Put them under `VISUAL_REVIEW/ipad/` and check them in.
3. Check what ADR-337 claims:
   - one readable column, capped at 760 pt, on regular width;
   - full width on compact width (Split View and Slide Over);
   - Back Tap setup hidden;
   - every orientation allowed;
   - the widget and share extension still build for iPad.
4. Fix only real breakage: clipped or overlapping content, unreachable buttons, broken sheets or popovers, or layout that doesn't recover after resizing. Don't change the iPhone layout. The iPhone UI tests must still pass.
5. Add one UI test that launches on iPad and checks the Back Tap row is absent.

**Gate:**
- tests pass on all three iPads;
- the screenshots are committed;
- ADR-337's status changes from "NOT RUN" to the evidence you have.

## Phase 3: Apple Watch app and complications (ADR-232, 262, 287, as built)

There's no new watch features in this phase. Make the existing watch app compile, run and behave as its status docs say.

1. Build the `DoddyWatch` scheme for a watchOS simulator.
   - Then run the iPhone app with a **paired** iPhone + Apple Watch simulator.
   - Check that "Embed Watch Content" actually puts the watch app inside the iPhone app, and that the companion bundle id is accepted.
   - If XcodeGen can't express something, fix it in `project.yml` and record the reason in an ADR.
2. Check on the paired simulators, and record the result of each:
   - Settings › Apple Watch appears only while a watch is paired. Turning it off sends an empty snapshot, and the watch explains how to turn it back on.
   - Pinned notes, the next 3 reminders and the lists show on the watch, with "As of HH:MM on your iPhone". Reminder text shows only when the notification-text setting is on.
   - Tick an item: the reply comes from the iPhone's read-back. A list changed on the iPhone gives "Nothing was changed".
   - Add an item to a list, including too long, duplicate and list-full cases.
   - Save a typed note on the watch.
   - With the iPhone app unreachable, nothing is queued and the watch says so. A sent request with no answer is never shown as done.
3. Complications (`DoddyWatchWidgets`): add each family (circular, corner, inline, rectangular) to a simulator watch face.
   - Take screenshots at the current 41/42 mm, 45/46 mm and 49 mm (Ultra) sizes, in normal and Always On dimming.
   - Put them under `VISUAL_REVIEW/watch/`.
   - Confirm no note or list-item text appears on any face. `ComplicationContent` must carry only times, counts and list names.
   - Without the App Group entitlement, the complication must say "Open Doddy on your iPhone."
4. Two gaps from `APPLE_WATCH_STATUS.md`:
   - **App icon:** only from the owner's pack. If no suitable imported pose exists, list "watch app icon: owner to pick a pose from the pack" as a decision. Don't make one.
   - **Polish catalog:** if the repo's existing catalog generator supports the watch app, use it to add the watch app's own Polish strings. If it doesn't, list it as a gap.
5. Leave these as **Device needed**:
   - real WatchConnectivity delivery while the iPhone app is in the background;
   - watchOS dictation (including Polish);
   - real watch faces and Always On;
   - whether the Smart Stack raises the widget before a reminder.

**Gate:**
- the watch app builds and is embedded in the iPhone build;
- every check in step 2 has a recorded result;
- `WatchLinkTests`, `WatchListAddTests` and `WatchComplicationTests` still pass;
- both watch status docs are updated with what was proven and what is still NOT RUN.

## Phase 4: iPad layout pass (owner decision first)

There are no iPad mockups in `design/`, so the layout direction belongs to the owner. **Before writing any layout code:**

1. Using the Phase 2 screenshots, show the owner two or three options, each with a sketch or screenshot and its trade-offs. For example:
   - **A.** Keep the single 760 pt column (no change).
   - **B.** Use `NavigationSplitView` on regular width only: the tabs or lists in a sidebar, the chosen note or list in the detail pane.
   - **C.** Use two columns on the Memories tab only. Everything else stays one column.
2. Ask the owner which one, with `AskUserQuestion`. **If there's no answer, skip this phase**, record it as an open decision and go on to Phase 5.
3. Build only the chosen option, switched on `horizontalSizeClass == .regular`, so iPhone and compact iPad layouts are unchanged.
   - Keep Dynamic Type, VoiceOver order, Reduce Motion and keyboard focus working.
   - Keep using the existing design tokens.
4. Prove it:
   - iPhone UI tests unchanged and passing;
   - new iPad UI tests for the chosen layout;
   - fresh screenshots in `VISUAL_REVIEW/ipad/` at every size from Phase 2, including Split View resizing back to compact.

**Gate:** the owner's choice is recorded in an ADR, the tests pass on iPhone and iPad, and the screenshots are committed.

## Phase 5: Mac spike (report only, don't ship)

The Mac has three possible routes. Measure the first two, then recommend one to the owner. Do the work on a separate branch, `apple-platforms/mac-spike`.

1. **Designed for iPad on Apple silicon** (no code change):
   - Run the app with the `My Mac (Designed for iPad)` destination.
   - Record what works and what doesn't. Expect the microphone path, Live Activities, the Dynamic Island, Back Tap, widgets placement, the watch and location to differ.
   - Take screenshots for `VISUAL_REVIEW/mac/`.
2. **Mac Catalyst**:
   - Turn on `SUPPORTS_MACCATALYST` for the **app target only** in `project.yml`.
   - Gate frameworks Catalyst lacks or that make no sense on a Mac behind `#if targetEnvironment(macCatalyst)` or the existing `DeviceSupport` checks. These include ActivityKit and the island, AlarmKit, WatchConnectivity, Back Tap and Picovoice. LiveKit, ElevenLabs and Picovoice Catalyst support must be checked, not assumed.
   - Each gated feature shows an honest "Not available on Mac" row instead of disappearing or pretending.
   - Note the sandbox entitlements the microphone would need. Don't add a signing team.
   - Build it, run the unit tests on the `macCatalyst` destination, and take screenshots.
3. **Native macOS app**: don't build it. Estimate it only. `DoddyCore` already declares macOS 14. List what new UI it would need.
4. Write `docs/implementation/MAC_SPIKE_REPORT.md`. Include:
   - what each route ran;
   - a feature-by-feature works / differs / unavailable table;
   - privacy differences (microphone, files, iCloud, where the database lives);
   - rough cost;
   - your recommendation.

   The choice is the owner's. Merge nothing from the spike branch without their approval.

**Gate:** the report and screenshots are committed on the spike branch, and the default branch is untouched by Catalyst changes.

---

## Report and stop

At the end, and also at any gate where you stop, report:

1. **Files changed**, per phase, with commit hashes.
2. **What now works**, per platform, each labelled **PASS (simulator)**, **PASS (device)** or **NOT RUN**.
3. **Exact commands run and their results**, including:
   - Xcode version, macOS version and simulator names;
   - every failing, skipped or flaky test, with output.
4. **Every compile fix**, as file, error and change. Put the same list into `FIRST_BUILD_GUIDE.md`.
5. **Device checks still needed**: iPhone, iPad and Apple Watch, as a checklist a person can tick.
6. **Security and privacy risks**: the watch snapshot at rest, complication content on a visible face, and Mac sandbox and microphone.
7. **Decisions for the owner**:
   - the iPad layout choice, if not yet made;
   - the watch app icon pose;
   - which Mac route to take;
   - signing team and bundle ids;
   - whether to commit the generated project (ADR-013).
8. **Constitution evidence log**: rule IDs, the enforcing code, tests run, gaps, and claims to limit.
9. **Recommended next step.**

Then **stop**. Don't start new features, App Store submission, TestFlight, paid services or a native macOS app without a new instruction.
