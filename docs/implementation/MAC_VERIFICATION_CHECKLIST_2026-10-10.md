# Mac and iPhone verification checklist (branch `claude/hopeful-fermat-1a63x0`)

Date: 2026-10-10 (updated for ADR-210 to ADR-225). Everything below was written and tested only on Linux (`scripts/ci.sh --core-only`,
486 Swift package tests, gateway and backend tests). **None of the app code has been compiled with Xcode or
run on a device.** Nothing here is verified until a person ticks it. Record the Xcode version, the device
and the result for each item in the table at the end.

## 0. What is already compiled
Since ADR-200, `scripts/typecheck_app_logic.sh` compiles eleven non-UI app files (`MemoryStore`,
`MemoryStore+Lists`, `ShortcutRouter`, `ProfileStore`, `ConversationLogStore`, `AskController`, `PersonalityPreferences`,
`PinnedNotesStorage`, `NoteReminderStore`, `PhotoFiles`, `WidgetSnapshotFile`) against the real DoddyCore module on Linux, and they pass. Everything else in
the app (SwiftUI views, the App Intents, the widget control, anything using UIKit, AVFoundation or
EventKit, and `PlaceLocation`, which the check replaces with a stub) has still never been compiled.

## 1. Build first
1. `xcodegen generate`, then `scripts/ci.sh` (the full run, not `--core-only`). Note the output.
2. If the app does not compile, these are the places most likely to need a one-line fix:
   - `DoddyApp/Intents/SaveToDoddyIntent.swift` and `FindInDoddyIntent.swift`: the `@Parameter(...)` arguments and `parameterSummary`.
   - `DoddyApp/Features/Memories/MemoriesView.swift`: `ForEach(choices, id: \.category)` over a tuple array; `let` statements inside the `ForEach` closure; `&pinnedRaw` passed inout inside a `Button` closure.
   - `DoddyApp/Features/Capture/CaptureView.swift`: `PasteButton` mutating `@State` in its `onPaste` closure. If Swift 6 calls it a Sendable-closure error, wrap the body in `MainActor.assumeIsolated { ... }`.
   - `VoiceView.swift` and `MemoryDetailView.swift`: `Picker(selection: Binding(get:set:))` that touches a main-actor object in `set`. Same pattern already builds in SettingsView; if it errors, make the closure `@MainActor`.
   - `DoddyApp/Features/Memories/MemoryDetailView.swift`: `PinnedNotes.toggle(_, stored: &pinnedRaw, ...)` on an `@AppStorage` property.
   - `DoddyApp/Features/Settings/SettingsView.swift`: `.fileImporter`, the `ProxyRepresentation` in `ProfileTextExport`, the two `confirmationDialog(... presenting:)` calls.
   - `DoddyApp/App/RootView.swift`: `$router.shownDraft` (a computed get/set on an `@Observable` class), `onChange(of:initial:)`.
   - `DoddyWidgets/NewNoteControl.swift` and `DoddyApp/Intents/DoddyShortcuts.swift` (four App Shortcuts).
   - New in this round, most likely to need a fix:
     - `Features/Photos/PhotoViews.swift`: `PhotosPicker` with `photoLibrary: .shared()`, and `loadTransferable(type: Data.self)`.
     - `Features/Photos/PhotoTextReader.swift`: `Task.detached` returning a non-`Sendable` UIImage path (only `Prepared` crosses), and the `VNRecognizeTextRequest` options.
     - `DoddyWidgets/HomeWidgets.swift`: `AppIntentConfiguration`, `ListEntity`/`EntityQuery` conformances, `Button(intent:)` in a widget, and `Text(date, format:)` interpolated into `Text`.
     - `Shared/Widgets/ToggleListItemIntent.swift`: a `LiveActivityIntent` with `@Parameter`s and a custom `init`; `authenticationPolicy`.
     - `Features/Backup/BackupViews.swift`: `.fileExporter(isPresented:document:contentType:defaultFilename:)`, `FileDocument`, `UTType(filenameExtension:conformingTo:)`.
     - `Features/MorningCheckIn/MorningCheckInViews.swift`: `.onChange(of: settings)` (needs `Equatable`, which it is), and `DatePicker` with a computed `Binding<Date>`.
     - `VoiceSessionController.swift`: `conversation?.agentAudioTrack?.volume` (LiveKit `RemoteAudioTrack`, SDK 3.3.1).
     - `DoddyApp/Resources/Localizable.xcstrings` is hand-generated: check that Xcode accepts it and lists `pl` under the project's localizations.
