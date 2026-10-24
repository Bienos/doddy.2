# Sport mode: status

Research and the owner's choices: `docs/research/2026-10-24/research_sport_mode.md`, ADR-620 (start with Apple Health, the Apple Watch and voice; health data leaves the iPhone only as a short summary after consent; food tips by default, counting only on request). This page tracks what is built.

## Step 1: Apple Health, read and shown on the iPhone (ADR-621)

Owner, 24 Oct 2026: "Start" (typed "Stary"), after the research's order of work. Branch `claude/sport-mode-health`, not merged.

**What it does.** Settings › Connections › Sport and health › **Apple Health**. The screen says what Doddy may read, that nothing leaves the phone, and how to stop it in the Health app. **Turn on Apple Health** shows iOS's Health sheet (read only), then the screen shows what Doddy sees for the last 7 days:

- each workout: kind, day and time, distance, time, pace (running, walking, hiking), average heart rate, active calories;
- last night's sleep: time asleep and, when a watch recorded them, deep, REM and core;
- resting heart rate and heart rate variability: the newest reading and the 7-day average;
- VO₂ max: the newest reading of the last 90 days.

**What it does not do.** Nothing read from Health is sent anywhere, spoken, put in a conversation, or saved by Doddy. No voice tool, no Claude, no write to Health, no background reading, no routes, no clinical records. Turn off stops Doddy reading; only the Health app can take the permission back, and the screen says so.

| Part | File | Checked |
|---|---|---|
| Rules: 7-day window, the night (18:00 to 12:00), workouts in the window, pace only for running/walking/hiking of 100 m or more, sleep added up without counting a minute twice (staged sleep wins over unstaged, deep over REM over core), the week's average as an average of daily averages, runner's clock format | `Packages/DoddyCore/Sources/DoddyCore/HealthGlance.swift` | `HealthGlanceTests`, 13 tests, Linux, Swift 6.1.2. The staged-sleep rule was broken on purpose: 2 tests failed, then it was restored |
| HealthKit reads (the only file that imports HealthKit) | `DoddyApp/Infrastructure/Health/HealthReader.swift` | **NOT COMPILED** (no Xcode here) |
| The screen and the card in Connections | `DoddyApp/Features/Health/HealthConnectionView.swift`, `Features/Connections/ConnectionsView.swift` | **NOT COMPILED** |
| HealthKit entitlement | `Config/Doddy-*AppGroup*.entitlements` (shipping project); `Config/DoddyiPhone-HealthKit.entitlements` (free-team project, HealthKit only) | `check_platform_specs.py` PASS; signing with a Personal team **not tried** |
| Health permission prompt in ten languages; the Motion & Fitness prompt no longer says Doddy reads nothing from Health | `project.yml`, `l10n/*_infoplist.json` | `build_strings_catalog.py --check` PASS; the nine translations are machine drafts |
| 40 Polish screen lines | `l10n/pl.json` | same check PASS; other languages show English |
| Guard: HealthKit only in `HealthReader.swift`; no write prompt, save or delete, clinical records, background delivery or workout sessions | `scripts/check_forbidden_capabilities.sh` | PASS; each of the four new rules was broken on purpose and caught |

## Not checked

- **The app has not been compiled with these changes.** The hosted Mac job compiles it on a pull request.
- **Nothing has run on a device:** the Health sheet, the reads, the numbers against the Health app's own, a night recorded by both a watch and the iPhone, an iPhone that is locked while the screen reads (it should say so), iPad.
- **Signing the free-team project with HealthKit.** Apple's capability table lists HealthKit for the free Apple Developer account (read 24 Oct 2026). If Xcode still refuses, set `DODDY_APP_ENTITLEMENTS: ""` in `project-iphone.yml`; the screen then says this build can't use Health.
- No UI test for the new screen yet.

## Privacy and safety

- Health data is special-category data (GDPR Art. 9). In this step it never leaves the iPhone, so no consent beyond iOS's own sheet is asked for. The next step that sends anything (a summary to Claude) needs its own explicit consent screen first (ADR-620; App Review 5.1.2(i)).
- The legal pages (`site/privacy/`) don't mention Health yet; they must before this ships.
- App Review 5.1.3: no Health data for ads, none in iCloud, nothing written to Health.

## Next (each needs the owner's go-ahead)

1. "How did it go?" and a weekly summary: the numbers worked out on the iPhone, a consent screen, then a short summary to Claude.
2. Voice gym log and the wger exercise base.
3. Running and strength plans with the safety rules from the research.
