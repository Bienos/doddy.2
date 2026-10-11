# Unclear days and times: status (ADR-237)
Date: 2026-10-10. Owner instruction: "move to 3", from the research backlog OP-014 "Ambiguous date clarification". Example from the backlog: "Book this for next Friday." → "Do you mean Friday 16 October?"

## What changes for the user
When they ask Doddy by voice for a reminder, a calendar event, a note reminder or a plan, the agent now also passes their exact words for when. Before any card appears, the app checks those words against the date the agent worked out. If they allow two answers, or don't match, Doddy asks one short question first and nothing is added.

| The user says (on Saturday 10 October, 13:02) | Date the agent sends | Doddy |
|---|---|---|
| "next Friday" / "w przyszły piątek" | 16 or 23 October | Asks: Friday 16 October or Friday 23 October? |
| "this weekend" | 10 October | Asks: Saturday 10 or Sunday 11 October? |
| "next week" | 14 October | Asks which day next week |
| "tomorrow at 7" / "jutro o 7" | 07:00 | Asks: 07:00 or 19:00? |
| "today at 7" | 19:00 | No question: 07:00 has passed |
| "tomorrow morning" | 09:00 | Asks what time, or whether the day without a time is fine (an event asks what time) |
| "Friday" | Thursday 15 October | Asks: the words say Friday, the date is a Thursday |
| "tomorrow at 9" | 10:00 | Asks: the words say 9 |
| "in 2 hours" | 16:00 | Asks: not 2 hours from now |
| "Friday 16 October at 19:00" | 16 October 19:00 | No question |

The answer the user gives is sent again with the day written out, so the second try passes.

## What it does not do
- **Words it doesn't read are not questioned:** "half past seven", "wpół do ósmej", "kwadrans po", and dates as "16.10".
- **Nothing is checked unless the agent passes `said_time`.** Calls without it are handled exactly as before.
- **On-screen edits are not checked:** the plan card's Change form holds the user's own choices.
- **"9:30" is read as the 24-hour clock** (09:30), not as a question.

## Files
- `Packages/DoddyCore/Sources/DoddyCore/SaidTime.swift`: new. Word lists and rules.
- `ReminderAction.swift`: four new `ReminderClarification.Kind` values.
- `VoiceTools.swift`: `parseReminder`, `parseEvent`.
- `NoteReminderVoice.swift`.
- `voice-agent/tools.json`: `said_time` on three tools and in the `propose_plan` example.
- `voice-agent/instructions.md`: two lines.
- `Packages/DoddyCore/Tests/DoddyCoreTests/SaidTimeTests.swift`: new, 8 tests. They cover about 60 phrase and date pairs in English and Polish, plus checks through the tool parser and the plan card.

## Verified (Linux, Swift 6.1.2)
- `scripts/ci.sh --core-only`: PASS for core-only scope, 445 package tests. The voice and phone agent spec checks pass.
- **Planted bug:** switching off the "next Friday" check made 3 tests fail. The code was restored.

## NOT DONE / NOT RUN
- **Live agent synced 2026-10-10:** version `agtvrsn_1601m4m03vmqe90rh35280g5pxp7` → `agtvrsn_1601m4m2szrwfb9rhx1r2vcgmc3j`. The live agent now sends `said_time`.
  - Only app builds that include ADR-237 act on it; older builds ignore the field.
  - The live prompt and tools contain features from other branches that are not in this branch's spec: lists, translator, morning check-in, repeat on note reminders. They were left untouched; only the ADR-237 lines were added.
- **Not heard in a real conversation or tried on a device:** whether the agent passes the words faithfully, and how often the questions feel unnecessary (Mac checklist V8).
- **Typed requests are not covered:** Ask Doddy and Shortcuts have no `said_time`.

## Constitution evidence log
| Rule | How it applies | Enforcing code | Tests run | Gap / claim to limit |
|---|---|---|---|---|
| DOD-07 scoped action approval | The approval card shows only a date the user's words support | `SaidTime.check` in the tool parsers | `SaidTimeTests` | Only when the agent passes `said_time` |
| DOD-02 honesty over agreeableness | Doddy asks instead of guessing between two days or times | Same | Same | The word lists are AI-written and not reviewed by a native Polish speaker |
| DOD-08 verified status | Nothing is added before the question is answered; the existing "failed: not added yet" path is used | `VoiceToolRequest.needsClarification`, `PlanProposal` | `testAPlanStepWithAnUnclearDayStopsThePlan` | — |
