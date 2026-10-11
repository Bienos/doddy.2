# "Whose birthday is coming up?": status (ADR-268)
Date: 2026-10-11. Owner: "build nex", after ADR-267. Claude's proposal list item 2/4: "people memory" and "birthdays this week". The notes half of "What do I know about Anna?" already works through `search_memories`; what was missing was the birthdays on contact cards.

## What ships
- **A new phone tool, `upcoming_birthdays`** (`voice-agent/tools.json`, 33 tools). It takes an optional `days`: 1 to 60, today included, default 7.
- **Read only.** It reads the name and birthday of each contact that has one. Nothing is written and nothing is set. If the user wants a reminder, the agent uses `create_reminder`, which goes through its usual card.
- **What the agent hears:** names with the day and month only ("today", "tomorrow", or "Wed 14 Oct"), at most 15, then "and N more". Never the birth year, an age, a number, an address or any other field. The reply tells the agent not to guess ages, years or birthdays that aren't saved.
- **Dates:**
  - Soonest first, then by name; birthdays later this week roll over into the new year.
  - A 29 February birthday falls on 28 February in other years and is marked "(born 29 Feb)".
  - Impossible dates are skipped (30 February, month 13, 29 February in a year that has no 29 February).
  - Non-Gregorian birthdays are skipped.
- **Switches:** uses the Contacts switch in Settings, Connections, iOS Contacts permission, and Pause all, like `lookup_contact`. It is logged in "What Doddy did" as "Read birthdays · Next 7 days" (a look-up).
- **Disclosure updated:**
  - Settings → Connections → Contacts gains the example "Whose birthday is this week?" and "Tell you whose birthday is coming up". What leaves the iPhone is now "Only the names Doddy finds, and for birthdays the day and month. Numbers, email addresses and birth years stay on your iPhone."
  - The voice privacy note (English and Polish) and the "What leaves this iPhone" row now say "contact names and birthdays (day and month)".

## Files
- **Core:**
  - `Birthdays.swift` (new: `ContactBirthday`, `Birthdays.upcoming`, parsing, the reply);
  - `VoiceTools.swift` (the case, the parser hook, the Contacts connection, `Arguments.has`);
  - `ConnectionPause.swift`;
  - `ActivityLog.swift`;
  - `DataFlow.swift`.
- **App:**
  - `DeviceConnections.birthdays()` reads the full name and birthday keys only;
  - the `VoiceSessionController` case;
  - wording in `ConnectionsView` and `VoiceView`;
  - `l10n/pl.json` and `Localizable.xcstrings`.
- **Agent:** `voice-agent/tools.json` (new tool, no live id yet) and one line in `voice-agent/instructions.md`.
- **Tests:** `BirthdaysTests` (7).

## Verified (Linux, Swift 6.1.2)
- `BirthdaysTests` (7) pass. They cover:
  - parsing (default, 1, 30, a string number; 0, 61, 2.5, a word and null refused);
  - the Contacts switch, Pause all and the activity row;
  - today and soonest first;
  - across the new year;
  - today only and the 60-day cap;
  - leap days and impossible dates;
  - the exact reply, with no year or age in it;
  - the cut at 15.
- A planted off-by-one (one day too many) was caught by a failing test, then removed.
- `scripts/ci.sh --core-only`: PASS (627 DoddyCore tests, voice agent spec with 33 tools, Polish catalog, guards). iOS app NOT RUN.
- `swiftc -parse` passes on `DeviceConnections`, `VoiceSessionController`, `VoiceView` and `ConnectionsView` (syntax only, not type-checked).

## NOT RUN / UNVERIFIED
- **Live agent NOT updated.** The ElevenLabs agent doesn't have `upcoming_birthdays` until someone adds it (owner approval needed, as for earlier tool syncs). Until then the agent can't call it, and the app answers nothing new.
- **No Xcode build, no device run.**
  - `CNContactStore.enumerateContacts` with only the name and birthday keys runs on the main actor. Large address books are untimed.
  - How birthdays without a year come back (`year` nil) is unverified on a device.
- **Mac checklist:** BD1–BD4 below.

## Mac checklist
| # | Do this | Expect |
|---|---|---|
| BD1 | Give two contacts birthdays this week (one without a year); ask "whose birthday is this week?" | Doddy names both with the day; never a year or age |
| BD2 | Contacts switch off; ask again | "Contacts isn't connected …"; nothing read |
| BD3 | Pause all on; ask again | Paused reply; nothing read |
| BD4 | "Remind me the day before Anna's birthday" | A create_reminder card; nothing added before the tap |

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-11 observable_privacy | Reads only name and birthday; the agent gets day and month, never the year; disclosure updated in Connections, the voice note and What leaves this iPhone | `testTheAgentHearsNamesWithDayAndMonthNeverAYearOrAge`, `testUsesTheContactsSwitchPauseAllAndTheActivityList` | Device untested |
| DOD-02 honesty_over_agreeableness | Reply tells the agent that only saved birthdays are known, and not to guess ages | same | Prompt behaviour not tried live |
| DOD-07 scoped_action_approval | Read only; any reminder goes through create_reminder's card | — (no write path) | — |

## Decisions for the owner
- Sync `upcoming_birthdays` to the live agent.
- ~~Accept that a contact's birthday (day and month) goes to ElevenLabs when asked for.~~ **Accepted by the owner 2026-10-11.**

**Live agent updated 2026-10-11** (owner approved): see the last paragraph of `DECISIONS.md` for tool ids and versions; `voice_agent_spec.py compare` MATCH.
