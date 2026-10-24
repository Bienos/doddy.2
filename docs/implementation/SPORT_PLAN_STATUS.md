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

## Stage 2 and 3

Not built yet when this page was written; each section is added when it is.
