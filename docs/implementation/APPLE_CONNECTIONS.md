# Apple apps Doddy can connect to

Owner, 20 Oct 2026: "Connect to all of the Apple tools … every time you want to have access to it, have the pop-up that asks for permission, sliding from the bottom." This page lists every Apple app and system service a third-party iPhone app could use, what Doddy does with each today, and what blocks the rest. ADR-562 to ADR-564 are the decisions behind this round.

**State of this round:** written and tested on Linux (DoddyCore), app code compiled only in the hosted Mac CI job, **never seen on a device**. Rows marked "new" are in that state.

## How Doddy asks (all of them)

- Every connection starts **off** in Settings, Connections.
- **New (ADR-562): when Doddy needs one that is off, a sheet slides up over the conversation** ("Let Doddy use Calendar?"). It says what Doddy was asked to do and what leaves the phone. **Allow** turns it on; iOS shows its own permission prompt the first time; then Doddy carries on with the same request. **Not now** (or a swipe down) tells Doddy no, and it doesn't ask again in that conversation.
- If iOS has refused it before, only iPhone Settings can change that, so the sheet offers **Open iPhone Settings** instead.
- For a read ("What's on today?"), Allow also counts as the yes for that one look-up, so there's one tap, not two. A change ("Add dentist on Monday") still shows its own card to tap after Allow.

## 1. Connected (before this round)

