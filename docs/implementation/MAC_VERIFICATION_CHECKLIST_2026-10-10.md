# Mac and iPhone verification checklist (branch `claude/brave-wright-k4jnu3`)

Date: 2026-10-10. Everything below was written and tested only on Linux (`scripts/ci.sh --core-only`,
268 Swift package tests, gateway and backend tests). **None of the app code has been compiled with Xcode or
run on a device.** Nothing here is verified until a person ticks it. Record the Xcode version, the device
and the result for each item in the table at the end.

## 0. What is already compiled
Since ADR-200, `scripts/typecheck_app_logic.sh` compiles eight non-UI app files (`MemoryStore`,
`ShortcutRouter`, `ProfileStore`, `ConversationLogStore`, `AskController`, `PersonalityPreferences`,
`PinnedNotesStorage`, `NoteReminderStore`) against the real DoddyCore module on Linux, and they pass. Everything else in
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
3. Run the unit and UI tests. The existing UI tests save one note per run in an empty store, so the duplicate warning should not change them.

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
| M12 | Run `MeaningSearchCalibrationTests` on a simulator **and** an iPhone; copy the `[calibration]` lines into the result log | Top-1 at least 6 of 8, few wrong offers. If it skips ("model assets not available"), go online and run it again (ADR-210, `MEANING_RECALL_STATUS.md`) |
| M13 | Save at least 8 notes, including "Kasia says the sushi spot on Mokotowska is great". Find → "japanese food" | "NO NOTE USES THESE WORDS", then "MAYBE RELATED" with the sushi note marked "Related by meaning, not your words". Opening it shows the stored note (ADR-210) |
| M14 | Same notes, ask Doddy by voice "where should we go for japanese food?" | Doddy says the sushi note *might* be what you mean; never claims it as an exact match. Ask about something unrelated ("my passport number"): no meaning suggestion is read out as an answer |
| M15 | Settings → Your memories → turn off Find by meaning, then search "japanese food" again | Only word matches; the "MAYBE RELATED" group is gone. Turn it back on: the next search is slower once (notes embedded again), then normal |
| M16 | Time the first Find after installing with 200+ synthetic notes, then the second | First search embeds up to 200 notes (record the seconds); the second embeds only the question. Record both in the result log |

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

## 4. Shortcuts, Siri and controls
| # | Do this | Expect |
|---|---|---|
| S1 | Shortcuts app → Doddy → Save to Doddy, with some text | Doddy opens on the capture screen with the text filled in. Nothing is saved until Save (ADR-179) |
| S2 | Say "Save a note in Doddy" | Siri asks "What should Doddy keep?" |
| S3 | Add the New note control to Control Center and the Lock Screen, then press it | Empty capture screen (ADR-180) |
| S4 | "Find in Doddy" with the app **closed**, then open | Memories → Find with the words filled in and the results showing (ADR-181). Run it again with the app open |
| S5 | Start Save to Doddy while a voice conversation is open | The note appears after the conversation closes |
| S6 | Run Save to Doddy during first-use onboarding or while the Back Tap setup sheet is open | It waits and appears afterwards. A later Save to Doddy still works (it must not stay blocked) |
| S7 | Save "Gate code 4821". With Doddy closed and the iPhone unlocked: "Hey Siri, ask Doddy what I saved" → "gate code" | Siri asks "What are you looking for?", then says "You saved this today: Gate code 4821." Doddy does not open. Also try "What did I save in Doddy" and the Shortcuts app tile "Ask what I saved" (ADR-214, `SIRI_READBACK_STATUS.md`) |
| S8 | Same, with the iPhone **locked** | Siri asks you to unlock first and says nothing about the note until you do |
| S9 | Save "Gate code 5555" too and ask again; then ask for something you never saved; then a long note | Both codes read with "Check which one is current"; "I couldn't find that in your saved memories."; a long note is cut with "open Doddy for the rest" |
| S10 | Settings → Back Tap and Siri → turn off "Siri can read my notes aloud", ask again | "Reading notes aloud is turned off in Doddy's settings…" and no note. What leaves this iPhone shows the Siri row off |
| S11 | Time the answer the first time after a restart, with Find by meaning on (model loads in the background) | Siri answers before giving up. If it times out, record it: the fix is to use word search only for Siri |

