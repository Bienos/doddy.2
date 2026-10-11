# Birthday reminders from contacts: status (ADR-288)
Date: 2026-10-11. Owner: "do all of them" (round 3, item 9).

## What ships
- **Settings › Birthdays:** the contacts that have a birthday, the next one first. Each has its own switch, and all start off. It needs Contacts on in Connections; otherwise the screen says so.
- **A picked birthday** becomes Doddy's own yearly notification at 09:00 on the day, read back from iOS ("Set for 3 people. Checked."). A 29 February birthday rings on 28 February.
- **Limits:** at most 20 people, because iOS allows 64 pending notifications for the whole app and note reminders and the check-ins need room.
- **What is read:** only the name and birthday, on this iPhone. Nothing goes to the voice agent or any server, and nothing is added to Calendar or Reminders.
- **The notification** shows the name ("Marta's birthday · Maybe say hello.") only when notifications may show note text. Otherwise it says "A birthday today". The request id is a hash, never the contact id.
- **At launch,** the picked birthdays are scheduled again, so names, dates and the language follow Contacts and the iPhone. Someone deleted from Contacts drops out.
- **Permission prompt:** the Contacts prompt and the Connections card now mention birthdays.

## Files
- **Core:** `Birthdays.swift`.
- **App:**
  - `DeviceConnections.birthdays()` (Contacts stays in Connections, as the guard requires);
  - `Features/Birthdays/BirthdayViews.swift` (scheduler, screen);
  - `SettingsView` (link); `DoddyApp` (refresh at launch); `NoteReminderNotifications` (a tap just opens Doddy).
- **Config:** `project.yml` and `l10n/pl_infoplist.json` (Contacts prompt).
- **Tests:** `BirthdayTests` (3).

## Verified (Linux)
- `BirthdayTests` pass.

## NOT RUN
- No Xcode build, and never run against real Contacts.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | All off; each person picked by the user | `testOnlyPickedPeopleAreScheduledAndAtMostTwenty` | UI not compiled |
| DOD-08 verified_status_and_receipts | Read back from iOS's pending notifications | — | Not run on a device |
| DOD-10 nonmanipulative_companionship | One gentle line, no streaks or nagging; off by default | — | — |
| DOD-11 observable_privacy | Name and day only, on the phone; name in the notification only if allowed; hashed id | `testTheNotificationNamesSomeoneOnlyWhenAllowed` | — |
