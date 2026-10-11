# Everyday iPhone moments status (ADR-337 to ADR-343)
Date: 2026-10-11. Owner: "can you code these if we don't have already that", with the Review Gallery
`Doddy-22-iPhone-Moments-v1/Review-Gallery.html` (22 lifestyle directions, each marked "Concept —
requires device validation"). Only the gallery page reached the repository; its 22 images,
implementation notes, contact sheets and review deck did not, so the mapping below goes by each
moment's title and one-line description. **Nothing in this round has been compiled with Xcode.**

## The 22 moments against the code
| # | Moment (gallery) | Surface | In Doddy | Where |
|---|---|---|---|---|
| 01 | Walking voice companion | Dynamic Island / Live Activity | **Already built** (ADR-053, 238–240, 264) | `DoddyWidgets/DoddyVoiceLiveActivity.swift` |
| 02 | Café focus timer | Dynamic Island / Live Activity | **Already built** (ADR-241) | `Features/Focus/`, `DoddyToolLiveActivity.swift` |
| 03 | Cooking countdown | Lock Screen Live Activity | **Built now: ADR-337.** A timer by voice used to be a notification only | `Features/Tools/CountdownController.swift`, `CountdownView.swift` |
| 04 | Brief capture confirmation | Transient expanded island after a save | **Built now: ADR-338** ("Note saved" for 8 s). Before, only inside a voice conversation (ADR-240) | `Features/Tools/SavedNoteIsland.swift` |
| 05 | Lock Screen voice status | Lock Screen Live Activity | **Already built** (ADR-053, 106, 266) | `DoddyVoiceLiveActivity.swift` |
| 06 | Lock Screen capture stamp | Lock Screen circular widget | **Built now: ADR-339** ("New note" circle). Before, only the iOS 18 control | `DoddyWidgets/HomeWidgets.swift` (`NewNoteWidget`) |
| 07 | Upcoming commitment widget, privacy-redacted | Lock Screen rectangular widget | **Already built** (ADR-219: "Next reminder", `privacySensitive`, words only with the setting) | `HomeWidgets.swift` (`NextReminderWidget`) |
| 08 | Static paper wallpaper | Lock Screen wallpaper | **Built now: ADR-341** (the app draws it; the user sets it) | `Features/Wallpaper/WallpaperView.swift` |
| 09 | Requested reminder follow-up, expanded actions | Notification | **Already built** (ADR-190, 211: Open, In 1 hour, Tomorrow 09:00, Done) | `Infrastructure/Connections/NoteReminderNotifications.swift` |
| 10 | Arrival reminder | Location-triggered notification | **Already built** (ADR-196, `UNLocationNotificationTrigger`, While Using only) | `PlaceLocation.swift` |
| 11 | Focus timer finished | Notification | **Already built** (ADR-241, "Focus done") | `FocusController.swift` |
| 12 | Thought ready for review | Passive Notification Center item, opt-in schedule | **Built now: ADR-342** | `Features/Review/ThoughtReviewViews.swift`, core `ThoughtReview.swift` |
| 13 | Expanded paper notification | Notification content extension | **Built now: ADR-343** (new target `DoddyNotificationContent`) | `DoddyNotificationContent/`, `Config/DoddyNotificationContent-Info.plist` |
| 14 | Home Screen capture tile | Small Home Screen widget | **Built now: ADR-339** (the same "New note" widget, small size) | `HomeWidgets.swift` (`NewNoteWidget`) |
| 15 | Saved-thought shelf | Small Home Screen widget with a count | **Built now: ADR-340** | `HomeWidgets.swift` (`SavedNotesWidget`), core `WidgetSnapshot.Shelf` |
| 16 | StandBy bedside widget, system night rendering | StandBy small widget | **Already built** (ADR-313 "Doddy, resting"); **night rule added now** (ADR-337: no picture when `isLuminanceReduced`) | `HomeWidgets.swift` (`DoddyRestView`) |
| 17 | StandBy wind-down activity | StandBy Live Activity | **Built now: ADR-337** (Home → Wind down; its Lock Screen card is what StandBy shows) | `CountdownController.swift`, `CountdownView.swift` |
| 18 | In-app vellum capture | Capture sheet | **Already built** (M1, ADR-180) | `Features/Capture/CaptureView.swift` |
| 19 | Control Center capture | Control (iOS 18) | **Already built** (ADR-180 "New note" control) | `DoddyWidgets/NewNoteControl.swift` |
| 20 | Lock Screen capture control | Lock Screen control slot (iOS 18) | **Already built** (the same control) | `NewNoteControl.swift` |
| 21 | Siri, Shortcuts, Action Button | App Shortcuts | **Already built** (ADR-040, 179, 180, 226, 248). The gallery's phrase is "Capture with Doddy"; Doddy's are "New note in Doddy" and "Save to Doddy" | `DoddyApp/Intents/DoddyShortcuts.swift` |
| 22 | User-configured Back Tap | App Shortcut run by Back Tap | **Already built** (ADR-041, 084; owner-tested on an iPhone on 2026-10-09) | `Features/Setup/BackTapSetupView.swift` |

Thirteen moments already existed; this round adds the other nine as seven decisions (ADR-337 to
ADR-343 in `DECISIONS.md`). The gallery's own looks (its images) were not seen; the islands use the
owner's V4 boards as every island does (ADR-238), and the widgets and cards the app's paper colours.

## What ships

### ADR-337 Countdown timers: the kitchen timer and the wind-down
- **Home → Timer:** 3, 5, 10 or 15 minutes and an optional line ("Pasta"). **Home → Wind down:** 5,
  10, 15 or 20 minutes, no line. Pause, Resume, Stop on the screen and on the island; one countdown
  of each kind at a time, kept in UserDefaults so it survives the app being closed.
- **By voice**, "set a timer for ten minutes" (`set_timer`, ADR-065) now starts the same countdown:
  it shows on the island and the Lock Screen instead of being a notification only. The old
  `DeviceConnections.startTimer` is gone; the voice reply is unchanged (set, or "not confirmed").
- **Island and Lock Screen:** the focus board (Tiny Promise) with "TIMER" or "WIND DOWN", the time
  left ticking, the label, and Pause/Stop pills. Whole Doddy kneels to watch a timer and stretches
  sleepily through a wind-down; a wind-down ends cross-legged, not with a fist pump. Stale at the
  end means "Time's up", never a running count (the end time is the stale date, as for focus).
- **StandBy:** iOS shows a Live Activity's Lock Screen card in StandBy, so the wind-down is there
  with nothing but the time. The "Doddy, resting" widget now leaves his picture out when
  StandBy's night mode dims the screen (`isLuminanceReduced`), showing only the next reminder's time.
- **Notification** when the time runs out: "Timer done" with the user's label, or "Wind-down over ·
  Time to put the phone down" (Polish too), time-sensitive. Added to iOS, then read back from the
  pending list; the screen says when iOS didn't confirm it. Stop cancels exactly that one.
- Doddy never checks whether the phone was put down or the pasta drained.

### ADR-338 "Note saved" in the Dynamic Island
- After a note is saved on the capture screen **and read back** from the store, a Live Activity
  shows the conversation's saved card ("NOTE · Saved · Note saved · Kept in Doddy on this iPhone",
  fist pump with Whole Doddy) and the app ends it after 8 seconds. Never the note's words.
