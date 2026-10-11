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
0. Start with `docs/implementation/FIRST_BUILD_GUIDE.md`. It covers getting hosted CI to start, or building on a Mac. It also lists the files most likely to need a fix from this round (ADR-226 to ADR-233), which added a watch target, voice memos, import, change cards, Siri lists, meaning search, tidy-up and the Polish catalogs.
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
| M12 | Correct one note three times (A → B → C → D), then open it | "Earlier versions (2)" lists C then B, each with its time. "Original capture" shows A. Relaunch: the same. Delete and Undo: the same. Search for a word only in B: no match (ADR-252) |
| M13 | Search "netflix password" with a wifi password note saved; then ask the same by voice | Find: "1 PARTIAL MATCH" and "No saved note mentions “netflix”…" above the wifi note. Voice: Doddy says no note mentions Netflix and does not read the wifi password out as the answer (ADR-251) |

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
| E6 | With the M12 note: export as JSON, text and Markdown; delete everything; restore the JSON | Each file has B and C as earlier wordings. After restore the note shows "Earlier versions (2)" again (ADR-252) |

## 4. Shortcuts, Siri and controls
| # | Do this | Expect |
|---|---|---|
| S1 | Shortcuts app → Doddy → Save to Doddy, with some text | Doddy opens on the capture screen with the text filled in. Nothing is saved until Save (ADR-179) |
| S2 | Say "Save a note in Doddy" | Siri asks "What should Doddy keep?" |
| S3 | Add the New note control to Control Center and the Lock Screen, then press it | Empty capture screen (ADR-180) |
| S4 | "Find in Doddy" with the app **closed**, then open | Memories → Find with the words filled in and the results showing (ADR-181). Run it again with the app open |
| S5 | Start Save to Doddy while a voice conversation is open | The note appears after the conversation closes |
| S6 | Run Save to Doddy during first-use onboarding or while the Back Tap setup sheet is open | It waits and appears afterwards. A later Save to Doddy still works (it must not stay blocked) |
| S7 | Save "Gate code 4821". With Doddy closed and the iPhone unlocked: "Hey Siri, ask Doddy what I saved" → "gate code" | Siri asks "What are you looking for?", then says "You saved this today: Gate code 4821." Doddy does not open. Also try "What did I save in Doddy" and the Shortcuts app tile "Ask what I saved" (ADR-248, `SIRI_READBACK_STATUS.md`) |
| S8 | Same, with the iPhone **locked** | Siri asks you to unlock first and says nothing about the note until you do |
| S9 | Save "Gate code 5555" too and ask again; then ask for something you never saved; then a long note | Both codes read with "Check which one is current"; "I couldn't find that in your saved memories."; a long note is cut with "open Doddy for the rest" |
| S10 | Settings → Back Tap and Siri → turn off "Siri can read my notes aloud", ask again | "Reading notes aloud is turned off in Doddy's settings…" and no note. What leaves this iPhone shows the Siri row off |
| S11 | Time the answer the first time after a restart | Siri answers before giving up (word search only). If it times out, record it in the result log |

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

## 4e. "Hey Doddy" (ADR-254, `HEY_DODDY_STATUS.md`)
Needs a free Picovoice account: copy the AccessKey, and in the Porcupine section train **Hey Doddy**, English, platform **iOS**; download the `.ppn` to the iPhone (Files → On My iPhone). Voice must already work (token server or the development agent). Turn off "Start listening when I open Doddy" first, so only the wake word starts conversations.

