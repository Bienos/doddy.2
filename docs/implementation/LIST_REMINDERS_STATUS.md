# List reminders at a place, by voice: status (ADR-256)
Date: 2026-10-11. Owner: "do all of them" (item 3: "remind me of the shopping list when I'm at Lidl").

## What was already there
- On screen, a list's menu has **Remind me**. It uses the same time and place reminders as notes (ADR-196, ADR-216).
- The notification says only "A list you asked to see again." and opens the list. Place reminders use "While Using" location only, and iOS, not Doddy, notices arriving or leaving.

## What ships now
- **The voice tool** `remind_me_about_note` takes `list` (the list's exact name, as in "The user's lists") instead of `note`. It takes one or the other, never both.
- **Matching:** the app matches the list like the list tools: exactly. If there is no match or several, the agent gets the list names and asks.
- **The card** says "Remind you about this list?" with "Your list in Doddy. The notification doesn't name it or its items." The time, or the Apple Maps results to pick from, appear as for notes. Nothing is set until Set reminder, and the reminder is read back from iOS as before.

## Files
- **Core:** `NoteReminderVoice.swift`: `NoteReminderVoiceDraft.isList`; `note` or `list`.
- **App:**
  - `VoiceSessionController`: `proposeNoteReminder` matches lists with `resolveList`; `isListReminder`;
  - `VoiceView`: the card's wording.
- **Agent:**
  - `voice-agent/tools.json`: the `list` parameter; `note` is no longer required;
  - `instructions.md`: one sentence.
- **Tests:** `NoteReminderVoiceTests.testAListCanBeNamedInsteadOfANote`.

## Verified (Linux)
- `NoteReminderVoiceTests` pass (7).
- `voice_agent_spec.py check` passes.
- `swiftc -parse` passes on the changed app files.

## NOT RUN
- No Xcode build, no device run, and no real place reminder for a list.
- The live agent isn't updated yet; that is planned in this round's agent step.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | Card, then Set reminder; exact list match, never a guess | `testAListCanBeNamedInsteadOfANote` | UI not compiled |
| DOD-11 observable_privacy | The notification never names the list or its items (ADR-216, unchanged) | existing `NoteReminders` tests | — |
