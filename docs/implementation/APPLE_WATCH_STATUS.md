# Apple Watch app status (ADR-232)
Date: 2026-10-10. Owner: "do all of them" (item 7).

## What ships
- **A watchOS 10 app** (`DoddyWatch`), embedded in the iPhone app. It needs the iPhone app; it has no database and makes no network calls.
- **What it shows:** the snapshot the iPhone sends through the WatchConnectivity application context. It is the same content as the widgets (`WidgetSnapshot.make`):
  - up to 4 pinned notes (first line);
  - the next 3 time reminders on notes, with their text only if "Show note text in notifications" is on;
  - up to 8 lists with up to 12 items each.
  It also shows "As of HH:MM on your iPhone".
- **Its own switch:** Settings › Apple Watch › "Show notes and lists on Apple Watch". It is shown only when a watch is paired, and is on by default, like widgets (ADR-224). When off, the watch gets an empty snapshot and says how to turn it on.
- **Ticking:** tapping an item sends `tick(listID, itemID, shownDone)`. The iPhone runs the widgets' tick (`WidgetSync.tick`): it reloads, changes the item only if it still looks as the watch showed it, and reads it back. The watch shows the iPhone's answer ("Ticked on your iPhone.", "That list changed on your iPhone. Nothing was changed."), and the item changes on the watch when the next snapshot arrives.
- **New note:** the user writes or dictates with watchOS text input, checks the words, then taps Save. The iPhone checks the text again, saves it as a typed note, reads it back and answers. The watch says "Saved in Doddy on your iPhone." only from that answer.
- **When the iPhone is out of reach:**
  - Not reachable: nothing is sent, nothing is queued for later, and the watch says so.
  - Sent but unanswered: "Your iPhone didn't answer, so Doddy can't say whether it happened. Check in Doddy on your iPhone before trying again." It is never shown as done.

## Files
- **Core:** `WatchLink.swift` (`WatchRequest`, `WatchReply`, `WatchNote`, versioned encoding); Package platforms now include watchOS 10.
- **iPhone:**
  - `Features/Watch/PhoneWatchLink.swift`: the session, sending the snapshot, answering requests, and the Settings section;
  - `WidgetSync.refresh` also sends to the watch (even without the widgets' App Group);
  - `DoddyApp.swift`, `SettingsView`;
  - the `watchShowContent` preference.
- **Watch:** `DoddyWatch/DoddyWatchApp.swift`, `WatchLink.swift` and `WatchViews.swift`.
- **Project:** `project.yml` has the `DoddyWatch` target (bundle id `<app>.watchkitapp`, companion id set, not independent) as a dependency of the app.
- **Guard:**
  - WatchConnectivity only in `Features/Watch` and `DoddyWatch`;
  - no GRDB, persistence, URLSession or Network in `DoddyWatch`;
  - `DoddyWatch` is scanned like the other app folders.
- **Tests:** `WatchLinkTests` (3).

## Verified (Linux)
- `WatchLinkTests` pass: requests round-trip; other versions and garbage are ignored; replies come from the read-back tick; notes are checked before sending.
- `swiftc -parse` passes on all watch and iPhone files. The capability guard passes.

## NOT RUN / UNVERIFIED
- No Xcode build. Never run on a watch or simulator. Not checked:
  - whether XcodeGen embeds the watch app correctly ("Embed Watch Content");
  - signing with the companion bundle id;
  - the WatchConnectivity activation order;
  - delivery of the application context;
  - `sendMessageData` while the iPhone app is in the background (iOS wakes the app for messages, but this is untested);
  - watchOS dictation in Polish.
- The watch app has no icon yet (it is needed for the App Store) and no Polish catalog of its own.

## Decisions for the owner
- On by default, like widgets. Say if the watch should start off instead.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-08 verified_status_and_receipts | Watch shows "Saved"/"Ticked" only from the iPhone's read-back reply; no answer → "can't say whether it happened" | `testRepliesComeFromTheReadBackTick` | WatchConnectivity untested |
| DOD-07 scoped_action_approval | Save only on tap after checking the words; a tick changes only the item as it was shown | `testRequestsRoundTripAndOtherVersionsAreIgnored`, `testNotesAreCheckedBeforeSending` | UI not compiled |
| DOD-11 observable_privacy | Own switch; notification-text setting respected; no storage or network on the watch (guarded) | capability guard PASS | Snapshot sits in the system's application context on the watch |