3. Run the unit and UI tests. The new app test is `MemoryStoreTests.testPhotoFollowsItsNoteThroughDeleteUndoAndRemove`. The existing UI tests save one note per run in an empty store, so the duplicate warning should not change them.

## 2. Memories
| # | Do this | Expect |
|---|---|---|
| M1 | Save "Gate code 4821". Save "gate  CODE 4821." again | "You saved this already" with the date, "View the saved note" and "Save it again anyway". Editing the text clears it (ADR-184) |
| M2 | Save notes of two or more types | A chip row (All, then each type with a count) above the list. Tapping a chip filters; tapping it again clears it (ADR-182) |
| M3 | Menu at the right of "YOUR SAVED NOTES" | Newest first, Oldest first, Recently changed. The choice is remembered after a relaunch (ADR-186) |
| M4 | Open a note → Pin to the top | A pin icon on its card and it moves to the top. An 11th pin shows "You can pin up to 10 notes". Deleting everything clears the pins (ADR-187) |
| M5 | Press and hold a card | Pin/Unpin, Copy text, Share text (ADR-188) |
| M6 | Note screen → Share text | The share sheet holds only the note's current words (ADR-185) |
| M7 | Delete one note | A "Note deleted. Undo" bar for about 10 seconds. Undo brings back the same text, corrections and dates. "Delete all" shows no bar (ADR-183) |
| M8 | Search for something with two notes that give different numbers | A "may disagree" banner and labels (ADR-171) |
| M9 | Copy some text elsewhere, open the capture screen, tap Paste | No permission prompt. The text goes in exactly as copied, replacing a blank editor or going on a new line after existing text. Nothing is saved until Save (ADR-189) |
| M10 | Open a voice-saved or "Other" note → Type menu → pick "Place" | The type changes at once and the type filter chips update. The text, dates and "Edited" label stay as they were (ADR-192) |
| M11 | Search for a word used by notes of two or more types | The same chips above the matches. A chip narrows them and says "Showing N of M matches". The "may disagree" banner still counts every match (ADR-199) |
| M12 | Correct one note three times (A → B → C → D), then open it | "Earlier versions (2)" lists C then B, each with its time. "Original capture" shows A. Relaunch: the same. Delete and Undo: the same. Search for a word only in B: no match (ADR-236) |
| M13 | Search "netflix password" with a wifi password note saved; then ask the same by voice | Find: "1 PARTIAL MATCH" and "No saved note mentions “netflix”…" above the wifi note. Voice: Doddy says no note mentions Netflix and does not read the wifi password out as the answer (ADR-235) |

## 2b. Accessibility (PRD item 7, acceptance test A-13)
| # | Do this | Expect |
|---|---|---|
| A1 | iOS Settings → Accessibility → Motion → Reduce Motion on. Run a voice conversation and the Ask screen; step through first-use onboarding | Scrolling to new messages and the onboarding steps are instant, not animated (ADR-201) |
| A2 | Largest Dynamic Type and VoiceOver on the new screens: type chips, sort menu, pin, undo bar, duplicate warning, remembered conversations | Everything reachable and readable; chips announce "Place, 2 notes" and "selected"; no clipped text |

