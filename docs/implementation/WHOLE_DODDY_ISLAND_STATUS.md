# Whole Doddy island style (ADR-264)
Date: 2026-10-11. Owner: "suggest more tailored designs … with his whole body", "only use assets from these
folders", "make them transparent not white colour on black", "deploy it". The design canvas the owner reviewed
is a private Artifact in the owner's account.

**Built on Linux only. The iOS app has not been compiled or run with this change.**

## What ships
- Settings → Voice → Dynamic Island style gains **Whole Doddy**, next to the V4 styles. Since ADR-267 it is the
  default and listed first; a style the user already picked is kept.
- With it chosen, the expanded voice island draws Doddy's whole body from the owner's pose pack, one pose per state:

| State | Pose |
|---|---|
| Connecting | Stretch (getting ready) |
| Listening | Hand at his ear |
| Thinking | Kneeling, hand on chin |
| Speaking | Open hands |
| Muted | Finger to his lips |
| Lost (stale) | Hand on his head |
| Hey Doddy waiting / paused | Cross-legged / leaning on his box |
| Hey Doddy greeting | A wave (ADR-290, cut from the pack's wave strip) |
| "Save this note?", a reminder waiting or being added | Reaching high |
| Note saved, reminder set | Fist pump (only after the store or Reminders confirmed it) |
| Ended | Fist pump if a note was saved in the conversation (`savedCount`, counted after the store returned the record), otherwise cross-legged (ADR-546; before it the island celebrated every ending) |
| A plan waiting or running | Tiptoe |
| Translating | Language Bridge, as in every style |

- Compact and minimal show a round face cropped from the same pictures: listening while live, shush when muted,
  eyes closed (from the stretch) while Hey Doddy waits or is paused, otherwise the cross-legged smile.
- The island stays black: iOS draws it and apps can't change it. The black outlines get a 1 pt cream edge; there is
  no panel. Orange still means "Doddy can hear you" (LIVE, the bars, the keyline).
- Unchanged here: the V4 styles and the focus and breathing islands. Since ADR-299 the Lock Screen card and the
  read-aloud island use the poses too (`DODDY_WORLD_IN_APP_STATUS.md`).

## Files
- `Shared/IslandArt/IslandPose.swift`: the poses, their figure boxes, the face poses and head positions.
- `Shared/IslandArt/IslandScene.swift`: `IslandStyle.wholeDoddy`, `IslandScene.pose`, `ContentState.wholeDoddyPose`.
- `Shared/IslandArt/IslandViews.swift`: `IslandPoseView`, `IslandPoseFaceView`, `islandCreamEdge`; the expanded,
  compact and minimal views use them when the scene has a pose.
- `DoddyApp/Resources/Assets.xcassets`, `DoddyWidgets/Assets.xcassets`: 12 `WholeDoddy_*` image sets.
  Provenance and hashes in `docs/design/UPLOADED_MEMORY_ASSETS.md`.
- `DoddyApp/Features/Settings/IslandStyleView.swift`: the footnote.
- Checks: `tools/island_boards/IslandSceneChecks.swift` (`wholeDoddy()`), `IslandArtCheck.swift`
  (`--pose-assets`), `scripts/check_island_art.sh` (every picture in both catalogs).

## Verified (Linux, Swift 6.2.1)
- `scripts/check_island_art.sh`: PASS, including the Whole Doddy checks. Planted bugs caught: a wrong pose for
  speaking, and a missing picture in the widget catalog.
- `scripts/ci.sh --core-only`: see the commit message for the run.
- Every changed Swift file parses.

## Not verified (needs a Mac and an iPhone)
Checklist W1–W6: that it compiles (SwiftUI `Image` from the widget's catalog, the shadows), how the poses read at
island size, the cream edge, the face crops, and memory use in the widget extension.

## Decisions for the owner
- ~~Whether Whole Doddy should become the default style~~: yes (owner, 2026-10-11, ADR-267).
- ~~A cut-out wave for the greeting~~: done (owner: "use the wave pose for the greeting", ADR-290).

---

# Island and notification pictures: audit and fixes (ADR-546, 20 October 2026)
Task: refresh the Dynamic Island and notification graphics from the owner's pack, and say honestly what was
checked. **Built and checked on Linux only (Swift 6.2.1). The iOS app, the widget extension and the notification
code have not been compiled or run with this change; the hosted macOS CI is the only compile check.**

## The pack has nothing new
`DODDY-Numbered-Video-Assets-v01` (Google Drive folder `1inLT9oV7wx7UM4P6nxP8yU1-29JV0_ee`) was last modified on
9 Oct 2026. Its three sub-folders (scenery, extra poses, Dynamic Island v4) and the `01-transparent-poses`
folder were created on 9 Oct, and a Drive search of the root, those three, `01-transparent-poses` and the
nested `doddy-extra-poses-expressions-v02` folder for anything modified after 10 Oct found nothing (checked
20 Oct; the other pose-sheet folders were not listed one by one). The repo's image sets were imported on
10–11 Oct, so **no pose was imported, drawn, recoloured or generated**. Every picture below is an existing
`WholeDoddy_*` set that is in both `DoddyApp/Resources/Assets.xcassets` and `DoddyWidgets/Assets.xcassets`
(200×300 and 300×450, unchanged). No row was added to `UPLOADED_MEMORY_ASSETS.md` because nothing was imported.

## Audit (step 1, before any change)
"Pose" below is an image set `WholeDoddy_<pose>`. **Bold** rows were changed.

### Dynamic Island and Live Activities
| Surface | State | Picture before | Picture now | Why |
|---|---|---|---|---|
| Voice island (Whole Doddy, the default) | connecting / listening / thinking / speaking | yawn_stretch / listening / kneeling_inspect / shrug | same | matches the table above |
| | muted / stale | shush / facepalm | same | "can't hear you" / "lost" |
| | Hey Doddy waiting / paused / greeting | crosslegged / leaning / wave | same | |
| | note or reminder waiting, adding | reaching_high | same | |
| | note saved, reminder set | fistpump | same | shown only after the store returned the record or Reminders confirmed (`flashIsland` after `store.save`) |
| | plan waiting / running | tiptoe | same | |
| | translating | Language Bridge board, no pose | same | private mode; the island shows language codes only |
| | **ended** | **fistpump always** | **fistpump if a note was saved, else crosslegged** | **Mismatch.** The island celebrated an ending with nothing saved, while the Lock Screen card (and the face, `proud`/`calm`) already used `savedCount`. One rule now, in `wholeDoddyPose`; the card's copy of it is gone |
| | compact and minimal | round face cropped from listening / shush / yawn_stretch / crosslegged | same | only these four poses have a measured head |
| Voice Lock Screen card | every state | the island's pose | same | `DoddyArt` calls `wholeDoddyPose` |
| Focus, breathing, read aloud (island) | running / paused / done / lost | basketball_dribble, oneleg_balance, belly_reading / crosslegged / fistpump / facepalm (read aloud only) | same | "Time's up" is a clock event the app scheduled, not a store write |
| Focus, breathing, read aloud (Lock Screen card) | all | the V4 board (Tiny Promise, Calm Tide, Story Spool) in a black tile, whatever the style | unchanged | **Flag, not changed:** with Whole Doddy chosen the island shows a pose but this card shows the board. ADR-299 only promised the pose on the voice card, and changing it is a visible design change. Owner decision |
| Alarm snooze | island and Lock Screen | yawn_stretch | same, now `DoddyActivityPose.alarmSnooze` | the mapping is in a file the Linux check compiles |
| **Shopping mode** | **all ticked** | **tiptoe** | **fistpump** | **Mismatch:** "All ticked" was shown with the "on the way" pose. `isFinished` comes from the list as the store holds it (`ShoppingModeState.make(store.list)` after each change), so the fist pump follows the store |
| | **stale** | **tiptoe** | **facepalm** | The card says "Open Doddy to see the list as it is now"; elsewhere a lost card is the facepalm |
| | otherwise | tiptoe | tiptoe | |
| **Doddy's call** | **stale** | **listening** | **facepalm** | He was shown listening to a call the app no longer updates |
| | **ended** | **listening** | **crosslegged** | An ended call may have failed: never the fist pump. Ended beats stale (the card claims nothing that can go out of date) |
| | ringing … ending | listening | listening | unchanged |
| Compact and minimal of alarm, shopping, call | | SF Symbols (`zzz`, `alarm`, `cart`, count, `phone.arrow.up.right`) | unchanged | **Flag:** no picture. They carry the time, the count and the call; a face crop would need a head box measured from the pack art. Not done |
| Island background and edge | | black, 1 pt cream edge (`islandCreamEdge`), orange only while he can hear you | unchanged | |

### Notifications (all local; titles and bodies unchanged)
| Notification | Picture before | Picture now | Why |
|---|---|---|---|
| Note reminder (time, place, repeating) | reaching_high | same (`.noteReminder`) | the same pose as the island's "reminder waiting" |
| Morning check-in | yawn_stretch | same (`.morningCheckIn`) | |
| Birthday | wave | same (`.birthday`) | |
| Evening wrap-up, weekly look-back | crosslegged | same (`.eveningWrapUp`, `.weeklyLookBack`) | |
| **Leave by** ("Time to leave") | **none** | **tiptoe** (`.leaveBy`) | on the way, as in shopping mode |
| **Tidy up** (weekly) | **none** | **kneeling_inspect** (`.tidyUp`) | kneeling to look the notes over |
| **Focus done** | **none** | **fistpump** (`.focusDone`) | the same pose as the island's "Time's up". It is the timer the app scheduled and cancels when the focus is stopped; it is not a store write |
| Event nudge (`DeviceConnections.scheduleNudge`, title "Doddy") | none | none | **Flag, left:** generic wording, not in the task's list. Owner decision |
| "Timer done" (`DeviceConnections.scheduleTimer`) | none | none | **Flag, left:** a kitchen timer is not a moment for the fist pump. Owner decision |
| Remote pushes (`server/messaging/src/providers/apns.ts`: server notifications and texts) | none | none | **Flag, not done:** a picture on a remote push needs a notification service extension and `mutable-content`. `project.yml` has no such target (extensions: widgets, share, watch). A new extension target, App ID and signing is not "the smallest change" and cannot be compiled here. Owner decision |
| Live Activity pushes (`apns.ts` `sendLiveActivity`) | | | No change: they carry a phase and times; the widget draws the picture |

Imported sets **not** used on these surfaces, on purpose: `WholeDoddy_sneaky_crouch` (Settings, "Pause all
connections"), `WholeDoddy_turned_away` (Home widget, hidden notes), `UploadedDoddy_*` (memory screens; the three widget
copies in `DoddyWidgets/Assets.xcassets` are not referenced by any Swift file in the widgets or `Shared`),
`DoddyMotion_*` and `VoiceDoddy_talking_*` (animations; a Live Activity cannot animate and the widget catalog does
not have them), `WidgetDoddy_face` (Home widget). They stay in the repo.

## What changed
- `Shared/IslandArt/IslandScene.swift`: the island's `ended` pose needs a saved note for the fist pump.
- `Shared/IslandArt/IslandPose.swift`: `DoddyActivityPose` (alarm, shopping, call) and `DoddyNotificationKind`
  (eight kinds). Plain values in, a pose out, so the Linux check compiles them.
- `DoddyWidgets/ShoppingLiveActivity.swift`, `DoddyCallLiveActivity.swift`, `AlarmLiveActivity.swift`,
  `DoddyVoiceLiveActivity.swift`: call the mappings; no pose is named in these files any more.
- `DoddyApp/Infrastructure/Connections/NotificationArt.swift`: `attachment(for: DoddyNotificationKind)` is now the
  only way to get a picture. Behaviour is unchanged: no picture when "Hide Doddy's pictures" is on, a fresh copy
  per request, and a failed copy returns nil so the notification is never held up.
- Call sites: the five existing notifications moved to kinds; Leave by, Tidy up and Focus done gained a picture.
- Checks: `IslandSceneChecks.activitiesAndNotifications()`, the stricter `ended` assertions in `wholeDoddy()`,
  `--notification-kinds` in `IslandArtCheck.swift`, and greps in `scripts/check_island_art.sh` (below).

## What `scripts/check_island_art.sh` now catches
- A wrong pose for any shopping, call, alarm or notification state (the Swift assertions).
- A new notification kind nobody added to the check; a fist pump on any notification other than focus done.
- An ended conversation that celebrates with nothing saved; an ended call that celebrates.
- A notification kind whose scheduler file stops naming it, or a call that passes a raw pose again.
- A file in `DoddyApp` that builds a `UNMutableNotificationContent` with no picture, unless it is
  `DeviceConnections.swift` (the two flagged above).
- A pose named directly in the alarm, shopping or call widget files.
The greps prove the files use the mappings. They do not prove the SwiftUI compiles or draws.

## Verified (Linux, Swift 6.2.1, 20 Oct 2026)
- `scripts/check_island_art.sh`: PASS ("96 island drawings parse and fit their view boxes; scene checks pass"),
  including the new `activitiesAndNotifications()` assertions and the grep guards.
- `scripts/ci.sh --core-only`: "RESULT: PASS for core-only scope; iOS app NOT verified". DoddyCore 1,169 tests,
  0 failures; "App logic type-check (non-UI app files)" PASS; "Dynamic Island art and scenes" PASS; the messaging
  server database tests SKIPPED (no `TEST_DATABASE_URL`). The same command on the untouched commit `f3bd10d` gave
  the same result and the same 1,169.
- Planted bugs, each one made the script exit 1 and was reverted: `.leaveBy` mapped to the fist pump; the
  shopping Lock Screen naming `.tiptoe` directly; the island celebrating an ended conversation (caught by the grep
  guard, and, spelled to evade it, by the Swift assertion "ended with nothing saved is not a fist pump"); the
  Tidy up picture removed; Birthdays back to a raw pose; an ended call mapped to the fist pump.
- Not run by anything here: the app and widget compile, the UI tests, simulator screenshots.
- **Hosted CI:** `.github/workflows/ios.yml` runs only on `pull_request` and `workflow_dispatch`, so pushing this
  branch started no run. Dispatching it by hand always runs the macOS job (about 52 minutes at $0.062 a minute,
  roughly $3). Nobody has done that, so **the app, widget and notification code have not been compiled by anything**.

## Not verified here (needs a Mac and an iPhone)
Everything the Linux check cannot reach: the app and widget compile (hosted macOS CI is the first), the UI tests,
simulator screenshots, and a real notification on a phone. Added to `MAC_VERIFICATION_CHECKLIST_2026-10-10.md`
as section 4z (N1–N6), with W1–W6 above: pose legibility at island size, the cream edge, face crops, widget
memory, and a real notification showing its picture.

## Decisions for the owner (ADR-546)
1. Tool Lock Screen cards (focus, breathing, read aloud): keep the V4 board, or show the island's pose?
2. ~~Event nudge and "Timer done": a picture, and which pose?~~ Decided 20 Oct ("pick sth"): the reach, as for a reminder, not the fist pump (ADR-547).
3. ~~Remote pushes: add a notification service extension so server notifications carry a picture?~~ Skipped for now (owner, 20 Oct). Still no picture on server pushes.
4. Compact and minimal views of alarm, shopping and call: keep symbols, or measure heads for face crops?
5. The in-app voice screen (`VoiceScreenArt.shown(.ended)`) still shows the fist pump for every ended
   conversation. It is not a Live Activity or a notification, so it was left; it has the same flaw the island had.

## Follow-up, 20 October 2026 (ADR-547)
- **Breathing is removed** (owner: "remove breathing, no need for that"): the Breathe screen and its Home menu entry,
  `BreathingController`, the breathing Live Activity kind and its Calm Tide island scene, `BreathingSession` and
  its tests (`FocusAndBreathingTests.swift` is now `FocusTests.swift`), the `WholeDoddy_oneleg_balance` pose and
  its two image sets, and eight now-unused strings in the ten language tables. The rows above that mention breathing
  describe the state before this. The Calm Tide drawing stays in the generated board data, which mirrors the pack.
  An activity left running by an older build with kind `breathing` can no longer be decoded and just disappears.
- **Event nudge and "Timer done" now have a picture** (`DoddyNotificationKind.eventNudge`, `.timerDone`): the reach.
  Every local notification has one; the check fails if one is added without.
- Remote pushes still have none (decision 3 skipped).
- **Verified after this follow-up (Linux, Swift 6.2.1):** `scripts/check_island_art.sh` PASS; `scripts/ci.sh --core-only`
  "RESULT: PASS for core-only scope; iOS app NOT verified", DoddyCore 1,166 tests (1,169 before, minus the three
  breathing tests), 0 failures, messaging database tests SKIPPED; `build_strings_catalog.py --check` PASS. Planted
  bugs (the timer notification losing its picture; `timerDone` mapped to the fist pump) each failed the check and were
  reverted. **Not compiled or run:** the app, widget extension, UI tests; no hosted CI run exists for the branch.
