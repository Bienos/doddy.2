# Launch profiling (ADR-547)

**Status 2026-10-20: written, never measured.** The launch change below was made on Linux with no Xcode and no iPhone. Nothing here shows Doddy starts faster; the signposts exist so you can find out. Until the table at the end has numbers, don't say "faster".

## What changed

`DoddyApp` used to start 14 `.task` jobs with the first frame, all on the main actor. Now (`DoddyApp/App/LaunchWork.swift`):

| When | Jobs |
|---|---|
| Right after the first screen (the profile has loaded) | learning reload, notification categories, shopping-mode reattach, shared lists' local load (`Early jobs`) |
| 1.5 s later, one at a time, 0.3 s apart | push-token sync, shared lists sync and live updates, morning check-in, tidy up, evening wrap-up, weekly look back, birthdays |

Every job still runs; none was removed. A shared-lists sync is also asked for when Doddy comes to the front, and at a cold launch that made two passes (`syncAll()` queues a second pass when one is running). `syncAllUnlessRecent()` (launch and foreground) skips one that is running or ended in the last 5 s. "Sync now", opening a list and local changes still call `syncAll()`.

What can look different: the shared-lists badges and the notification schedules appear up to a few seconds after launch instead of at once. Not changed: `RootView`'s own repeats at launch (`refreshOnForeground`, `MemoryCopySync`, `heyDoddyAppBecameActive` each run from the launch task and from the first `.active`); measure first.

## Signposts

Subsystem: the app's bundle id (`Bundle.main.bundleIdentifier`). Category: `Launch`.

| Name | Kind | Meaning |
|---|---|---|
| `Launch to first screen` | interval | start of `DoddyApp.init` until the profile has loaded and Home (or the introduction) is built; not the same as the first frame drawn |
| `App.init` | interval | `DoddyApp.init` alone |
| `Notes load` | interval | `store.reload()` in `RootView` |
| `First screen shown` | event | the moment `Launch to first screen` ends |
| `Early jobs` | interval | the jobs in the first table row |
| `Push token`, `Shared lists sync`, `Morning check-in`, `Tidy up`, `Evening wrap-up`, `Weekly look back`, `Birthdays` | intervals | the later jobs, each timed alone |

## How to measure (on a real iPhone, a Release build)

1. **Build:** in Xcode choose the `Doddy` scheme and your iPhone, then Product › Profile (⌘I). Profiling builds the Release configuration. The simulator's numbers don't count.
2. **Template:** choose **App Launch** and keep whatever instruments it comes with. Add the **os_signpost** instrument from the Library (⇧⌘L) so the signposts below show. (The exact lane names differ between Xcode versions; check what yours shows before you trust a label here.)
3. **Same conditions every run:** iPhone unlocked and on the charger or above 50%, Low Power Mode off, airplane mode off, the same Wi-Fi, iCloud signed in. Note whether you have shared lists, birthdays, and the check-ins turned on: they decide how much work there is.
4. **Cold launch:** swipe Doddy away in the app switcher, wait 30 s, then press Record. Let it run 15 s after Home shows, then stop. Do this 5 times.
5. **Read:** in the os_signpost track filter by category `Launch`. For the launch time, use the template's launch lane, the one that ends at the first frame drawn. Write the median of 5.
6. **Compare** with the build before this change: check out `f3bd10d` (the commit before ADR-546 and ADR-547 on this branch), build and profile it the same way. The signposts don't exist there, so use the template's launch time to the first frame.

## Results (fill in)

| Build | iPhone and iOS | Launch time to first frame (median of 5) | Launch to first screen | Notes load | Longest later job | Notes |
|---|---|---|---|---|---|---|
| `f3bd10d` (before) | | | n/a | n/a | n/a | |
| this branch | | | | | | |

If the launch time to the first frame doesn't move, the 14 jobs weren't the cost and the next suspects are `App.init` (the 15 wiring steps) and `Notes load`. If a later job takes seconds, that is the one to look at.
