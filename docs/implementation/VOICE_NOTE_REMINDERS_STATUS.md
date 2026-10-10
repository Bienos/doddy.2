# Voice note reminders status (ADR-198)
Date: 2026-10-10. Owner instruction: "build voice reminders next". Builds on note reminders (ADR-190, `M4A_NOTE_REMINDERS_STATUS.md`) and place reminders (ADR-196, `PLACE_REMINDERS_STATUS.md`). Design: `docs/design/NOTE_REMINDERS.md` (catalogue row "Voice agent proposing a reminder").

## What ships
- New voice tool **`remind_me_about_note`**: "remind me about the parcel code tomorrow at nine" or "…when I get to the post office". Arguments: `note` (the saved note's text, quoted), then `due` (YYYY-MM-DDTHH:MM) **or** `place` (Apple Maps search words) with optional `when_leaving`.
- The app finds the note from the quote: exact text first, then the same text ignoring case, outer quotes and extra spaces; with duplicates, the newest. No partial or "closest" match: the agent is told no note has that text and to call `search_memories`.
- A time goes through the same checks as Apple Reminders (written-out day, still ahead, not skipped or repeated by a clock change) and must include a time of day. Anything unclear goes back to the agent as a question; no card is shown.
- A place is searched in Apple Maps on the phone; the card lists up to 5 results to pick from. Nothing found: the agent asks for a more specific place.
- The card shows "Remind you about this note?", the note exactly as stored, and the time with its zone or the picked place, arriving or leaving. **Set reminder** / **Don't set**.
- **Set reminder** uses the same `NoteReminderStore` as the note screen: asks iOS for notifications (and location, for a place) only if never answered, then sets it. The agent hears "added: …" only when iOS lists the request as pending, "kept in Doddy only" when notifications are off for a time reminder, or "failed: … Nothing was set." with the reason (a place needs notifications and Precise Location; there is no in-app fallback).
- By voice a place reminder uses 200 m; the user changes the radius on the note.
- Activity log: "Remind about a note", with the note and the time or "arriving at / leaving" the place.
- **Pause all connections** stops the Apple Maps lookup; a time reminder still works because nothing leaves the phone.
- Agent prompt: one tool line and one rule ("Doddy's own notification, not an Apple Reminder"; say "set" only on "added"; tell the user when the iPhone won't alert). `create_reminder` stays for new to-dos.

## Files
- Core: `NoteReminderVoice.swift` (new: parsing, `NoteQuoteMatch`, replies), `VoiceTools.swift` (tool name, request case), `ActivityLog.swift`, `ConnectionPause.swift`.
- Tests: `NoteReminderVoiceTests.swift`.
- App: `Features/Voice/VoiceSessionController.swift` (proposal, place choice, set through `NoteReminderStore`, confirm and decline replies), `Features/Voice/VoiceView.swift` (card).
- Agent: `voice-agent/tools.json`, `voice-agent/instructions.md`, `voice-agent/README.md`.

## Live agent
- Client tool `tool_7401m4k84jjgf1ctk26vj03kextq` created and attached. Agent `agent_0501m4et27vyeawrwqfdxxfszfa6` version `agtvrsn_1401m4k5nha9ffv81j7c6m6sze2n` → `agtvrsn_1601m4k85xy5ew7awn6n9yxwas7v`. The prompt change adds only the two lines; the other 21 tool ids are unchanged.
- `voice_agent_spec.py compare` was run on the new tool and the full live prompt: no drift. The other 21 tools were not re-exported; they were unchanged on the agent before the update.
- An app build without this code answers the tool as unsupported, so the agent says it isn't available in this version.

## Verified (Linux, Swift 6.2.1)
- `scripts/ci.sh --core-only`: PASS, including the voice agent spec check (22 tools).
- 348 package tests. New tests:
  - time and place requests parse;
  - unclear, past, day-only and both-or-neither requests go back to the agent without a card;
  - quote matching: exact, normalised, newest, and no partial match;
  - reply prefixes map to activity outcomes;
  - pause stops only the place lookup.
- `RealtimeVoiceTests.testRepoToolCatalogDecodes`: every phone tool in the spec is routable.
- `swiftc -parse` on every Swift file in the app, test, widget and shared targets.

## NOT RUN / UNVERIFIED (needs a Mac and an iPhone)
- App compile, the card's layout and place selection, VoiceOver.
- On a device:
  - the agent quotes the note exactly as `search_memories` returned it;
  - Polish phrasing, for example "przypomnij mi o kodzie, jak będę na poczcie";
  - Apple Maps results for spoken place names;
  - the permission prompts appear in the middle of a voice session;
  - the notification fires.
- The agent's behaviour with the new tool has not been evaluated in a live conversation.

## Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run (Linux) | Gaps / claims to limit |
|---|---|---|---|
| DOD-07 scoped_action_approval | The model's call is only a proposal. `VoiceToolRequest.parseNoteReminder` validates it in typed code, and nothing is set before **Set reminder** on a card showing the stored note and the exact time or place (`VoiceSessionController.confirm` → `NoteReminderStore.set`). | `testTimeAndPlaceRequestsParse`, `testUnclearRequestsGoBackToTheAgentWithoutACard` | Card UI not exercised (no Xcode). |
| DOD-08 verified_status_and_receipts | The reply comes from the store's verified receipt: "added" only for a pending iOS request; Doddy-only and failure are stated, and nothing is retried. | `testRepliesUseTheActivityLogPrefixes`; existing coordinator tests for pending verification and rollback | Pending ≠ delivered. Whether the agent repeats the result correctly is not tested. |
| DOD-06 user_controlled_relevant_memory | The agent can't name a memory by id or invent one. Its quote must match a stored note (no closest match), and the card shows the stored text, not the agent's. | `testQuoteFindsTheNoteOrNothing` | A wrong but identical-text duplicate picks the newest; the user sees the text, not which copy. |
| DOD-11 observable_privacy | Place words go to Apple Maps, already listed in "What leaves this iPhone". Pause stops it, and a time reminder sends nothing. | `testPauseAllConnectionsStopsOnlyThePlaceLookup` | The lookup runs before the tap, like the note screen's search. Spoken words also reach ElevenLabs and the model as before. Don't claim more than this. |
| DOD-10 nonmanipulative_companionship | Only on the user's request (prompt plus tool description). No proactive reminders are offered. | — (no automated check) | Prompt-only. Model behaviour is not evaluated. |
| Tool content is data (CLAUDE.md constitution summary) | Note text and Apple Maps names are shown and quoted, never followed as instructions (existing prompt rule). | — | Prompt-only. |

## Open
1. Polish copy for the card and the replies.
2. A radius choice on the voice card (now fixed at 200 m).
3. A live conversation test in both languages, before calling this done for users.
