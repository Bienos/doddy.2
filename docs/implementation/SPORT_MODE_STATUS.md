# Sport mode: status

Research and the owner's choices: `docs/research/2026-10-24/research_sport_mode.md`, ADR-620 (start with Apple Health, the Apple Watch and voice; health data leaves the iPhone only as a short summary after consent; food tips by default, counting only on request). This page tracks what is built.

## Step 1: Apple Health, read and shown on the iPhone (ADR-621)

Owner, 24 Oct 2026: "Start" (typed "Stary"), after the research's order of work. Branch `claude/sport-mode-health`, not merged.

**What it does.** Settings › Connections › Sport and health › **Apple Health**. The screen says what Doddy may read, that nothing leaves the phone, and how to stop it in the Health app. **Turn on Apple Health** shows iOS's Health sheet (read only), then the screen shows what Doddy sees for the last 7 days:

- each workout: kind, day and time, distance, time, pace (running, walking, hiking), average heart rate, active calories;
- last night's sleep: time asleep and, when a watch recorded them, deep, REM and core;
- resting heart rate and heart rate variability: the newest reading and the 7-day average;
- VO₂ max: the newest reading of the last 90 days.

**What it does not do.** Nothing read from Health is sent anywhere, spoken, put in a conversation, or saved by Doddy (step 2 adds one exception: the week's summary the person sends in Messages). No voice tool, no write to Health, no background reading, no routes, no clinical records. Turn off stops Doddy reading; only the Health app can take the permission back, and the screen says so.

| Part | File | Checked |
|---|---|---|
| Rules: 7-day window, the night (18:00 to 12:00), workouts in the window, pace only for running/walking/hiking of 100 m or more, sleep added up without counting a minute twice (staged sleep wins over unstaged, deep over REM over core), the week's average as an average of daily averages, runner's clock format | `Packages/DoddyCore/Sources/DoddyCore/HealthGlance.swift` | `HealthGlanceTests`, 13 tests, Linux, Swift 6.1.2. The staged-sleep rule was broken on purpose: 2 tests failed, then it was restored |
| HealthKit reads (the only file that imports HealthKit) | `DoddyApp/Infrastructure/Health/HealthReader.swift` | **NOT COMPILED** (no Xcode here) |
| The screen and the card in Connections | `DoddyApp/Features/Health/HealthConnectionView.swift`, `Features/Connections/ConnectionsView.swift` | **NOT COMPILED** |
| HealthKit entitlement | `Config/Doddy-*AppGroup*.entitlements` (shipping project); `Config/DoddyiPhone-HealthKit.entitlements` (free-team project, HealthKit only) | `check_platform_specs.py` PASS; signing with a Personal team **not tried** |
| Health permission prompt in ten languages; the Motion & Fitness prompt no longer says Doddy reads nothing from Health | `project.yml`, `l10n/*_infoplist.json` | `build_strings_catalog.py --check` PASS; the nine translations are machine drafts |
| 40 Polish screen lines | `l10n/pl.json` | same check PASS; other languages show English |
| Guard: HealthKit only in `HealthReader.swift`; no write prompt, save or delete, clinical records, background delivery or workout sessions | `scripts/check_forbidden_capabilities.sh` | PASS; each of the four new rules was broken on purpose and caught |

## Step 2: "How did my week go?" in Messages (ADR-622)

Owner, 24 Oct 2026: "Start". Same branch.

**What it does.** On the Apple Health screen, under what Doddy sees: **Ask Doddy about this week** with the exact text that would go. The first time, a consent sheet says what is sent (only that summary), where (Doddy's server, which keeps counts only, and Claude at Anthropic), that the thread is saved on the iPhone, and how to take it back; **Allow** records the consent's version and time on the iPhone. Then Messages opens with the text in its box. **Nothing is sent until the person taps Send there**; they can change or delete the text first. Claude answers in the thread as for any typed question.

The summary: a question ("How did my week go? … No medical advice, please."), each workout of the last 7 days, the totals of this week and the week before (workouts, time, running distance and average pace), last night's sleep, resting heart rate and HRV with their 7-day averages, VO₂ max. Only numbers the screen shows; nothing else from Health. Over Messages' 2,000-character limit, the oldest workouts are left out and the text says how many.

| Part | File | Checked |
|---|---|---|
| Rules: the previous 7 days, week totals (pace only over runs with a distance), consent version, assembling the text within the limit (oldest workouts first, never a half-cut text) | `Packages/DoddyCore/Sources/DoddyCore/HealthShare.swift`, `HealthGlance.thisWeek` / `previousWeek` | `HealthShareTests`, 8 tests; trimming the newest instead of the oldest was tried on purpose: 2 failures, restored |
| Two weeks of workouts read | `HealthReader.swift` | **NOT COMPILED** |
| The summary text, the consent sheet, Messages opened with a draft | `HealthConnectionView.swift`, `MessagesView.swift` (new `draft:` parameter, default empty) | **NOT COMPILED** |
| Health prompt: "None of it leaves this iPhone unless you send the week's summary to Doddy in Messages yourself, after a yes of its own" in ten languages | `project.yml`, `l10n/*_infoplist.json` | catalogs PASS; nine machine drafts |
| 22 Polish lines | `l10n/pl.json` | catalogs PASS |

**Different on purpose.** Not a voice tool: Doddy's voice runs on ElevenLabs with Google's Gemini (`voice-agent/session.json`), and ADR-620 allowed a summary to go to Claude only. "How did it go?" by voice needs the owner's decision first.

## Not checked

- **The app has not been compiled with these changes** (steps 1 and 2). The hosted Mac job compiles it on a pull request.
- Messages opened from Settings over the Apple Health screen (not from Home) has not been seen; the persistent Doddy rides Home's Messages cover, and may not appear here.
- **Nothing has run on a device:** the Health sheet, the reads, the numbers against the Health app's own, a night recorded by both a watch and the iPhone, an iPhone that is locked while the screen reads (it should say so), iPad.
- **Signing the free-team project with HealthKit.** Apple's capability table lists HealthKit for the free Apple Developer account (read 24 Oct 2026). If Xcode still refuses, set `DODDY_APP_ENTITLEMENTS: ""` in `project-iphone.yml`; the screen then says this build can't use Health.
- No UI test for the new screen yet.

## Privacy and safety

- Health data is special-category data (GDPR Art. 9). Reading it stays on the iPhone. Sending the week's summary (step 2) has its own explicit consent, versioned and recorded on the iPhone, and every send is the person's own tap on Send with the text in front of them (App Review 5.1.2(i), ADR-620).
- Withdrawing the consent stops new summaries; what was sent stays in Messages until the person deletes it, and the screen says so. Anthropic's own retention of API requests is not covered by this page; the legal pages must state it.
- The legal pages (`site/privacy/`) don't mention Health or the summary yet; they must before this ships.
- App Review 5.1.3: no Health data for ads, none in iCloud, nothing written to Health.

## Next (each needs the owner's go-ahead)

1. Owner decision: may a summary go to Doddy's voice (ElevenLabs and Google's Gemini) for "How did it go?" by voice?
2. Voice gym log and the wger exercise base.
3. Running and strength plans with the safety rules from the research.
