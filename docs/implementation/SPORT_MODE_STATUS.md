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

**Different on purpose.** Not a voice tool: Doddy's voice runs on ElevenLabs (with an OpenAI model, `gpt-6-luna`, on the live agent read 24 Oct; `voice-agent/session.json` says Gemini and is out of date), and ADR-620 allowed a summary to go to Claude only. "How did it go?" by voice needs the owner's decision first.

## Step 3: "How did my week go?" by voice (ADR-623)

Owner, 24 Oct 2026: "1 tak" (Doddy's voice may hear the summary). Same branch.

**What it does.** A new voice tool, `read_health_week`. When the person asks how their week, training or sleep went, Doddy says what he will look at and asks (ASK-01: a spoken yes or a tap on the card "Read your week from Apple Health?"). Then the iPhone works out the same week as the screen and gives the agent a short English summary with the rules for answering: rate briefly, compare with the week before, one change, no diagnosis or medical advice or calorie targets, and for chest pain, fainting, dizziness or unusual breathlessness, stop and see a doctor (112).

**Its own consent.** On the Apple Health screen, **Doddy's voice** › **Let Doddy's voice hear the week**: a sheet that says the voice runs on ElevenLabs with an OpenAI model (or OpenAI directly if picked on Home), that they get the summary as part of the conversation, and that ElevenLabs keeps each conversation's recording and transcript, which Doddy's settings there keep with no time limit for now. Without that yes, or with Apple Health off, the tool answers "not allowed" and reads nothing. "Stop Doddy's voice hearing Health" takes it back.

| Part | File | Checked |
|---|---|---|
| The tool: name, parse, ASK-01 card, a look-up in the catalog, a row in What Doddy did (Apple Health, Polish "Zdrowie"), paused by Pause all, allowed in the car, no Connections switch | `HealthVoice.swift`, `VoiceTools.swift`, `ToolCatalog.swift`, `AskFirst.swift`, `ActivityLog.swift`, `ActivityText.swift`, `ConnectionPause.swift`, `CarProfile.swift` | `HealthVoiceTests` 7 tests (the agent's exact lines included); `ActivityTextTests` now counts 41 kinds; `ToolCatalogTests` matches `tools.json` |
| What the agent hears and the refusals | `VoiceToolReply.healthWeek`, `healthWeekNotAllowed`, `healthWeekEmpty`, `healthWeekFailed` | same tests |
| The handler: Apple Health on and the voice consent, else "not allowed" | `VoiceSessionController.swift` | **NOT COMPILED** |
| The voice section and its consent sheet | `HealthConnectionView.swift` | **NOT COMPILED** |
| Agent spec: the tool (`not_synced`) and one prompt line | `voice-agent/tools.json`, `instructions.md`; `backend/src/web/logbook.ts` lists the new id | `voice_agent_spec.py check` PASS (96 tools); backend 428/428 |
| Health prompt: a summary leaves only "in Messages when you send it yourself, or to Doddy's voice when you ask and say yes"; ten languages | `project.yml`, `l10n/*_infoplist.json` | catalogs PASS; nine machine drafts; 10 more Polish lines |

**Live agent: changed on the owner's yes** ("Jazda tak", 24 Oct, to the exact text shown): `tool_3001m5q73js3f5stcnshpx4d13f6`, saved as `agtvrsn_4701m5q787a7e9kvp21qvjza63t0` with an "## Apple Health" prompt section; rollback `agtvrsn_2801m5pzdaxpepgax0wwfawyc8tp` (`voice-agent/README.md`). An app build without the tool answers that it doesn't support it. The OpenAI voice gets it with the next app build.

**Gap to know.** The red-flag rule reaches the voice as text in every reply and in the prompt; the model could still ignore it. A fixed, code-enforced reply for red-flag words is not built.

## Step 4: running and strength plans, the engine (ADR-624)

Owner, 24 Oct 2026: "2" (plans next). Same branch. The engine (DoddyCore, tested on Linux), then the screens on the iPhone (ADR-625, below). No voice tool or Messages way to ask for a plan yet.

**What it does.** `PlanEngine.make(request)` turns the person's answers (goal, level, days a week, minutes a session, longest recent run, the screening questions, age) into a plan or a refusal. Deterministic: the same answers give the same plan; a model may later explain a plan, never change its numbers.

- **Refusals first:** an injury or pain → a physiotherapist or doctor; pregnant or recently gave birth → a doctor or midwife; a condition, symptoms or a doctor's limit → a doctor first; under 16 → with a parent, PE teacher or coach; a 10 km or half marathon for a beginner → a first 5 km first; a half marathon at 16 or 17 → a 10 km first; too few days or minutes → says how many.
- **First 5 km:** run/walk, 12 weeks on three days (14 on two), from 8 × (1 min run, 1.5 min walk) to 30 minutes without stopping (for many people 4 to 5 km), with 5-minute walks around each block. Doddy's own table, not NHS's.
- **10 km (8 weeks), half marathon (12 weeks):** easy runs, one hard session (tempo or intervals) for people who train (from week 3 for "now and then"), the long run on the weekend building to 70 or 120 minutes, every fourth week easier, the last week lighter.
- **Strength at home or in the gym (8 weeks):** full body on two or three days with a day between, upper and lower on four days for people who train regularly; 8–12 reps with 2 reps in reserve (16 and 17: 10–15 with 3); beginners start with 2 sets; every fourth week a set fewer; short sessions drop exercises, then sets.
- **`PlanRules.violations`** checks any plan against the rules: no run more than 10% longer than the longest of the four weeks before (time on feet), at most 20% of running time hard, nothing hard the day after a hard session, full-body days apart, weekday sessions within the person's time, at least 2 reps in reserve, at most 5 sets, 16 and 17 never under 10 reps.
- **`StrengthProgression.next`:** load goes up only after every set reached the top of the range with 2 reps in reserve (5 kg legs, 2.5 kg upper body, a harder version at home); a set to failure keeps the load; two short sets mean lighter.

| Checked | How |
|---|---|
| Every plan the engine can make keeps every rule | `TrainingPlanTests.testEveryPlanTheEngineMakesKeepsTheRules`: every goal × level × 1–6 days × 8 session lengths × 6 starting runs × 4 ages, over 1,000 plans, no violation. With the long-run growth loosened to 25% on purpose it fails; restored |
| The 5 km table | checked by a script and by the test above, for three and two days |
| Refusals, the 10 km long-run sequence (33, 36, 39, 31, 42, 46, 50, 55 min from a 30 min start), half marathon 80/20, strength shapes, youth limits, short sessions, progression | 11 more tests |
| A bad plan is caught | a hand-made week with a 50-minute jump, 25% hard, two hard days in a row, too many days, a long weekday, and a squat at 0 reps in reserve: each one found |

### On the iPhone: questions, the plan, keeping it (ADR-625)

The hosted Mac build of steps 1 to 3 compiled the app (run 40106746382 on `d7349ff`: build-for-testing and the unit tests pass; the one failing UI test fails the same way on the base branch, see "Not checked"), so the screens were added.

- **Where:** Settings › Connections › Sport and health › **Training plan**, a row under Apple Health; the plan needs no Health data. Since ADR-633 (Settings in fourteen rows) Sport and health is a section of its own on the Connections page, not cards inside Calendar, reminders, contacts.
- **Questions** (a sheet): goal, how much you train now, days a week (2–5 running, 2–4 strength), minutes a session, for 10 km and the half the longest run of the last 30 days if known, then the five safety questions as Yes/No with nothing pre-set, and age. **Make the plan** stays off until every question has an answer.
- **Answer:** a refusal says who to ask (doctor, doctor or midwife, physiotherapist, an adult, or the shorter goal first), with the safety note; a plan shows its weeks, a start (this week or next Monday) and **Keep this plan on this iPhone**. The screen says "kept" only after the file was written and read back.
- **The kept plan:** where today falls ("Week 3 of 8", or the days until Monday, or finished), today's session or a rest day, and every week with its sessions in words ("Walk 5 min. Then run 1 min and walk 1 min 30 s, 8 times. Walk 5 min to finish."; "Squat: 3 × 8–12, stop with 2 reps left"). **Make a new plan** replaces it; **Delete this plan** asks, deletes and checks the file is gone.
- **Honest about the goal:** with runs growing 10% at a time, a 10 km or half plan from far below ends short of the goal's long run (from 30 minutes, 8 weeks reach 55). Such a plan says so and says to make the next plan from there; its last long run is called "Your goal run" only when it reaches the goal (`TrainingPlan.reachesGoal`).
- **File:** `Application Support/Sport/training-plan.json`, complete file protection, the folder left out of iCloud and computer backups (App Review 5.1.3). One plan; nothing sent anywhere. A file that isn't exactly what this Doddy's engine makes for its answers (edited, or from an older engine) is never shown as Doddy's plan, only "delete it or make a new one"; an unreadable file is kept until the person decides (`SavedTrainingPlan.read`).
- **Safety note** on every plan and refusal (fixed text): an AI, not a doctor or coach, not medical advice; stop at once for chest, neck, jaw or arm pain, feeling faint or dizzy, unusual breathlessness or a racing heart; 112.
- **Polish:** 126 new lines in `l10n/pl.json`, machine-written.

| Checked | How |
|---|---|
| The kept plan's rules | DoddyCore `SavedPlanTests` 6 (read back exactly; an edited plan and a plan from answers that get no plan are both refused; unknown file and version are unreadable; Monday start whatever the first weekday, across the new year; where today falls, across the end of summer time in Warsaw; the start is a day, the same in New York) and `PlanGoalReachTests` 2 |
| The store on real files | `scripts/check_training_plan_store.sh` (new CI step, Linux): kept and read back, read after a "restart", an edited file not shown and not written over, an unreadable file kept, a new plan replacing it, delete, a failed write reported with nothing claimed: 9 checks pass |
| Store and text compile | `scripts/typecheck_app_logic.sh` now includes `TrainingPlanStore.swift` and `PlanText.swift` (Swift 6, Linux): 29 files pass |
| The flow | `TrainingPlanUITests`: a "yes" gets "Talk to a doctor first" and nothing to keep; all "no" gets a plan, kept, shown, deleted. **Passes** on the hosted Mac (run 40128474881 on `53777ef`, iPhone simulator). Its first run (40122886800) found that the number pad covered "Make the plan" and had no key to close it; the sheet now has Done above the keyboard |

**Not built:** the voice and Messages way to ask for a plan, logging what was done and the next load from it (`StrengthProgression` is ready, no screen), the exercise descriptions and pictures (wger), and adjusting the plan from what Apple Health shows was actually done.

## Not checked

- **Steps 1 to 4 compile and pass on the hosted Mac:** run 40128474881 on `53777ef`.
  - Build-for-testing, the app's unit tests and every UI test (63, 1 skipped: iPad only) pass.
  - The run includes `TrainingPlanUITests` and the base's menu fix.
  - Earlier runs failed `MemoryJourneyTests.testDarkLargestTextKeepsTextRoutesUsable`, which came from the base: "Cheapest this week" sat above Memories in Home's menu. The base fixed it in `185155b`, merged here.
  - The base's price watch also left two settings out of `secrets/manifest.json`, which this branch adds (`695b525`).
- Messages opened from Settings over the Apple Health screen (not from Home) has not been seen; the persistent Doddy rides Home's Messages cover, and may not appear here.
- **Nothing has run on a device:** the Health sheet, the reads, the numbers against the Health app's own, a night recorded by both a watch and the iPhone, an iPhone that is locked while the screen reads (it should say so), iPad.
- **The free-team project has no HealthKit** (owner, 25 Oct 2026, before merging): `make project-iphone` is back to no entitlements, and its Apple Health screen says this build can't use Health. The shipping project (`make project`) has HealthKit. To try Health on a free team, set `DODDY_APP_ENTITLEMENTS` to `Config/DoddyiPhone-HealthKit.entitlements` in `project-iphone.yml`: Apple's capability table lists HealthKit for the free Apple Developer account (read 24 Oct 2026), but signing it has not been tried.
- No UI test for the Apple Health screen. The training plan's UI test passes on the simulator; nobody has used the screens on a device.

## Privacy and safety

- Health data is special-category data (GDPR Art. 9). Reading it stays on the iPhone. Sending the week's summary (step 2) has its own explicit consent, versioned and recorded on the iPhone, and every send is the person's own tap on Send with the text in front of them (App Review 5.1.2(i), ADR-620).
- Withdrawing the consent stops new summaries; what was sent stays in Messages until the person deletes it, and the screen says so. Anthropic's own retention of API requests is not covered by this page; the legal pages must state it.
- The legal pages (`site/privacy/`) don't mention Health or the summary yet; they must before this ships.
- App Review 5.1.3: no Health data for ads, none in iCloud, nothing written to Health.
- The training plan and the answers it was made from (every safety answer "no", and the age) stay on the iPhone in a protected file left out of backups; nothing about it is sent. **Delete this plan** removes it. Settings' "Delete all memories" doesn't touch it: a plan isn't a memory.

## Next (each needs the owner's go-ahead)

1. A first real conversation with `read_health_week` on an app build from this branch, then the ElevenLabs log.
2. Asking for a plan by voice or in Messages; logging a session and the next load from it.
3. Voice gym log and the wger exercise base.