| Apple app or service | What Doddy does | Asks |
|---|---|---|
| Calendar (EventKit) | Reads events, finds free time; adds, moves, renames or deletes one event after a tap | Connections switch + iOS prompt |
| Reminders (EventKit) | Adds, moves, completes or deletes a reminder after a tap | Connections switch + iOS prompt |
| Contacts | Looks up a person (details on screen only), upcoming birthdays, birthday reminders | Connections switch + iOS prompt |
| Notifications | Timers ring, note reminders, check-ins | Connections switch (Timers) + iOS prompt |
| Clock alarms (AlarmKit, iOS 26) | Doddy's own alarms that ring in Silent mode | iOS prompt |
| Apple Maps (MapKit) | Opens a place; travel time for "when to leave"; place search for reminders | Connections switch |
| Location (While Using only) | Place reminders, parking spot, leave-by | iOS prompt, never "Always" |
| Shortcuts | Runs one of your Shortcuts after a tap (also "open the camera" via a "Doddy Camera" Shortcut) | Connections switch |
| Messages and Mail | Drafts a text or email and opens it there; you send it | Connections switch |
| Microphone | The voice conversation, voice memos | iOS prompt |
| Speech recognition | Voice memos written out on the iPhone (on-device only) | iOS prompt |
| Face ID | App and private-note lock | iOS prompt |
| Photos picker (PhotosUI) and Vision | Photo notes: you pick a photo, its text is read on the iPhone. No library access | None (Apple's picker) |
| iCloud (CloudKit) | Shared lists with people you invite | iCloud account |
| Siri, App Shortcuts, Action Button, Back Tap, Control Center control | Ways to open Doddy, "Ask Doddy what I saved", list intents | None |
| Widgets, Live Activities, Dynamic Island | Glanceable notes, lists, the conversation's island | None |
| Spotlight | Your notes in iPhone search (off by default) | Settings switch |
| Focus filters | A list comes first while a Focus is on | Set on the Focus |
| Share Sheet ("Save to Doddy") | Save text or a link from any app | None |
| Apple Watch (WatchConnectivity) | Notes and lists on the Watch | Settings switch |
| Sign in with Apple | Doddy voice account (needs a paid Apple team) | Apple's sheet |

## 2. New in this round

| Apple app or service | What Doddy does | Asks | Code |
|---|---|---|---|
| **Keynote** (via a .pptx file) | "Make me five slides about our trip": every slide on a card, then a PowerPoint file Keynote opens, and the share sheet to open it in Keynote, save it to Files or send it | Connections switch (Presentations); a card tap | `PresentationFile`, `StoredZip` (DoddyCore), `Features/Presentations/` (ADR-563) |
| **Motion & Fitness** (steps) | "How many steps today?": steps, walking distance and floors for one of the last 7 days | Connections switch (Steps) + iOS prompt; a yes or tap | `StepCount` (DoddyCore), `DeviceConnections.steps` (ADR-564) |
| **The permission sheet** | Slides up for any connection above that is off | Allow / Not now | `PermissionAsk` (DoddyCore), `PermissionAskSheet` (ADR-562) |

## 3. Possible next, with your OK (no paid team needed)

| Apple app or service | What it would do | Why it waits |
|---|---|---|
| Photo library (PhotoKit) | "Show me photos from Saturday", count or find photos | ADR-218 says photo notes never touch the whole library. Needs your decision to change it |
| Camera (in the app) | Take a photo note without the Shortcut | Same ADR-218 rule; today it goes through the "Doddy Camera" Shortcut |
| Apple Music / your music library (MediaPlayer) | "Play my running playlist", pause, skip | Music fights the live conversation for audio; needs a design (end the conversation first?) |
| Files (document picker) | Attach a PDF or file to a note, read a document you pick | No iOS prompt (Apple's picker); a feature to scope |
| Pages and Numbers (via .docx / .xlsx files) | Write a document or a table the way presentations work | Same approach as Keynote; say which first |
| Apple Translate (iOS 18, on-device) | Offline translation | Translator mode already runs on the voice provider |

## 4. Needs a paid Apple Developer team or Apple's approval

The free (Personal) team build has no entitlements (`project-iphone.yml`), so none of these can be turned on there.

| Apple app or service | What it would do | Needs |
|---|---|---|
| Health (HealthKit) | Sleep, workouts, heart rate, more than steps | HealthKit entitlement, App ID capability, App Store health rules |
| Home (HomeKit) | Lights, scenes, "I'm leaving" | HomeKit entitlement |
| Weather (WeatherKit) | Weather from Apple | Entitlement and App ID; weather today comes from ElevenLabs |
| Focus status | Know when you're in a Focus | Communication Notifications entitlement |
| CarPlay | Doddy in the car (rules are written, ADR-338) | Apple's CarPlay entitlement |
| Screen Time (FamilyControls) | App limits | Apple's approval |
| Journaling Suggestions | Moments for a daily note | Entitlement |
| Push notifications | Server updates, texts | Paid team (the messaging server is built) |

## 5. Apple gives apps no way in

No third-party app can do these on iPhone; Doddy says so rather than pretending.

- **Notes app:** no API to read or write. Workaround: a Shortcut ("Run my notes shortcut") or Doddy's own notes.
- **Keynote, Pages, Numbers controls:** no API. Workaround: Doddy makes the file (done for Keynote).
- **Messages and Mail inboxes:** no API to read texts or Apple Mail. Gmail and Outlook work through Online accounts.
- **Phone:** no call history and no silent calls; Doddy can only open the dialer for you.
- **Safari, Settings switches (Wi-Fi, Bluetooth, brightness), other apps' screens:** no API; some can be done through your Shortcuts.
- **The Clock app's own alarms:** not readable; Doddy has its own alarms (AlarmKit).
- **Apple Pay, Wallet passes, Find My:** no way to pay, read others' passes or locate devices. Money is shown on a card for you to send (BLIK, ADR-510).
- **Siri itself:** Doddy can be opened by Siri, not control it.

## What was checked, and what wasn't

- **Ran here (Linux, Swift 6.1.2, 21 Oct):** `swift test` for DoddyCore, 1,293 tests, 0 failures (1,267 before; the new ones are `PermissionAskTests`, `PresentationTests` and `StepCountTests`, plus the tool lists in `ToolGateTests`, `ActivityTextTests` and `VoiceToolsTests`). `scripts/ci.sh --core-only`: every other step PASS (guard, the three agent specs with 84 app tools, string catalogs with the Motion & Fitness prompt in all ten languages as machine drafts, platform specs, the app logic type-check, the servers' tests); its only FAIL was `VoiceToolsTests`' old count of 8 connections, fixed and re-run above. The iOS build is NOT RUN there.
- **The presentation file:** a sample deck written by the tests was opened with python-pptx 1.0.2 (4 slides, every text read back) and rendered by LibreOffice to images; a deck at every limit at once still fits. **Not opened in Keynote or PowerPoint yet.**
- **NOT RUN here:** the iPhone app build and its tests (`PermissionSheetTests` in `DoddyTests/VoiceSessionControllerTests.swift`) need Xcode; they run in the hosted Mac job.
- **On a device, still to check:** the sheet sliding up over a live conversation; iOS's prompts for Calendar and Motion & Fitness after Allow; the share sheet listing Keynote; Keynote opening the file; a call held longer than its tool timeout (60–120 s).
- **The live ElevenLabs agent was not changed.** `make_presentation` and `read_steps` are `not_synced` in `voice-agent/tools.json`, and the instruction lines about the sheet are only in this repository. Until the owner syncs them, the live agent can't call the two new tools, and it still tells the user to go to Settings when it hears "not connected" (which the new app no longer sends while it asks on screen).
