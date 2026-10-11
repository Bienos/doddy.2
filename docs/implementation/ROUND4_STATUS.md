# Round 4: status (ADR-291 to ADR-298)
Date: 2026-10-11. Owner: "do all of them" (round 4). Decisions are in `DECISIONS.md` › Round 4. Everything here is written and checked on Linux only. **No Xcode build, no device.**

| # | Item | Result |
|---|---|---|
| 1 | Join `claude/affectionate-edison-ktc6i6` | Already merged by another session (PR #27). Its follow-ups (ADR-277, ADR-278) are still on that branch. |
| 2 | Currency conversion | ADR-291, below |
| 3 | "Where did I park?" | ADR-292, below |
| 4 | Reminder details by voice | ADR-293, below |
| 5 | Todoist: complete and move | ADR-294, below |
| 6 | Read one whole email | ADR-295, below |
| 7 | Recipe to shopping list | ADR-296, below |
| 8 | Weekly look-back | ADR-297, below |
| 9 | "Talk to Doddy" control | Already existed: `DoddyWidgets/TalkToDoddyControl.swift` (iOS 18, Control Center, Lock Screen, Action Button). Nothing changed. |
| 10 | A shared list's place for everyone | ADR-298, below |

## ADR-291 Currency conversion
- **Ships:**
  - `convert_currency` (amount, from, to).
  - The app downloads the ECB's daily reference-rate file itself: one fixed address, ephemeral session, no cookies, redirects refused, 64 KB cap.
  - The file is fetched again after 6 hours; the last good rates are kept in UserDefaults.
  - The answer always gives the rates' date, and says "last rates the app has" when newer ones couldn't be fetched.
  - With no rates it says so and doesn't guess.
- **Files:**
  - Core: `Currency.swift`.
  - App: `Infrastructure/Network/ExchangeRateClient.swift` and the controller case.
  - Guard: the new network file is allowed, but only for `ExchangeRateSource.url`.
  - Data-flow row "European Central Bank (exchange rates)".
- **Tests:** `CurrencyTests` (7).
- **NOT RUN:** a real download from an iPhone, and the ECB's exact XML on the day (the parser accepts single or double quotes).

## ADR-292 "Where did I park?"
- **Ships:** `parking_spot` save, find and clear.
  - **Save:** one position (≤ 100 m uncertainty, 15 s at most), a card, then Save keeps it in UserDefaults and reads it back.
  - **Find:** the reply has the time, the note and a rounded distance, never coordinates. The card shows Open in Maps.
  - **Clear:** removes the spot and checks it is gone.
- **Files:**
  - Core: `Parking.swift`.
  - App: `Features/Parking/ParkingStore.swift` (type-checked on Linux), `PlaceLocation.currentFix(within:)`, and the controller and `VoiceView` card.
- **Tests:** `ParkingTests` (6).
- **NOT RUN:** location on a device, underground car parks (expect "couldn't get a precise enough position"), and Maps opening.

## ADR-293 Reminder details by voice
- **Ships:**
  - `change_reminder` takes `add_note`, `priority` and `move_to_list`, alone or with `new_due`.
  - The list is matched against `DeviceConnections.reminderLists()`, writable lists only.
  - The stale check includes priority and list. Everything is written in one `save`.
  - The read-back must show the note at the end, the priority, the list and the due.
  - No Undo for these changes, and the card says so.
- **Files:**
  - Core: `ReminderDetails.swift`; `ReminderChangeDraft`, `ReminderChange.details` and `ReminderSnapshot.priority/listID`.
  - App: `DeviceConnections.changeReminder`, `reminderLists`; the controller; the card rows.
- **Tests:** `ReminderDetailsTests` (7).
- **NOT RUN:** EventKit. In particular, whether moving a reminder between an iCloud list and a local list keeps its identifier: if it doesn't, the read-back reports "unknown", never "done".

## ADR-294 and ADR-295 Todoist complete and move; read one email
- **Backend (`backend/src/tools`):**
  - `complete_todoist_task`, `move_todoist_task` and `read_email`.
  - An optional `resolve` lookup. `prepare` is now async; the approval is bound to the arguments plus the looked-up task, which is looked up again before the write.
  - `list_todoist_tasks` text carries `[id …]`.
- **Mock:** new envelopes and a `malformed_write` scenario.
- **Tests:** 19 new; 152 pass in total.
- **App:** `CloudToolName` lists the three tools; the writes match the server's fixtures (`OnlineAccountsContractTests`). There is a not-found reply and activity rows.
- **Guard:** only `TODOIST_CLOSE_TASK_V1` and `TODOIST_UPDATE_TASK` are allowed among Todoist writes, only in the catalog and the mock. A probe file with `TODOIST_DELETE_TASK` still fails the guard.
- **NOT RUN:**
  - any real Composio, Todoist or Gmail account;
  - what Composio returns for an unknown task id (assumed `successful: false` with "not found"; anything else is treated as an error, never as not found);
  - whether `messageText` arrives with `verbose: true`.

## ADR-296 Recipe to shopping list
- **Ships:**
  - `add_ingredients` gives a card with ticks. Items already open on the list start unticked.
  - "Add N" adds only the ticked items through the store, read back, with Undo in What Doddy did.
  - The reply says the items were Doddy's suggestions.
- **Files:** `Ingredients.swift`; the controller and `VoiceView`.
- **Tests:** `IngredientsTests` (4, including the "What Doddy did" rows for this round's replies).

## ADR-297 Weekly look-back
- **Ships:**
  - Settings › Weekly look-back: off, plus day and time; read back from iOS.
  - The notification says only "Your week with Doddy". Its screen shows notes (up to 5, the user's words), ticked items, checked changes by app (undone and unsure ones excluded) and, if connected, the next 7 days.
  - It is re-applied on launch. A tap opens the sheet.
- **Files:**
  - Core: `WeeklyLookBack.swift`.
  - App: `Features/WeeklyLookBack/WeeklyLookBackViews.swift`, `ShortcutRouter.weeklyLookBackOpened`, the RootView sheet, the notification tap and `DoddyApp` launch.
- **Tests:** `WeeklyLookBackTests` (3).
- **NOT RUN:** the weekly notification on a device.

## ADR-298 A shared list's place for everyone
- **Ships:**
  - **Under a shared list's reminder:**
    - **Share this place with everyone on the list:** one `DoddyListPlace` record, read back.
    - **Remind me there too:** sets this user's own place reminder.
    - **Stop sharing this place:** for whoever shared it.
  - A place within 50 m, arriving or leaving alike, counts as the same.
  - Synced places are read at each sync.
- **Files:**
  - Core: `SharedListPlace` and `SharedPlaceOffer` in `SharedLists.swift`.
  - App: `ListCloud.setPlace` and `Zone.sharedPlace`, `SharedListsController.placeOffer/setSharedPlace`, `SharedPlaceRow` and `ListViews`.
- **Tests:** `SharedListPlaceTests` (2).
- **NOT RUN:** CloudKit. The `DoddyListPlace` record type must be added to the CloudKit schema and deployed to Production with the list types.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | Cards for parking save, reminder details, Todoist complete and move (built from Todoist's own task), ingredients (ticks) and Share this place | `ReminderDetailsTests`, `IngredientsTests`, backend `todoist-gmail-tools.test.ts` | UI not compiled |
| DOD-08 verified_status_and_receipts | Read-back for the parking spot, reminder details, list adds and the shared place. Todoist "moved" only with the returned due, otherwise unknown. A currency answer always has its date. | `ParkingTests`, `ReminderDetailsTests`, `SharedListPlaceTests`, backend tests | No device, iCloud or account run |
| DOD-05 tool_content_is_data | `read_email` text framed as information only; links and tags removed | backend tests | Live Gmail not run |
| DOD-10 nonmanipulative_companionship | The look-back has no streaks, scores or comparisons | `WeeklyLookBackTests` | — |
| DOD-11 observable_privacy | No coordinates to the agent; one fixed ECB address; read_email off by default; the place shared only on a tap; data-flow rows and privacy paragraph | guard script, `CurrencyTests`, `ParkingTests`, `OnlineAccountsContractTests` | Never "privacy guaranteed" |