| # | Do this | Expect |
|---|---|---|
| H1 | Build: `make project`, then build. Package resolution fetches the Porcupine repository (large; first time takes a while) | The app builds with the `Porcupine` product. If `revision:` is refused by XcodeGen or SwiftPM, note the error. Compile errors most likely in `WakeWordListener.swift`: `PorcupineManager(accessKey:keywordPath:sensitivity:onDetection:errorCallback:)`, the `nonisolated` handler factories, `UIApplication.beginBackgroundTask`, and the memberwise `ContentState(status:isMuted:greeting:conversationStartedAt:)` |
| H2 | Settings → Hey Doddy, fresh install | Switch off; "Now: Off." Nothing in the island; no microphone dot |
| H3 | Turn it on without a key or file | iOS asks for the microphone if it never has. "Add your Picovoice AccessKey and “Hey Doddy” keyword file…"; no microphone dot |
| H4 | Paste a wrong key (e.g. one letter changed) and choose the .ppn | "Picovoice didn't accept the AccessKey…" (or the activation message); no microphone dot. Choose a .zip or a `_pl_ios_` / `_android_` file: the matching problem text |
| H5 | Paste the right key | "Now: Listening for “Hey Doddy” on this iPhone." The orange microphone dot shows. Go to the Home Screen: the island is in your island style with the label HEY DODDY, "Say “Hey Doddy”", "Listening on this iPhone for “Hey Doddy” only" and Stop listening (no Mute, no timer, no orange). The Lock Screen shows Doddy sitting and "Hey Doddy is on". Change the island style in Settings and check the waiting island follows it |
| H6 | On the Home Screen, say "Hey Doddy" | Within about a second the island says **"Hey Pat, what's up?"** (your nickname; without one, the first word of your About you name; without both, "bud"), then Doddy connects and **says the same greeting out loud** (live agent first message `{{opening_line}}` since 2026-10-11). A conversation started with a tap still opens with "Hey, it's Doddy. What's up?". The timer counts from the wake word, not from when listening started. When you first speak, the island goes back to Listening/Thinking/Speaking. Note the time from "Hey Doddy" to Doddy's first word |
| H7 | Say "bye" / tap End on the island | The conversation ends; the island shows "“Hey Doddy” paused" for a moment, then "Say “Hey Doddy”" again (not the Conversation ended card). Say "Hey Doddy" again after 5 seconds: a second conversation starts. **Key question:** does listening restart in the background after the conversation, or does the island go away and Settings say "Open Doddy"? Write down which |
| H8 | Open Doddy while a wake conversation runs; and once after one ended with a "Worth keeping?" card | The voice screen opens on that conversation (not a second one); the card shows. After a wake conversation that ended with nothing, opening Doddy goes to Home |
| H9 | Say "Hey Doddy" and then say nothing | The conversation ends by itself about 20 seconds after Doddy is ready; listening comes back |
| H10 | Tap Stop listening on the island | The island goes away, the microphone dot goes off, Settings shows the switch off |
| H11 | With it listening: (a) turn on Low Power Mode; (b) take a phone call; (c) open Voice Memos and record; (d) play a voice sample in Settings and read a note aloud | (a) "Paused: Low Power Mode is on.", dot off; listening returns when it's off and Doddy is open. (b, c) "Paused: another app or a call…", then back if iOS allows. (d) Samples and the note play through the **speaker** (not the earpiece) and listening comes back after |
| H15 | With it listening, in Doddy: record a voice memo on a note, stop, then play it back; while it plays, start reading another note aloud and stop that first | Listening pauses while recording and playing (Settings "Now" says so), the memo records and plays normally, and listening comes back only when both the memo and the read-aloud have stopped (ADR-254 port) |
| H16 | With the morning check-in or the tidy-up sheet open, say "Hey Doddy" | The conversation starts on the island, but the voice screen doesn't push the sheet aside. Close the sheet and leave and reopen Doddy: the voice screen opens on that conversation if it is still running |
| H12 | Leave it listening in the background for an hour with the screen locked; note the battery % used and whether it is still listening (island) | Write the battery cost down. If iOS ended it, the island must not still say "Say “Hey Doddy”" (stale: "Not listening — open Doddy") |
| H13 | Leave a TV or podcast playing near the iPhone for 30 minutes | Count false wake-ups. Each one should end by itself after 20 s of silence from you; after 12 in an hour the status says "Resting…" |
| H14 | What leaves this iPhone | A Picovoice row: active only while the switch is on; the "stays on this iPhone" line for Hey Doddy; Settings → Privacy → Microphone mentions it while on |

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
| V8 | With an app build that includes ADR-253 (live agent synced 2026-10-10): say "remind me next Friday to call mum", then "add the dentist tomorrow at 7", then "remind me tomorrow morning to pay rent" | Each time Doddy asks one question (which Friday, with both dates; 7 in the morning or evening; what time or no time) before any card. After the answer the card shows the chosen date. "Friday 16 October at 19:00" goes straight to the card |
| V9 | In a conversation say "By the way, Marta's birthday is on the 12th of May" and "The plumber Adam comes on Tuesday", ask the weather, then tap End | A "Worth keeping?" card with those two sentences in your words, **none ticked**, Save disabled. Tick one, change the other's words, tap Save: both saved (check Memories), the card says "What was saved". Ask-the-weather and Doddy's own lines are never offered (ADR-247) |
| V10 | Same, but say "My Netflix password is …" and "Remind me to call Adam at 5" | Neither is offered. Also: a Private conversation shows no card; Settings → What Doddy knows → Suggest notes after a conversation off shows no card; a note Doddy already put on a save card (saved or declined) is not offered again |
| V11 | Tap "Not now", then leave and come back to the Talk screen | The card stays gone for that conversation. Note how ElevenLabs' transcript splits sentences and whether names come capitalised (affects which sentences are offered); record in the result log |

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