## 4b. Morning brief (ADR-212, `MORNING_BRIEF_STATUS.md`)
| # | Do this | Expect |
|---|---|---|
| B1 | Settings → Morning brief on, time 2 minutes from now | iOS asks for notifications (first time). Status "On. A notification every day at …" only after iOS lists it. Home shows nothing yet |
| B2 | Wait for the time with the phone locked | Banner "Morning brief — Your day at a glance is ready in Doddy." No titles or notes on the Lock Screen. Tap it from another tab: Doddy opens on Home with the brief at the top |
| B3 | With Calendar and Reminders on, a timed event, an all-day event, a reminder from yesterday and a note reminder later today | The brief lists counts, the first timed event's time, the all-day title, "One is from an earlier day", and the note reminder with its words. Compare with the Today card below it: same data |
| B4 | Read aloud, then Stop; start a voice conversation and try Read aloud | It speaks with the iPhone's voice and stops at once; it never speaks during a conversation. Leaving the app stops it |
| B5 | Close for today; relaunch; change the time to later today | The brief stays gone today and comes back tomorrow. Status updates and iOS lists the new time (one notification only) |
| B6 | Pause all connections; Calendar off; notifications refused in iOS | The brief says what it couldn't read; never guesses. Refused notifications: Settings says so and the brief still shows on Home |
| B7 | Turn the brief off | Status "Off. No morning notification." and iOS no longer lists it; timers, nudges and note reminders are still there |
| B8 | Settings → Morning brief → In your morning brief: turn off Events, leave Reminders on | The brief has no events line and no "Calendar is off" note. Back on Home without leaving the app, the card already reflects it (ADR-213) |
| B9 | With the mock Doddy server: connect Todoist and Gmail in Online accounts, switch on "List my tasks" and "Check my email", add both to the brief | Tasks and "unread emails … from Anna Demo", both starting "Demo data, not your account:". No email preview anywhere on the card. Online accounts → receipts lists both checks. Opening Home again doesn't add receipts; Refresh adds one each |
| B10 | Add Todoist to the brief with "List my tasks" switched off; turn off Wi-Fi and tap Refresh | "Todoist isn't in this brief: … Check Settings, Online accounts." Offline: "Couldn't … just now." Nothing invented, local lines still there |
| B11 | Add Today's daily news with a digest from today (Daily news → Send now) | "From your daily news:" and up to 3 stories with their source; tapping one opens Safari. With no digest today: "No daily news digest yet today." Yesterday's digest is never shown |

## 4c. Widgets (ADR-215, `WIDGETS_STATUS.md`)
| # | Do this | Expect |
|---|---|---|
| W1 | Default build (no App Group). Add Talk to Doddy (small, medium) and the Lock Screen circle; tap each | Talk opens Doddy and starts a conversation; New note opens an empty capture screen. Settings → Widgets says "Not set up in this build"; Pinned notes says "This Doddy build isn't set up to share notes with widgets." |
| W2 | Build with the App Group (`BUILD_AND_TEST.md`). Pin 3 notes, set a note reminder in 10 minutes, add Pinned notes (small, medium) and Next note reminder (small, Lock Screen rectangular and inline) | Pinned shows the newest pin first; Next reminder shows the time and "in 10 minutes". Tapping a note opens it in Doddy |
| W3 | Lock the iPhone and look at the Lock Screen widgets | The time shows; the note's words are hidden until unlocked |
| W4 | Wait until the reminder time passes without opening Doddy | The widget moves on to the next reminder (or "No note reminders coming up") by itself |
| W5 | Unpin a note, edit a pinned note, delete a pinned note, delete all notes | Each change reaches the widgets within moments of leaving the screen; after delete all they're empty. A widget tap on a deleted note shows "This memory no longer exists." |
| W6 | Settings → Widgets → turn off note words | Widgets show "Pinned note" / "Open Doddy to see it". The shared file no longer contains the words (check in Xcode's device container download if possible) |
| W7 | First install with the App Group, add a note widget before opening Doddy | "Open Doddy once to show this here." |

| # | Do this | Expect |
|---|---|---|
| V1 | Settings → Voice and personality: play each voice sample, change speed and expressiveness | Samples play at the chosen speed. They refuse to play during a conversation (ADR-105, ADR-122) |
| V2 | Start a conversation with a non-default voice, speed and starting language | The voice and language are used. The dev agent allows the overrides. If it connects but sounds default, check the agent's override switches |
| V3 | Set a nickname | Doddy uses it now and then (ADR-127) |
| V4 | Turn on Private on the Talk screen, talk, end | The banner shows. The conversation is not in Remembered conversations (ADR-170) |
| V5 | Island: start a conversation, tap Mute and Unmute on the Live Activity | The Unmute fix works and the app keeps running (ADR-128; `NATIVE_BASELINE_REPORT.md`) |
| V6 | Reminders by voice (ADR-126, `M4_REMINDERS_STATUS.md`) | The device checks listed there |
| V7 | Ask Doddy to save a note by voice, pick "Place" on the card, tap Save | The note is saved with that type (see the type filter chips). Declining and a second proposal start at "Other" again (ADR-202) |
| V8 | In a conversation say "By the way, Marta's birthday is on the 12th of May" and "The plumber Adam comes on Tuesday", ask the weather, then tap End | A "Worth keeping?" card with those two sentences in your words, **none ticked**, Save disabled. Tick one, change the other's words, tap Save: both saved (check Memories), the card says "What was saved". Ask-the-weather and Doddy's own lines are never offered (ADR-211) |
| V9 | Same, but say "My Netflix password is …" and "Remind me to call Adam at 5" | Neither is offered. Also: a Private conversation shows no card; Settings → What Doddy knows → Suggest notes after a conversation off shows no card; a note Doddy already put on a save card (saved or declined) is not offered again |
| V10 | Tap "Not now", then leave and come back to the Talk screen | The card stays gone for that conversation. Note how ElevenLabs' transcript splits sentences and whether names come capitalised (affects which sentences are offered); record in the result log |

## 6. Ask and server
- Ask: after the daily limit is reached, "Try again" is hidden. This needs a deployed gateway with limits set (ADR-124, ADR-125). The Redis store and real OpenAI prices are still owner tasks.

## Result log
| Item | Xcode / iOS / device | Result | Notes |
|---|---|---|---|
| Build | | | |
