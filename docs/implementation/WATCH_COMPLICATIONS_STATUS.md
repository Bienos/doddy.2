# Watch complications and Smart Stack: status (ADR-262)
Date: 2026-10-11. Owner: "do all of them" (item 8).

## What ships
- **A watchOS widget extension, `DoddyWatchWidgets`,** embedded in the watch app (ADR-232). One widget, "Doddy", in four sizes; watchOS also offers it in the Smart Stack:
  - **circular:** a bell and the next reminder's time; else a checklist and the open-item count;
  - **corner:** an icon, with the time or "N left" along the edge;
  - **inline:** "Doddy reminder 18:00", or "Shopping · 4";
  - **rectangular:** "Doddy", "Reminder at 18:00", "Shopping · 4".
  - A tap opens the Doddy watch app.
- **What a complication may show:** the next Doddy note reminder's **time**, the **number** of open list items, and the **name** of the list with the most left. Never a note's or reminder's words, never list items. A watch face is seen by anyone nearby and stays on with Always On; the core type (`ComplicationContent`) has no field that could carry note text.
- **Smart Stack:** relevance is high in the hour before the next reminder (rising as it nears), 0.1 when lists have things left, and 0 otherwise. Timeline entries are written an hour before and just after each reminder, so it rises and then drops off without the iPhone.
- **Where the data comes from:** the watch app already receives the iPhone's widget snapshot. It now also writes it to the watch's App Group folder (`WidgetSnapshotFile`, read back) and reloads the complications. "Show in widgets" off on the iPhone arrives as an empty snapshot, so nothing of the user's is left on the watch either.
- **Opt-in signing:** like the iPhone widgets, the App Group needs a paid team. Set `DODDY_WATCH_ENTITLEMENTS = Config/DoddyWatch.entitlements` (used by the watch app and its extension). Without it the complication says "Open Doddy on your iPhone." and nothing is written.

## Files
- **Core:** `WatchComplication.swift` (`ComplicationContent`: make, relevance, timeline dates).
- **Watch:** `DoddyWatchWidgets/DoddyWatchComplications.swift` (provider, views, bundle), `DoddyWatchWidgets/Localizable.xcstrings`; `DoddyWatch/WatchLink.swift` (writes the snapshot, reloads).
- **Config:** `project.yml` (new target; the watch app embeds it and compiles `Shared/Widgets/WidgetSnapshotFile.swift`), `Config/DoddyWatch-Info.plist`, `Config/DoddyWatchWidgets-Info.plist`, `Config/DoddyWatch.entitlements`.
- **Tools:** the catalog generator writes the extension's Polish catalog; the capability guard now also scans `DoddyWatchWidgets`.
- **Tests:** `WatchComplicationTests` (4).

## Verified (Linux)
- `WatchComplicationTests` pass (4). `swiftc -parse` on the extension and `WatchLink.swift`. `project.yml` parses as YAML.

## NOT RUN
- No Xcode build. Not known: whether XcodeGen embeds a watchOS app extension into a single-target watch app exactly as written, and whether the extension's bundle id (`<app>.watchkitapp.widgets`) is accepted.
- Never run on a watch: how each size looks on real faces, Always On dimming, and whether the Smart Stack actually raises it before a reminder.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-11 observable_privacy | `ComplicationContent` carries only a time, counts and a list name; "off" leaves nothing on the watch | `testOnlyTimesCountsAndListNamesAreShown`, `testNothingIsShownWhenOffOrNotReady` | Not seen on a real watch face |
| DOD-08 verified_status_and_receipts | The snapshot write is read back before the complications reload | — | — |
| DOD-10 nonmanipulative_companionship | Relevance only from the user's own reminder times; no streaks or prompts | `testTheSmartStackWantsItInTheHourBeforeAReminder` | — |