## 15. Undo in What Doddy did (ADR-268)
| # | Do this | Expect |
|---|---|---|
| U1 | Ask Doddy to add an event; Settings → What Doddy did → Undo → Remove | The event is gone from Calendar; the row says "Calendar · Undone" |
| U2 | Ask Doddy to add a reminder; rename it in Reminders; Undo | "Not undone: it changed in Reminders since Doddy did this…"; the reminder stays |
| U3 | Have your own reminder "Buy milk", ask Doddy to add "Buy milk" (already there) | No Undo on that row |
| U4 | Ask Doddy to move an event; Undo → Put back | Old time and name back; row "Undone" |
| U5 | Ask Doddy to mark a reminder done; Undo → Mark not done | Open again in Reminders |
| U6 | Turn on Pause all; Undo | "Not undone: Connections are paused in Settings. Nothing changed."; Undo still offered |
| U7 | Plan card with an event and a reminder → Add; What Doddy did | Both steps show Undo |
| U8 | (after the live agent update) Ask Doddy to add a reminder, then say "undo that" → Remove | Card names the reminder; it's gone from Reminders; Doddy says it was undone |
| U9 | (after the live agent update) New conversation, say "undo that" | Doddy says there's nothing to undo from this conversation |
| U10 | Ask Doddy to add "milk, eggs" to Shopping; tick eggs yourself; What Doddy did → Undo → Remove | Milk is gone; eggs stay; row "Notes · Undone" |
| U11 | Ask Doddy to remove "bread" from Shopping; Undo → Put back | Bread is back where it was |
| U12 | Ask Doddy to add an item, then delete the whole list; Undo | "Not undone: it changed in the list since…" |

## 16. Birthdays from Contacts (ADR-269; needs the live agent update first)
| # | Do this | Expect |
|---|---|---|
| BD1 | Give two contacts birthdays this week (one without a year); ask "whose birthday is this week?" | Doddy names both with the day; never a year or age |
| BD2 | Contacts switch off; ask again | "Contacts isn't connected …"; nothing read |
| BD3 | Pause all on; ask again | Paused reply; nothing read |
| BD4 | "Remind me the day before Anna's birthday" | A create_reminder card; nothing added before the tap |

## 17. Sums and unit conversions (ADR-270; needs the live agent update first)
| # | Do this | Expect |
|---|---|---|
| C1 | "What's 124.50 plus 37, split three ways?" | About 53.83; nothing logged in What Doddy did |
| C2 | "How many kilometres is 5 miles?" / "350 Fahrenheit in Celsius?" | 8.05 km / about 177 °C |
| C3 | "Convert 20 euros to złoty" | Doddy says it can't convert currencies yet |
| C4 | Pause all on; ask a sum | Still answered (no other app is used) |

## Result log
| Item | Xcode / iOS / device | Result | Notes |
|---|---|---|---|
| Build | | | |

## 4f. Whole Doddy island style (ADR-264, `WHOLE_DODDY_ISLAND_STATUS.md`)
| # | Do this | Expect |
|---|---|---|
| W1 | Fresh install; open Settings → Voice → Dynamic Island style. Then pick Lean In, relaunch, and check it stays | "Whole Doddy" is first and already ticked (the default, ADR-267); a picked style is kept after a relaunch. Its preview: Doddy's whole body on black with a thin cream edge, no panel. Switch the preview between Listening, Speaking, Thinking and Muted: hand at ear, open hands, kneeling, shush |
| W2 | Choose Whole Doddy, talk to Doddy, go to the Home Screen and long-press the island | The expanded island shows the pose for each state as it changes (connecting = stretch). The pose is sharp, not blurry, and the cream edge is even |
| W3 | Look at compact and minimal (open another app with its own activity for minimal) | A round face crop: the listening face while live, shush when muted. Not cut off, not blurry |
| W4 | Ask Doddy to save a note, tap Save; ask for a reminder and Add | Reaching high while it waits; a fist pump only after Saved / Reminders confirmed it |
| W5 | With Hey Doddy on: wait, say "Hey Doddy", end the call | Cross-legged while waiting, waving with the greeting (no paper edge around the wave), leaning while paused |
| W6 | Start the translator from Home with Whole Doddy chosen | Language Bridge as before, no pose |