## 3. Export, restore and settings
| # | Do this | Expect |
|---|---|---|
| E1 | Settings → About you → Export with your settings (JSON and text) | A file with the profile answers and voice/personality choices. Change a voice setting, return and export as text again: the new value is included (ADR-176) |
| E2 | Export memories as JSON, delete one note, then Restore from a JSON export and pick the file | A preview with counts, then "Added 1 note". Notes already on the phone are not replaced (ADR-178) |
| E3 | Restore a text file, an empty file and a hand-edited file with one note broken | A plain message each time and nothing added |
| E4 | Settings → What Doddy knows → Remembered conversations | The list, a full conversation, "Brought up next time" marks, delete one with confirmation, export as text (ADR-177). Delete from inside a conversation: it goes back one screen, not two |
| E5 | Settings → Your memories → Export as Markdown, then open the file in Notes or Files | A file named doddy-memories.md (check it is not .md.txt) with one heading per note, the words in a block quote, and the original for a corrected note (ADR-203) |
| E6 | With the M12 note: export as JSON, text and Markdown; delete everything; restore the JSON | Each file has B and C as earlier wordings. After restore the note shows "Earlier versions (2)" again (ADR-236) |

## 4. Shortcuts, Siri and controls
| # | Do this | Expect |
|---|---|---|
| S1 | Shortcuts app → Doddy → Save to Doddy, with some text | Doddy opens on the capture screen with the text filled in. Nothing is saved until Save (ADR-179) |
| S2 | Say "Save a note in Doddy" | Siri asks "What should Doddy keep?" |
| S3 | Add the New note control to Control Center and the Lock Screen, then press it | Empty capture screen (ADR-180) |
| S4 | "Find in Doddy" with the app **closed**, then open | Memories → Find with the words filled in and the results showing (ADR-181). Run it again with the app open |
| S5 | Start Save to Doddy while a voice conversation is open | The note appears after the conversation closes |
| S6 | Run Save to Doddy during first-use onboarding or while the Back Tap setup sheet is open | It waits and appears afterwards. A later Save to Doddy still works (it must not stay blocked) |

## 4b. The opening and listening on open (ADR-225)
| # | Do this | Expect |
|---|---|---|
| O1 | Launch the app (onboarding done) | About 2.4 s: a pen draws Doddy, two bounces with dust, crouch, spring, shot with a trail, SWISH! with confetti and a shake, he pops up, then jumps into his place on Home as Home fades in and the buttons slide in. **Main check: when the opening ends, Home's Doddy must not move by even a point** (light, dark, smallest and largest iPhone, largest text size where Home's picture is 100 pt). Also: every stroke of the pen drawing appears; no text greeting anywhere. `design/opening-v0.1/index.html` shows the intended timing |
| O2 | Settings → Voice → "Start listening when I open Doddy" off; relaunch and tap during the scene | It jumps to the hand-over: Doddy hops into his place and Home is usable within half a second. Nothing listens |
| O3 | Switch to another app and back within a minute; then leave it in the background for 5 minutes and come back | No scene on the quick return; the scene on the return after 5 minutes |
| O4 | Settings → Appearance → "Doddy's opening" off; relaunch | Home straight away. On again: the scene is back on the next launch |
| O6 | iOS Settings → Accessibility → Motion → Reduce Motion on; relaunch | A still picture: Doddy already in his place on Home, then the paper fades around him in about a second; nothing moves; Home's buttons are there at once. VoiceOver on: no opening |
| O7 | "Hide character artwork" on; relaunch | No scene |
| O8 | Fresh install, finish onboarding, then relaunch ("Start listening when I open Doddy" is on by default) | After the scene, Talk to Doddy opens by itself: the iOS microphone prompt the first time, then "Connecting…" and "Listening" from the real session, the orange indicator, Doddy's own first message spoken by the agent. End it. Privacy row reads "Only while talking. A conversation starts when you open Doddy; turn that off under Voice" |
| O9 | With O8 on: open Doddy from Back Tap or the Talk to Doddy control during the scene | The scene stops; one conversation, not two |
| O10 | With O8 on: iOS Settings → Doddy → Microphone off; relaunch | The scene plays; no conversation opens by itself (it would only say "Microphone is off"). Tapping Talk to Doddy still explains and offers Open Settings |
| O11 | With O8 on: tap a note reminder's "Done" from the Lock Screen (a background launch), then open Doddy | Nothing listened in the background; the scene (and the conversation) only once the app is on screen |

