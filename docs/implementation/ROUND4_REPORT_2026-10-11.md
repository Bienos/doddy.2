# Round 4 report: "do all of them" (2026-10-11, ADR-291 to ADR-298)
Branch `claude/hopeful-fermat-1a63x0`, restarted from `claude/loving-dirac-uuxoux` after PR #34 merged. The owner's list of ten. Details are in `ROUND4_STATUS.md`; decisions are in `DECISIONS.md` › Round 4.

## Outcome per item
| # | Item | Outcome |
|---|---|---|
| 1 | Join affectionate-edison | **Already done** by another session (PR #27). Its follow-ups (ADR-277, ADR-278) are still on that branch. |
| 2 | Currency conversion | ADR-291, written and checked on Linux |
| 3 | "Where did I park?" | ADR-292, written and checked on Linux |
| 4 | Reminder details by voice | ADR-293, written and checked on Linux |
| 5 | Todoist complete and move | ADR-294: backend tests pass (mock); the app is wired |
| 6 | Read one whole email | ADR-295: backend tests pass (mock); off by default |
| 7 | Recipe to shopping list | ADR-296, written and checked on Linux |
| 8 | Weekly look-back | ADR-297, written and checked on Linux |
| 9 | "Talk to Doddy" control | **Already existed** (`TalkToDoddyControl`, iOS 18). I proposed it without checking first; nothing was changed. |
| 10 | Shared list place for everyone | ADR-298, written and checked on Linux |

## Tests actually run
- `scripts/ci.sh --core-only` on Linux (Swift 6.2.1): **RESULT: PASS for core-only scope; iOS app NOT verified**. It covers:
  - DoddyCore tests, including 7 new test files (`CurrencyTests`, `ParkingTests`, `ReminderDetailsTests`, `IngredientsTests`, `WeeklyLookBackTests`, `SharedListPlaceTests` and the updated `OnlineAccountsContractTests`);
  - the app-logic type-check, now including `ParkingStore.swift`;
  - the capability guard, with negative checks: a probe `TODOIST_DELETE_TASK` fails it, and the rates client may only use its fixed address;
  - the agent specs and the Polish catalogs (1,136 of 1,158 strings);
  - backend: 152 tests, 19 new;
  - gateway and messaging tests.
- **Skipped:** the messaging database tests (no `TEST_DATABASE_URL`).
- `swiftc -parse` on every changed SwiftUI, WidgetKit, CloudKit and EventKit file.

## NOT RUN
- No Xcode build, no device, no iCloud, no real Todoist or Gmail account.
- The ECB file has never been downloaded by the app.
- See `FIRST_BUILD_GUIDE.md` › Round 4.

## Live voice agent
- Version `agtvrsn_7701m4n8vprrem78gmfjjmq77t96` → `agtvrsn_8101m4nf7332e9d9s4vcvvyd1zbx`, 49 tools.
- Six new tools; `change_reminder`, `check_email` and `list_todoist_tasks` updated. The prompt is `voice-agent/instructions.md`.
- The stored prompt was read back.
- **Mixed versions:** older apps answer "unsupported" to the six new tools. An older backend refuses the three online-account tools.

## Security and privacy
- **New outside contact:** the ECB's public rates file. One fixed address, nothing about the user sent, a guard check, a data-flow row and a privacy sentence.
- **Read an email:**
  - off by default;
  - the email's text goes to ElevenLabs during that conversation, which the privacy paragraph now says;
  - the text is framed as data;
  - receipts keep no content.
- **Todoist writes:**
  - the card is built from Todoist's own task, and the approval is bound to that task;
  - the guard allows exactly two new write slugs.
- **Parking:** coordinates never go to the agent. Location is read once, only on "save", and kept only on this iPhone.
- **Shared place:** only the place the user picked is shared, and only on a tap. Nobody's whereabouts are shared.

## Decisions for the owner
1. First build: fix Actions billing or use a Mac. Four rounds of Swift now wait on it.
2. Deploy the CloudKit schema with the new `DoddyListPlace` record type before turning shared lists on.
3. Deploy the backend so `complete_todoist_task`, `move_todoist_task` and `read_email` work, then try them once against a real account. Note: I couldn't confirm what Composio returns for an unknown task id.

## Constitution evidence log
In `ROUND4_STATUS.md` (rules DOD-05, DOD-07, DOD-08, DOD-10 and DOD-11, with their enforcing code, tests and gaps). Nothing in this round is "implemented" on a device, and no "privacy guaranteed" claim is made.