## 4g. Cream Lock Screen cards (ADR-266)
| # | Do this | Expect |
|---|---|---|
| C1 | Dark mode on. Talk to Doddy and lock the iPhone; then turn on Hey Doddy and lock it again | Both Lock Screen cards are cream with dark text and Doddy without a paper box. Mute / End / Stop listening read clearly |
| C2 | Dark mode on. Start a focus timer, then shopping mode for a list, and lock the iPhone | Both cards are cream with readable text; ticking an item still works |


## 4h. Doddy's world in the app (ADR-299, `DODDY_WORLD_IN_APP_STATUS.md`)
| # | Do this | Expect |
|---|---|---|
| X1 | Build the app, widgets and watch app. Talk to Doddy and lock the iPhone; mute; end with and without saving a note | The Lock Screen card shows the island's pose: listening, shush when muted, fist pump only if a note was saved, else cross-legged. Same with a V4 style picked |
| X2 | Whole Doddy style. Read a note aloud; pause; let it finish; then read again and force-quit Doddy for 2 minutes | Island: Doddy reading lying down, then cross-legged, fist pump, facepalm when lost. With Lean In picked, the Story Spool board as before |
| X3 | Find a word that isn't saved. Then make a save fail (for example, a nearly full iPhone) | Find: Doddy shrugging. A failed save: facepalm beside the message. Light and dark mode; Hide Doddy's pictures hides both |
| X4 | Open Home, Memories and the morning check-in in light and dark mode, and at the largest text size (ADR-308) | No text over any scenery. Home: the room faint behind Doddy only, edge to edge. Memories and check-in: a faint strip of the library / coffee shop between the heading and the content, fading at top and bottom. Night pictures in dark mode; with Hide Doddy's pictures the strips leave no gap |
| X5 | Talk to Doddy and watch the screen while he answers; then turn on Reduce Motion | Pose follows the island; while speaking the talking frames play without Doddy jumping; with Reduce Motion one still frame. Check CPU in Instruments stays low |
| X6 | Add Talk to Doddy and Next reminder (small) widgets; try light, dark, tinted and clear Home Screens | Wave and reach in light and dark (dark: thin cream edge); tinted and clear show the symbols, no grey blobs |
| X7 | On the watch, add the Doddy complication (circular with nothing coming up, and rectangular) on a full-colour face and a tinted face | Doddy's round face in colour on full-colour faces, and on tinted faces on watchOS 11+; monochrome faces show the symbol or name only |
| X8 | Fresh install: go through the opening, then the welcome; go to the first question and back; turn on Reduce Motion and reopen | Four panels cross-fade once and stop on Doddy waving; going back doesn't replay; Reduce Motion shows only the wave panel. The opening (ADR-225) is unchanged |