- Settings › Appearance: "“Note saved” in the Dynamic Island", on unless turned off. Off, or with
  Live Activities off for Doddy in iOS, nothing shows and the save is unchanged.
- A card left by a killed app is removed at the next launch with the other leftovers.

### ADR-339 The "New note" widget
- Small Home Screen tile (Doddy leaning in, or the pencil symbol on tinted Home Screens and with
  "Hide character artwork") and a Lock Screen circle. A tap runs `NewNoteIntent`, the same as the
  Control Center control: Doddy opens on an empty capture screen; nothing is saved until Save.

### ADR-340 The saved-thought shelf widget
- Small, Lock Screen circular, rectangular and inline: how many notes are saved, how many in the
  last seven days, and when the last one was. Counts only, never words. Lists and private notes
  (ADR-310) aren't counted. A tap opens Memories (`doddy://memories`).
- The widget snapshot carries an optional `shelf`; snapshots from before still read and the
  widget then says "Open Doddy once". The snapshot is rewritten when the counts change.

### ADR-341 Lock Screen wallpaper
- Settings › Appearance › Lock Screen wallpaper: light or dark paper, and Doddy sitting,
  stretching, listening, waving, or paper only (paper only when character artwork is hidden). The
  app draws the picture at this iPhone's own pixel size (`ImageRenderer`, scale 1) with the clock
  band and the controls band kept clear (`WallpaperLayout`, tested), then hands it to the share
  sheet as PNG. "Save Image" puts it in Photos; the user picks it under iOS Settings › Wallpaper.
