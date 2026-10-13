# Apple Watch

**Build:**
- `make project`, scheme `DoddyWatch`: Watch only, for a quick compile.
- `make project`, scheme `Doddy`: builds the iPhone app with the Watch app embedded.
- To run it you need a paired iPhone + Watch simulator with the iPhone app installed. The Watch app only shows what the iPhone sends.

**State:** the code exists (ADR-232, 262, 287, 434, 454). It has **never been compiled or run.** Logic tests pass on Linux.

## What it does
- **Watch app** (`DoddyWatch/`):
  - shows the iPhone's snapshot: pinned notes, the next reminders, lists;
  - tick an item, add to a list, write or dictate a new note;
  - each action is done and read back by the iPhone before the Watch says it happened.
  - No database, no network (enforced by the capability guard).
- **Complications** (`DoddyWatchWidgets/`):
  - "Doddy" shows times, counts and list names only; never a note's words.
  - "New note" opens the note screen (`doddy://watch/new-note`). Nothing records until you tap.
- **iPhone side:** `DoddyApp/Features/Watch/PhoneWatchLink.swift`, through WatchConnectivity.
- **From the iPhone, no Watch code** (iOS 18):
  - the focus, breathing and read-aloud Live Activity has a Smart Stack layout with Pause/Resume (`DoddyWidgets/DoddyToolLiveActivity.swift`);
  - reminder notifications come with Done and Later actions.

## Rules and tests
- **Shared rules:** `DoddyCore` (`WatchLink.swift`, `WatchComplication.swift`).
- **Tests:** `WatchLinkTests`, `WatchListAddTests`, `WatchComplicationTests`, `WatchCaptureLinkTests`.
- **Status docs:**
  - `docs/implementation/APPLE_WATCH_STATUS.md`: the full list of what's NOT RUN;
  - `docs/implementation/WATCH_COMPLICATIONS_STATUS.md`.