## 5. Voice (needs a real conversation)
| # | Do this | Expect |
|---|---|---|
| V1 | Settings → Voice and personality: play each voice sample, change speed and expressiveness | Samples play at the chosen speed. They refuse to play during a conversation (ADR-105, ADR-122) |
| V2 | Start a conversation with a non-default voice, speed and starting language | The voice and language are used. The dev agent allows the overrides. If it connects but sounds default, check the agent's override switches |
| V3 | Set a nickname | Doddy uses it now and then (ADR-127) |
| V4 | Turn on Private on the Talk screen, talk, end | The banner shows. The conversation is not in Remembered conversations (ADR-170) |
| V5 | Island: start a conversation, press Home, long-press the island, tap Mute then Unmute | Status changes to Muted and back; the app keeps running (ADR-128; `NATIVE_BASELINE_REPORT.md`). If a tap does nothing, read the Console line (subsystem `com.bienos.doddy2`, category `island`): it names the process that ran the intent and whether a handler was there (`V3_ISLAND_STATUS.md`, "Go live") |
| V5b | Simulator first: `DoddyUITests/MemoryBaselineTests/testNativeIslandOfflineFixtureCanStartMuteAndEnd` on an iPhone with a Dynamic Island, plus `DoddyTests/IslandBaselineTests` | All green. This is the red check from the Codex run; it is the first thing to run after `make project` |
| V6 | Reminders by voice (ADR-126, `M4_REMINDERS_STATUS.md`) | The device checks listed there |
| V7 | Ask Doddy to save a note by voice, pick "Place" on the card, tap Save | The note is saved with that type (see the type filter chips). Declining and a second proposal start at "Other" again (ADR-202) |
| V8 | With an app build that includes ADR-237 (live agent synced 2026-10-10): say "remind me next Friday to call mum", then "add the dentist tomorrow at 7", then "remind me tomorrow morning to pay rent" | Each time Doddy asks one question (which Friday, with both dates; 7 in the morning or evening; what time or no time) before any card. After the answer the card shows the chosen date. "Friday 16 October at 19:00" goes straight to the card |

## 6. Ask and server
- Ask: after the daily limit is reached, "Try again" is hidden. This needs a deployed gateway with limits set (ADR-124, ADR-125). The Redis store and real OpenAI prices are still owner tasks.

## 7. Note reminders by voice and at places, repeats and snooze (ADR-210, ADR-211)
| # | Do this | Expect |
|---|---|---|
| R1 | The device checks in `VOICE_NOTE_REMINDERS_STATUS.md`, `PLACE_REMINDERS_STATUS.md` and `REPEAT_SNOOZE_STATUS.md` | As listed there. Key ones: a place reminder fires when arriving, "While Using" only; a weekly repeat rings on the right weekday; "In an hour" moves a one-off |

## 8. Languages and translator (ADR-212 to ADR-215, ADR-221)
| # | Do this | Expect |
|---|---|---|
| T1 | Start a conversation in English, switch to Polish, then German mid-sentence | Doddy follows (`LANGUAGES_STATUS.md`) |
| T2 | Home › Translate, face to face, Polish ⇄ Spanish | Their half is rotated; Doddy says the AI disclosure in Spanish first; no tool runs; nothing in Remembered conversations; the end card's Copy and Save work for 5 minutes (`TRANSLATOR_STATUS.md`) |
| T3 | Listen only, turn **Read aloud** off | The lines still appear; Doddy's voice is silent on the iPhone; turning it back on is heard; no red "couldn't be turned off" line. Ending the mode restores the voice |
| T4 | Ask Doddy to propose a plan while translating | Refused; the plan card never appears |