- The screen says plainly that iOS lets no app set the wallpaper. Nothing of the user's is in the
  picture, and no photo-library permission is asked for (the share sheet handles the save).

### ADR-342 "A thought is ready for review"
- Settings › A thought to review: off by default; a time (19:30 to start). When on, Doddy puts
  **one** passive notification in iOS for the next chosen time, for the one note `ThoughtReview.due`
  picks: a note (never a list, never a private note) saved at least 7 days ago and never reviewed,
  newest such first, so a note comes back about a week after it was saved; otherwise the note
  reviewed longest ago, once 30 days have passed. Deterministic and tested.
- Passive: no sound, no banner; it waits in Notification Center. It names no note. A tap, or
  "Open the note" on a long press, opens that note in Doddy and writes the review in a log of ids
  and dates (`thoughtReview.log` in UserDefaults). The schedule is rebuilt at every launch and
  return to the foreground, so a deleted note is never offered and the log can't name notes that
  are gone. If the app isn't opened, the one pending notification fires once and nothing follows.
- No streaks, scores or nudges; nothing is sent anywhere.

### ADR-343 The expanded paper notification
- A new notification content extension, `DoddyNotificationContent`, for the three note reminder
  categories and the review category. On a long press iOS shows Doddy's paper card (eyebrow,
  title, words, the pose picture when the notification carries one) instead of its plain expanded
  banner; the actions still come from the category. The unexpanded banner is unchanged.
- The extension shows only what is in the notification it was handed: no App Group, no database,
  no network, no permissions, and it changes nothing. Timers, check-ins and the other notifications
  keep iOS's own expanded view.
- Added to `project.yml` (embedded in the app, linked only to `DoddyDesignTokens`), the capability
  guard's scanned folders and the Polish catalog builder.

## Files
- **Core (`Packages/DoddyCore`):** `CountdownSession.swift`, `ThoughtReview.swift`,
  `WallpaperLayout.swift`; `WidgetSnapshot.swift` (`Shelf`, `shelf(_:now:)`).
- **Shared:** `ToolActivity/DoddyToolAttributes.swift` (kinds `timer`, `windDown`, `noteSaved`);
  `IslandArt/IslandScene.swift` (their scenes and poses, `length(_:)`).
- **App:** `Features/Tools/CountdownController.swift`, `CountdownView.swift`, `SavedNoteIsland.swift`,
  `ToolLiveActivity.swift` (stale rules); `Features/Review/ThoughtReviewViews.swift`;
  `Features/Wallpaper/WallpaperView.swift`; `Features/Home/HomeView.swift` (two tiles);
  `Features/Capture/CaptureView.swift` (the saved card); `Features/Settings/SettingsView.swift`
  (review section, wallpaper link, saved-island switch); `Features/Widgets/WidgetSync.swift` (shelf
  changes rewrite the snapshot); `Features/Voice/VoiceSessionController.swift` and
  `Infrastructure/Connections/DeviceConnections.swift` (voice timers through the controller);
  `Infrastructure/Connections/NoteReminderNotifications.swift` (review and countdown taps);
  `App/DoddyApp.swift`, `App/RootView.swift` (restore, refresh, `PreferenceKey.savedIsland`).
- **Widgets:** `HomeWidgets.swift` (`NewNoteWidget`, `SavedNotesWidget`, night rule, preview
  shelf), `DoddyWidgetsBundle.swift` (eight Home Screen entries), `DoddyWidgetPreviews.swift`.
- **Extension:** `DoddyNotificationContent/NotificationViewController.swift`,
  `Config/DoddyNotificationContent-Info.plist`, `project.yml`.
- **Checks and tools:** `tools/island_boards/IslandSceneChecks.swift`,
  `scripts/check_forbidden_capabilities.sh`, `tools/build_strings_catalog.py`, `l10n/pl.json`
  (30 Polish lines) and the generated `Localizable.xcstrings` files.
- **Tests:** `CountdownSessionTests` (7), `ThoughtReviewTests` (9), `WallpaperLayoutTests` (5),
  `WidgetSnapshotTests` (+1).

