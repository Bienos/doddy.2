# Weekly tidy-up status (ADR-228)
Date: 2026-10-10. Owner: "do all of them" (item 6).

## What ships
- **Off by default.** In Settings › Weekly tidy-up you pick a day and a time (Sunday, 18:00 by default). One weekly notification is set and read back from iOS. It says only "Tidy up Doddy · A few minutes to tidy up?" ("Porządki w Doddym · Kilka minut na porządki?" on a Polish iPhone). There is also "Open the tidy-up now".
- **The screen** (`TidyUp.suggestions`) has three kinds of suggestion:
  - **Saved twice:** notes with the same words, ignoring case, accents and punctuation. The first copy is kept. Each later copy has "Delete the copy from …", which asks for confirmation; the app's Undo bar works as usual.
  - **Reminders that already passed:** one-off time reminders more than a day past that were never marked done. "Mark done" is checked against the reloaded reminders.
  - **Lists with everything ticked:** "Clear the ticked items" or "Delete the list", which asks for confirmation.
- "Keep them all" and "Leave it" hide a suggestion for this visit only.
- Nothing changes without a tap. There are no streaks, scores or counts on the app icon. Sample notes are never suggested.

## Files
- **Core:** `TidyUp.swift`; `DuplicateNote.key` is now public.
- **App:**
  - `Features/TidyUp/TidyUpViews.swift`: the scheduler, the screen and Settings;
  - `ShortcutRouter`: `isTidyUpPresented` (the opening's listen-on-open waits for it too);
  - the notification route; the `RootView` sheet; Settings; re-applied on launch.
- **Tests:** `TidyUpTests` (3).

## Verified (Linux)
- `TidyUpTests` pass. They cover:
  - copies are found, but not samples or different numbers, and the first copy is kept;
  - forgotten reminders, but not recent, repeating or ones for deleted notes;
  - a finished list, but not an empty one;
  - "nothing to tidy";
  - off by default, clamped settings and neutral wording.
- App-logic type-check passes (12 files). `swiftc -parse` on the new and changed files.

## NOT RUN / UNVERIFIED
- No Xcode build, and nothing run on a device. Unchecked:
  - the weekly trigger;
  - a tap from a cold start;
  - the confirmation dialog;
  - Undo after deleting from the sheet: the Undo bar sits behind the sheet until it closes.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | One button per suggestion; deletes confirmed; nothing automatic | `testSuggestionsFindCopiesForgottenRemindersAndFinishedLists` | UI not compiled |
| DOD-10 nonmanipulative_companionship | Off by default, neutral words, no streaks or badges | `testOffByDefaultAndNeutralWords` | — |
| DOD-08 verified_status_and_receipts | "Reminder marked done" only when it's gone from the reloaded reminders; deletes report through the store | — | — |