## 9. Lists (ADR-216, ADR-217)
| # | Do this | Expect |
|---|---|---|
| L1 | The checks in `LISTS_STATUS.md` | As listed |
| L2 | Find "milk" | A list containing "oat milk" shows under "IN 1 LIST" |
| L3 | Export JSON with a list, delete the list, restore | The list and its items come back |
| L4 | Ask for a plan that adds to a list | The card shows the step, which can't be changed; the item is added |

## 10. Photo notes (ADR-218)
| # | Do this | Expect |
|---|---|---|
| P1 | New note › Add a photo, pick a receipt | No permission prompt. A thumbnail, the read text added below anything typed, and "check it before saving". Save: the receipt; open the note: the photo shows |
| P2 | A photo with no text; a 48 MP photo; a HEIC | "No text was found…"; no crash or long freeze; downscaled to 2048 px |
| P3 | Delete the note, then Undo; delete again and let the bar go | The photo comes back with Undo; afterwards the file is gone from `Application Support/Memories/NotePhotos` |
| P4 | Remove photo on a note | The words stay; the photo and its file are gone |
| P5 | Polish receipt, handwriting, a dark photo | Note how good the text reading is (unknown so far) |

## 11. Widgets (ADR-219). Build with `DODDY_APP_ENTITLEMENTS` and `DODDY_WIDGET_ENTITLEMENTS` set (BUILD_AND_TEST.md)
| # | Do this | Expect |
|---|---|---|
| W1 | Add Pinned notes, Next reminder, List and Talk to Doddy to the Home Screen; pin a note; set a reminder; make a list | Each widget shows them within seconds of the change |
| W2 | **Tick an item on the List widget**, with Doddy closed (swipe it away first) | The item is ticked in the widget and in Doddy; the list screen offers Undo. This is the key unverified path: if nothing happens, the intent ran in the extension; record it |
| W3 | Tick from the Lock Screen widget while locked | iOS asks to unlock first; note text is hidden while locked |
| W4 | Settings › Widgets › turn "Show notes and lists in widgets" off | Widgets say "Turned off in Doddy's Settings." |
| W5 | Build without the App Group | Widgets say "Open Doddy to set up widgets"; Settings says the build can't share |
| W6 | Tap a pinned note or the reminder | Doddy opens on that note |

## 12. Morning check-in (ADR-220)
| # | Do this | Expect |
|---|---|---|
| M1 | Settings › Morning check-in on, time two minutes ahead | "Set for HH:MM every day." The notification arrives and says only "Good morning · A quick look at your day?" (Polish on a Polish iPhone) |
| M2 | Tap it with Doddy closed | The check-in screen opens with today's reminders, lists and the Today card |
| M3 | Talk it through (after the live agent update) | The sheet closes, the conversation opens, Doddy greets and then gives a short briefing from those facts; with Calendar on, it reads today |
| M4 | Weekdays only; then off | Five pending requests; then none |

## 13. Encrypted backup (ADR-222)
| # | Do this | Expect |
|---|---|---|
| B1 | Make a backup with photos, save to iCloud Drive | Time to lock (600,000 rounds) noted; "Saved as …" only after the save sheet succeeds |
| B2 | On a second iPhone, or after Delete all: restore with a wrong passphrase, then the right one | Wrong: "doesn't open this backup"; right: a summary, then "Added N notes and lists, P photos, R reminders, your About you answers" |
| B3 | Restore the same file again | "Everything in this backup is already on this iPhone." |
| B4 | Open the file in a text editor | No note text visible |

## 14. Polish screens (ADR-223)
| # | Do this | Expect |
|---|---|---|
| PL1 | iPhone language Polish; go through Home, New note, Memories, Lists, Settings | Polish everywhere listed in `POLISH_SCREENS_STATUS.md`; note clipped buttons and any English left on a main screen |

## Result log
| Item | Xcode / iOS / device | Result | Notes |
|---|---|---|---|
| Build | | | |