## 4i. Doddy moving, and outside the app (ADR-313, `DODDY_MOVES_STATUS.md`)
| # | Do this | Expect |
|---|---|---|
| Y1 | Whole Doddy style. Start a focus timer, pause, resume, let it finish; then a breathing session | Island: dribbling, cross-legged when paused, fist pump at the end; breathing: balancing on one leg. Lean In: the boards as before |
| Y2 | Open Focus: before starting, while running, paused, finished, stopped early | Court strip at the top: no Doddy before starting, dribbling, cross-legged, fist pump, none after a stop. No text over the court |
| Y3 | Open the weekly look-back in light and dark mode | Rooftop strip under the heading with Doddy cross-legged; text clean |
| Y4 | Talk to Doddy and watch the screen while it connects; ask for a plan with several steps and confirm it | Doddy walks while connecting, runs while the steps run, talks when he speaks. Reduce Motion: still frames. Island unchanged (stretch while connecting) |
| Y5 | Save a note from Capture; then make a save fail | Receipt: the pop plays once, then the fist pump stays. A failed save shows no pop |
| Y6 | Tick the last item on a list; reopen the list; tick on another device for a shared list | The jump plays once when ticked here; reopening shows "Nothing left." without it. An empty list shows Doddy cross-legged |
| Y7 | Undo an event in What Doddy did; clear the list | The undone row shows the small turned-back Doddy; empty: Doddy cross-legged |
| Y8 | Cold-launch with the opening off (Reduce Motion off), then with it on | Opening off: Doddy stands, breathes four times, sits; once per launch. Opening on: no breaths, the hand-over unchanged |
| Y9 | Add Talk to Doddy to the Lock Screen (circular); add "Doddy, resting" and charge the iPhone on its side at night | Lock Screen: Doddy's face, reads in the Lock Screen tint. StandBy: the stretch pose and the next reminder's time only, red at night |
| Y10 | Set a note reminder a minute ahead; turn on Hide Doddy's pictures and set another | First notification shows the reaching pose as its picture, same words as before; the second has no picture |
| Y11 | A list's menu → Share as a picture → Messages and Save Image | A cream card with the list name, open items (15 at most, then "and N more") and Doddy waving. Hide Doddy's pictures: no Doddy |
| Y12 | Ask Siri "Ask Doddy what I saved" for a saved word, a missing word, and with readback off | Siri's panel shows Doddy listening, shrugging, shushing; the spoken answer is unchanged |

## 4j. Alarm, shopping, notifications, Settings, watch app (ADR-323, `DODDY_MOVES_STATUS.md`)
| # | Do this | Expect |
|---|---|---|
| Z1 | iOS 26: set a Doddy alarm a minute ahead, snooze it, lock the iPhone | Cream card: Doddy stretching, "Snoozed" and the countdown; island: the same pose |
| Z2 | Start shopping mode on a list; lock the iPhone; long-press the island | Doddy on tiptoe on the cream card and on the island; ticking items still works |
| Z3 | Schedule the morning check-in, evening wrap-up, weekly look-back and a birthday a minute ahead; then with Hide Doddy's pictures on | Each shows its picture (stretch, cross-legged, cross-legged, wave), same words; none with Hide on |
| Z4 | Launch with the opening off; switch tabs and back; later return after the replay time so the opening plays | Breaths, then he sits down on his box and stays there when you come back to Home; the opening lands on the usual sitting picture and he's off the box |
| Z5 | Settings: turn Pause all connections on and off | The crouching Doddy beside the footer only while paused |
| Z6 | Watch app before the iPhone has sent anything; then save a note from the watch | Cross-legged Doddy with the hint; fist pump only after "Saved", with the thin cream edge on black |
| Z7 | Undo an entry in What Doddy did; leave and come back | He turns back once when it's undone; afterwards the turned frame stands still |

## 4l. First-use fixes (ADR-325)
| # | Do this | Expect |
|---|---|---|
| O1 | Fresh install, finish onboarding, look at Home; then Settings › Voice | No ElevenLabs / OpenAI switch on Home. It is in Settings › Voice ("Test voice"), and picking OpenAI there still runs the next conversation with OpenAI |
| O2 | Fresh install, finish onboarding, don't talk. Quit Doddy, wait 5 minutes, open it again. Then tap Talk to Doddy, allow the microphone, end, quit, wait 5 minutes, open again | Second opening: the animation, then Home; no conversation and no microphone question. After allowing it: the third opening starts listening by itself as before |

## 4m. Home's first visit (ADR-326)
| # | Do this | Expect |
|---|---|---|
| H1 | Fresh install, finish onboarding | Home: under Talk to Doddy, "Try saying: “Remember the gate code is 4821.” …"; no Back Tap card; no Today card. Bottom: "Doddy is an AI, not a person." and What leaves this iPhone |
| H2 | Tap What leaves this iPhone; Done. Then Settings › Privacy | The row-by-row screen opens as a sheet and closes. Settings › Privacy starts with the paragraph that used to be on Home |
| H3 | Tap Talk to Doddy, allow the microphone, wait for Listening, end. Back on Home | The hint is gone; the Back Tap card (if not set up) and the Today card are back. A failed connection (airplane mode) does not count |

