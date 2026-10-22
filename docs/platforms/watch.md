# Apple Watch

> **PAUSED (ADR-572, 21 Oct 2026).** Apple Watch development is on hold while iOS and the web come first. **Nothing here is deleted.** The app (`DoddyWatch/`), the complications (`DoddyWatchWidgets/`), `Config/DoddyWatch*` and the iPhone side (`DoddyApp/Features/Watch/`, `DoddyCore` `WatchLink`/`WatchComplication`) are unchanged. What changed: the Watch targets and scheme left `project.yml` and moved verbatim to `project-watch.yml`, so the iPhone build, the Mac CI job and `scripts/ci.sh` no longer compile or embed the Watch app, and changes to Watch folders no longer start the hosted Mac build. The iPhone still runs `PhoneWatchLink`; with no Watch app installed it sends nothing.

## Re-enabling
1. **Try it first, no other change:** `make project-watch ENABLE_WATCH=1`, then open `DoddyWithWatch.xcodeproj` (schemes `Doddy` and `DoddyWatch`).
2. **Ship it again:** move `DoddyWatch` and `DoddyWatchWidgets` from `project-watch.yml` into `project.yml`'s `targets`; add `- target: DoddyWatch` back to the `Doddy` app's `dependencies` (and to `project-iphone.yml`'s list); move the `DoddyWatch` scheme, `DODDY_WATCH_ENTITLEMENTS` and `deploymentTarget.watchOS` across; delete `project-watch.yml` and its `make` target.
3. **Update the checks:** `scripts/check_platform_specs.py` (it now fails if a Watch target is in `project.yml`) and `scripts/ci_needs_mac.sh` plus its test (take the Watch paths out of the "no Mac build" list so Watch changes run the hosted build again).
4. **Then:** run `scripts/ci.sh` on a Mac. The app has never been compiled (below), so expect compile errors.

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
