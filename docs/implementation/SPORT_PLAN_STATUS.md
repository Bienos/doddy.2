# Sport plan: interview, safety, cards, logbook, review (ADR-632)

Owner, 24 Oct 2026: "dalszy plan sportowy" (after the expert-modes research, `docs/research/2026-10-24/research_expert_modes_PL.md` section 2, ADR-630). Branch `claude/sport-plan`, built on `claude/sport-mode-health` (PR #137). **Not merged, nothing seen on a device.**

## What was already there (ADR-624, 625, in `SPORT_MODE_STATUS.md`)

`PlanEngine` makes a running or strength plan from the person's answers or refuses; `PlanRules` checks any plan; `StrengthProgression` says what comes next after a session; the screens ask the questions and keep the plan. This track does **not** repeat any of that; it adds what that status page lists as "not built" and what the research asks for around it.

## Stage 1: the decisions in code (DoddyCore, Linux)

| What | File | Checked |
|---|---|---|
| The typed result of any expert mode: mode, answer, proposed actions, missing data, sources with `checked_at`, caveats, `memory_update_proposal` (null), risk level, `verified_external_action` (false); humor allowed only at low risk | `Expert/ExpertResult.swift` | `ExpertResultTests` 5 |
| Triage of the words: a fixed stop message ending in 112 for chest, jaw or radiating pain, fainting, dizziness, unexplained breathlessness, palpitations, stroke-like signs; fixed texts for a sharp injury and for pregnancy (no plan); eating-disorder cues switch off every number. Negation within three words cancels a match; soreness after a workout is not chest pain unless something sudden is said | `Sport/TrainingTriage.swift` | `TrainingTriageTests` 12 |
| A weight goal said in words, judged by pace: above 0.5 kg a week it is refused with "about N weeks"; none under BMI 18.5, under 18, or with eating-disorder cues or pregnancy; no calorie number in any answer | `Sport/WeightGoalGuard.swift` | `WeightGoalGuardTests` 6 |
| The minimum interview: reads goal, days, minutes and level from what is said; asks only what is missing, at most five grouped questions; the safety questions and age are never assumed | `Sport/TrainingInterview.swift` | `TrainingInterviewTests` 7 |
| 25 text-only exercise cards (Polish and English), one for every exercise the engine can prescribe, with WHO 2020 and ACSM 2026 cited and the day checked | `Sport/ExerciseCard.swift` | `ExerciseCardTests` 7: a sweep of every goal, level, days, length and age checks that each prescribed exercise has a card |
| The order of decisions: triage, then a weight goal, then the interview, then `PlanEngine`; Apple Health fills a gap only after a yes and says so | `Sport/TrainingExpert.swift` | `TrainingExpertTests` 12: the research's acceptance tests 1, 2, 3, 11 and 12 at the level of the logic |

DoddyCore `make test-core` (Swift 6.1.2, Linux): **1,880 tests, 0 failures** (1,831 on the branch before, 49 new). One rule per new file was broken on purpose and the tests failed (negation 7, pace limit 4, assuming the screening 3, a missing card 1, `verified_external_action` defaulting to true 3, skipping triage 22), then the rule was restored. `scripts/typecheck_app_logic.sh` PASS (30 files); `check_forbidden_capabilities.sh`, `build_strings_catalog.py --check` and `voice_agent_spec.py check` PASS.

## Honest limits

- The triage is a wide mesh of words, not a diagnosis, and it can only add a stop. It will miss symptoms said in other words; the screening questions of `PlanScreening` stay mandatory before any plan. It is Polish and English only.
- The cards cite WHO 2020 and ACSM 2026 for how hard to train (read on their pages on 24 Oct 2026); the technique cues are Doddy's own words, not taken from a named instruction source, and have not been reviewed by a trainer or physiotherapist. **A person qualified in exercise should read the 25 cards before they are shown to anyone.**
- Nothing of this stage is on a screen or behind a voice tool yet.
- After an eating-disorder cue the mode gives the fixed text and no plan in that turn. The research only requires the numbers off; whether a movement plan may follow is the owner's decision.

## Stage 2: the logbook and the weekly review (DoddyCore and DoddyPersistence, Linux)

| What | File | Checked |
|---|---|---|
| A logged set and session, with the rules in the value: a key is a short lowercase word and never free text, reps 0 to 200 (seconds for a hold), load 0 to 500 kg kept in grams, reps left 0 to 10, at most 40 sets, a session needs sets or run minutes. The consent value, the export (JSON, ISO dates, oldest first) and the store's protocol | `Sport/TrainingLog.swift` | `TrainingLogTests` 9 |
| The store on SQLite, in the notes' file: consent first (checked in the same transaction as the write), every write read back inside its transaction and rolled back on a difference, a session more than a day ahead refused, a correction replaces the entry whole, delete one, delete all, export with or without consent. Migration `v19_training_log`; the same rules also sit in the tables as CHECK constraints and a foreign key | `Sources/DoddyPersistence/SQLiteTrainingLogRepository.swift`, `DoddyDatabase.swift` | `SQLiteTrainingLogRepositoryTests` 14: consent, read-back with an injected fault, delete for good (the exercise name is gone from the file bytes), the tables refusing bad rows from another path, a broken stored row reported as corrupt, a file from the build before opening and gaining the tables |
| The weekly review: the last 14 days, **one** priority, **one** variable | `Sport/TrainingReview.swift`, `TrainingReviewText.swift` | `TrainingReviewTests` 23 |

How the review decides, in this order: pain in any session of the window (nothing is raised, see a doctor or physiotherapist, a mistaken entry can be corrected); an exercise whose sets stopped short of the range (lighter); the last two sessions both hard (the same as last time, nothing added); the first exercise ready for more (`StrengthProgression`: +5 kg legs or +2.5 kg upper body and back to the bottom of the range, or one more rep, or a harder version at home, or a few seconds longer for a hold); otherwise nothing changes. A set without "reps left" is counted as none, so it never raises anything and the text asks for the note. The totals of the last two sessions are compared only when the heaviest load was the same. A run is never raised: the plan already caps the long run at +10%. The text is fixed, in Polish and English; a test scans every text for shaming and promising words and for calorie numbers.

DoddyCore `make test-core` (Swift 6.1.2, Linux): **1,926 tests, 0 failures** (46 new). One rule per piece was broken on purpose and the tests failed, then it was restored: the pain stop skipped (1 test, 7 assertions), a missing "reps left" counted as 2 (1 test), the consent check dropped from `record` (2 tests), the read-back dropped (1 test), `secure_delete` switched off (the delete-all test found the exercise name still in the file).

### What the logbook is, and is not

- Training notes are health data. They stay on this iPhone, in the app's SQLite file; nothing in this code sends them anywhere or into a prompt. The file is the notes' file, `Application Support/Memories/memories.sqlite`, in a folder created with iOS file protection `completeUntilFirstUserAuthentication` (`AppEnvironment.databaseURL`); it is not separately encrypted, and whether it is in a device backup is as for the notes. The notes' "delete everything" in Settings does not yet reach the logbook; its own delete-all does (stage 3 must put both on the screen).
- **Taking back the yes stops recording and does not delete.** The screen must say so in those words and offer "Delete my log" next to it (stage 3). Deleting all leaves the yes in place.
- There is no note field on purpose: no free text about a person's body is stored. The feeling is one of four words; `pain` is the only one that changes what the review says.
- There is no limit on how many sessions are kept. A year of training is a few thousand rows.
- Two builds that each add a migration number `v19` would both apply; if another branch also adds `v19_...`, the names differ so GRDB runs both, but the order of the list in `DoddyDatabase.migrator` decides which runs first. Nothing here depends on that order.

## Stage 3

Not built yet when this page was written; added when it is.