## Verified (Linux, Swift 6.1.2, 2026-10-11)
| Step | Result |
|---|---|
| `swift test --package-path Packages/DoddyCore` | PASS: 793 tests, 0 failures (771 before this round, 22 new) |
| `scripts/check_island_art.sh` | PASS: 96 drawings; scene checks incl. the timer, wind-down and note-saved scenes, poses, stale rules and raw values |
| `scripts/check_forbidden_capabilities.sh` | PASS (now scans `DoddyNotificationContent/` too; no new permission) |
| `scripts/typecheck_app_logic.sh` | PASS: 18 app files (the new controllers import UserNotifications/SwiftUI and are outside its scope) |
| `python3 -I tools/build_strings_catalog.py --check` | PASS: 1205 of 1234 UI strings in Polish |
| `python3 -I scripts/verify_imported_pack.py` | PASS |
| `swiftc -parse -swift-version 6` | PASS on every new and changed Swift file (syntax only) |
| `Config/DoddyNotificationContent-Info.plist` | parses |
| `scripts/ci.sh --core-only` | exit 0: every core step PASS (pack, guard, agent specs, blog, Polish catalogs, DoddyCore tests, app-logic type-check, island checks, token server, backend, gateway and messaging server tests); iOS app build + tests NOT RUN |

## NOT RUN / UNVERIFIED (needs a Mac and an iPhone)
- **No Xcode build.** SwiftUI, WidgetKit, ActivityKit, App Intents, `ImageRenderer`, `ShareLink`
  and the content extension are parsed only. `UIScreen.main` in `WallpaperView` is a deprecated
  API that still compiles; a future pass can read the size from the window scene instead.
- **ADR-338 is the open question of this round:** whether iOS shows an app's **own** Live Activity
  in the Dynamic Island while that app is in front. If it doesn't, the card shows on the Lock
  Screen and from other apps only, and the owner decides whether to keep it (Mac checklist 4m, S2).
- Voice timers through the controller: the agent's spoken reply and the island together.
- The content extension's size (`UNNotificationExtensionInitialContentSizeRatio` 0.35 then
  `preferredContentSize`), its appearance in light and dark, and that the attachment picture reads.
- The passive review notification's behaviour in Notification Center; the log after a tap.
- The wallpaper's pixel size on each iPhone, and that "Save Image" lands in Photos without a prompt.
- StandBy: the wind-down card and the rest widget at night.

## Decisions for the owner
- Keep "Note saved" in the island on by default, or off (it is on; Settings turns it off).
- The review time's default (19:30) and the 7-day / 30-day rule.
- The gallery's "Capture with Doddy" phrase: rename the "New note" App Shortcut, or keep both names.
- The gallery's own visual designs for these moments were not seen; if they differ from the V4
  boards and the paper colours used here, design should say where.

## Constitution evidence log (`docs/trust/config/doddy_rules.yaml`)
| Rule | What enforces it here | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-08 verified_status_and_receipts | A countdown's "done" notification is read back from iOS's pending list (`CountdownController.schedule`); the voice reply says "not confirmed" otherwise. "Note saved" starts only after `MemoryStore.save` returned the record (`CaptureView.save`). The review notification is read back after `add`. The shelf shows counts from the snapshot the app wrote and read back | `CountdownSessionTests`, `WidgetSnapshotTests` | iOS behaviour NOT RUN |
| DOD-06 user_controlled_relevant_memory | The review log holds ids and dates only; private notes and lists are never offered (`PrivateNotesStore.shareable`, `ThoughtReview.due`); deleted notes drop out at every rebuild | `ThoughtReviewTests` | — |
| DOD-11 observable_privacy | No notification, island, widget or wallpaper carries note words except where ADR-190's setting already allows it (the reminder body, which the content extension only redraws). The content extension has no App Group, network or permissions; the guard scans it | capability guard | Extension NOT RUN |
| DOD-10 nonmanipulative_companionship | No streaks, scores or nudges in the review; a wind-down says only that it ended; Doddy doesn't claim to know what the user did | — | — |
| DOD-07 scoped_action_approval | The wallpaper is never set by the app; the user saves and chooses it. A widget tap only opens a screen | — | — |
| T35/T42 honest capability claims | The screens say iOS can't let apps set wallpaper, that a review names no note, and that Doddy doesn't check what the user did | — | Nothing here is "tested on a device" |
