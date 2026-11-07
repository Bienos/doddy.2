# iPhone and iPad

**Build:**
- `make project`, scheme `Doddy`: the shipping build. The Apple Watch app is paused (ADR-572) and is not in it.
- `make project-iphone`, scheme `Doddy`: the same with no entitlements, so a free Apple team can sign it. It has no Apple Health: the Health screen says this build can't use it (owner, 25 Oct; to try it, see `project-iphone.yml`).
- iPad is the same app target (`TARGETED_DEVICE_FAMILY 1,2`).

**State:** this is what the owner builds and uses. The known-good branch and the unmerged changes are in `/STATUS.md`. iPad work (sidebar, fixes) is in `docs/implementation/IPAD_STATUS.md`; it compiles in the hosted Mac job (whose iPad sidebar UI test is skipped on the iPhone simulator) and hasn't been seen on an iPad. **Everything on the default branch compiles in the hosted Mac job** (last: #157's run, 1 Nov); that is not a run on a device, and almost nothing merged since 20 Oct has a recorded device check.

## Voice: the core of the app
- **Code:** `DoddyApp/Features/Voice/` (27 files). Session: `VoiceSessionController.swift`. Screen: `VoiceView.swift`; on Home, `HomeConversation.swift`. Provider config: `VoiceConfig.swift`. The island's activity: `VoiceLiveActivity.swift`; the loudness of Doddy's voice: `AgentVoiceMeter.swift`. The wake word (`WakeWordListener.swift`) was removed with Hey Doddy (ADR-549).
- **Agent:**
  - ElevenLabs `agent_0501m4et27vyeawrwqfdxxfszfa6`. The prompt and tools are in `voice-agent/` (`instructions.md`, `tools.json`, `session.json`). `python3 -I scripts/voice_agent_spec.py check` validates them.
  - The live agent is changed by the owner, never from the app.
  - The app sends dynamic variables at start (notes, lists, profile, `learned_context`, opening line). A variable the live prompt requires but the app doesn't send stops the call before it starts.
- **Providers:** ElevenLabs (default, ADR-546) or OpenAI Realtime, chosen in Settings › Voice (and on Home after the first conversation) (ADR-265, ADR-442, ADR-443). `docs/implementation/VOICE_PROVIDER_TEST_STATUS.md`. OpenAI always goes through the token server with a Doddy voice account (Sign in with Apple, so a paid Apple team); a Debug build's developer connection reaches ElevenLabs only (ADR-551, ADR-633).
- **Audio session:** one owner, `AudioSessionOwner.swift` (ADR-695; the rule is `AudioSessionPolicy` in DoddyCore). Anything new that records or plays sound registers there, asks `claim` before setting the session up and calls `release` when done; it never switches the session off itself. A phone call during a conversation follows `VoiceInterruptionPolicy` (ADR-696).
- **Status docs:** `V1_VOICE_STATUS`, `V3_ISLAND_STATUS` (Dynamic Island), `HEY_DODDY_STATUS` (history: removed, ADR-549), `OPENING_SCENE_STATUS` (the intro and listen-on-open).
- **To debug a voice problem,** look at the ElevenLabs conversation log for the agent first:
  - no conversation at all means the app failed before connecting;
  - a conversation with no messages means the session started without its start data.

## Feature map
Code lives under `DoddyApp/Features/<Folder>/`. Status docs are in `docs/implementation/`. Rules with no UI are in `Packages/DoddyCore/Sources/DoddyCore/`.

| Folder | What it is | ADR | Status doc |
|---|---|---|---|
| Voice | Voice conversation, plan cards, the island (Whole Doddy only, ADR-653), the BLIK, email and errand cards; the wake word was removed (ADR-549) | 254, 265 | V1_VOICE_STATUS, VOICE_PROVIDER_TEST_STATUS |
| Voice (BLIK card), Connections › Money | BLIK phone transfer shown for the user to send in their bank app; Doddy never sends money | 483 | BLIK_TRANSFER_STATUS |
| Opening | Animated intro, listen on open | 225 | OPENING_SCENE_STATUS |
| DesignSystem/Motion (on the default branch since 20 Oct, #111; his eyes, ADR-560, #114) | One persistent Doddy: director, drawing, clock; the engine is in DoddyCore `Motion/` | 554, 555 | MOTION_V2_PLAN (in `docs/design/`), MOTION_V2_DEVICE_CHECKLIST, MOTION_V2_ART_REQUESTS |
| Onboarding | Introduction, storybook welcome | 299, 380 | ONBOARDING_STATUS |
| Welcome (on the default branch since 23 Oct, #132) | First-launch welcome "One morning in Warsaw": five chapters, a persistent Doddy, a sign-in sheet (Apple is real, the rest not connected yet); `DoddyCore/Welcome/` for the maths | 598, 599 | WELCOME_STATUS |
| Home | Home screen: the calm "I'm here" Home (ADR-545); Doddy talks on Home (ADR-595); the island extension while he talks, a thin strip at the island's height that follows his real loudness (`IslandExtension.swift`, ADR-654, 655, 665); the leaflet offers card after a voice search (ADR-666) | 323, 380, 545, 595, 654, 655, 665 | ONBOARDING_STATUS, V3_ISLAND_STATUS, ISLAND_SMOOTHNESS |
| Shopping (`Features/Shopping`) | Leaflets: "Cheapest this week", the basket, My shops (Apple Maps, kept on the iPhone), "Remind me on …" for a later price, partner links on an offer's own page (none signed); a task's three picks and its PDF report; the price watch (off on the server). Readers for each shop are on the messaging server | 607 to 614, 659 to 664, 666 to 669 | SHOPPING, SHOPPING_WATCH |
| Memories | Notes list, find, detail, corrections. No tab of its own since ADR-633: opened from Settings › Doddy's memory (and Find, links, widgets) | 252, 310, 607 | MEMORY_HISTORY_STATUS, M1_STATUS |
| Files | Home's Files sheet (ADR-633): files Doddy made on his server (`GET /v1/web/documents` with the phone's session, `MadeDocumentsClient` in DoddyCore), opened in Quick Look; and Recordings | 564, 607 | SETTINGS_SIMPLIFIED |
| Capture | New-note editor, "Save to Doddy" | 179 | M1_STATUS |
| Lists | Lists, templates, share card, shopping mode; quantities, the At home list and barcodes (Shopping list+, merged 25 Oct, #140) | 216, 257, 334, 631 | LISTS_STATUS, SHOPPING_MODE_STATUS, SHOPPING_LIST_PLUS |
| Parcels, Invoices (`Features/Parcels`, `Features/Invoices`, `Infrastructure/AccountKeyStore.swift`, `Network/InPostTrackingClient.swift`; on the default branch since 27 Oct, #141) | InPost parcel status by number on a list that is off until turned on; the person's own inFakt key in the Keychain and the invoice card. **Nothing can be sent to inFakt** (its wire format is unverified). Rules are in DoddyCore `Invoices/` and `Parcels/`, tested on Linux; the SwiftUI, the Keychain and the InPost client compile in the hosted Mac job but **have not run on a device** | 640, 641 | INFAKT_STATUS, INPOST_STATUS |
| NoteReminders | Time and place reminders on notes; "Ring like an alarm" through AlarmKit (`Alarms/ReminderRinger`, ADR-651) | 196, 211, 651, 652 | M4A_NOTE_REMINDERS_STATUS, PLACE_REMINDERS_STATUS, RINGING_REMINDERS_AND_WEEKLY_PLAN, STOPWATCH_AND_SHOP_LIST |
| Settings | Settings, island style, personality, what Doddy learned ("Hey Doddy" was removed, ADR-549) | 254, 440, 549 | HEY_DODDY_STATUS (history), M6_LEARNING_LOOP_STATUS |
| Messages (was Ask) | The typed conversation with Doddy, drawn like iMessage in Doddy's colours: bubbles saved on this iPhone until deleted; answers from Claude through the messaging server (`POST /v1/assistant/ask`); a mic button that dictates into the box; a photo sent with a question (made smaller, kept nowhere); files Doddy made and finished tasks as cards; a read-only copy, encrypted and without photos, on Doddy's server for Doddy Web | 585, 586, 605, 606 (115) | MESSAGES_STATUS, MESSAGES_DICTATION, MESSAGES_PHOTOS, MESSAGES_ATTACHMENTS, MESSAGES_TASK_RESULTS, MESSAGES_WEB_SYNC, M2_STATUS |
| Web (`Features/Web`, `Infrastructure/WebMemoryClientFactory.swift`, DoddyCore `OnlineAccounts/WebMemory*`) | Sign in to Doddy Web; **Keep on Doddy's server** (ADR-603): two switches for notes and conversations, a consent screen, "Delete everything on Doddy's server". Rules and the HTTP client are in DoddyCore and tested on Linux. The SwiftUI screens and the call from the voice controller compile in the hosted Mac job but **have not run on a device** | 603 | CLOUD_MEMORY |
| Activity | "What Doddy did" and undo | 268, 271 | ACTIVITY_UNDO_STATUS |
| Alarms | Alarms by voice (AlarmKit, iOS 26); timers ring through AlarmKit too, with a Lock Screen countdown (`TimerRinger`, ADR-650) | 260, 283, 650 | ALARMS_STATUS, NOTIFICATIONS_AND_TIMERS |
| Backup | Encrypted backup file | 222 | ENCRYPTED_BACKUP_STATUS |
| Birthdays | Birthday reminders from contacts | 288 | BIRTHDAYS_STATUS |
| Calls | Calling Doddy on the phone, PIN | - | S2_CALLS_STATUS |
| CallCases | Calls Doddy makes for you: brief, card, live call with take over, answer card, rehearsal, Live Activity | 500–507 | CALL_CASES_STATUS |
| Connections, ConnectedApps, OnlineAccounts | Calendar, Reminders, Contacts, Steps (Motion & Fitness), Presentations; online apps. The permission sheet that slides up in a conversation is `Voice/PermissionAskSheet.swift` | 291, 309, 566, 568 | APPLE_CONNECTIONS |
| Health (`Features/Health`, `Infrastructure/Health`, DoddyCore `HealthGlance`; merged 25 Oct as #137) | Sport mode: Connections › Apple Health, read only, the last 7 days on that screen (step 1); "Ask Doddy about this week" puts an exact summary into Messages after a consent of its own, sent only by the person's tap (step 2); `read_health_week` by voice after its own consent (step 3); training plans: the engine in DoddyCore `Sport/` and Connections › Training plan (`Features/Sport`), kept on the iPhone (step 4); asking for a plan by voice (`open_training_plan`, a card and a tap) or from a card in Messages opens that screen with the goal filled in, and the safety questions stay on the screen (step 5, ADR-626, merged 27 Oct as #144); the training log and weekly review in `Features/Sport` (ADR-642, #142, `SPORT_PLAN_STATUS`). Rules tested on Linux; the hosted Mac run builds it and passes every UI test, the plan flow included (run 40128474881); not on a device | 620 to 626 | SPORT_MODE_STATUS |
| Presentations | Slides by voice: the card, the .pptx file Keynote opens (`PresentationFile` in DoddyCore), the share sheet | 567 | APPLE_CONNECTIONS |
| Errands | Tasks handed to Doddy's background worker: the Tasks list and result card (Home's ••• menu), Home's "Done" card, `hand_over_errand` and `check_errands` in Voice | 570 | ERRANDS |
| Focus, Tools | Focus timer and its Live Activity (the breathing exercise was removed, ADR-550) | 241, 242, 550 | - |
| Stopwatch | A stopwatch that counts up: Home › Stopwatch, Lock Screen and island, three voice tools (`Features/Stopwatch`) | 652 | STOPWATCH_AND_SHOP_LIST |
| Import | Google Keep and text import | 231 | NOTE_IMPORT_STATUS |
| LeaveBy, Parking, Today | Time to leave, parking spot, Today card | 335, 301 | TODAY_STATUS |
| Meaning | Find by meaning (on-device) | 227 | MEANING_SEARCH_STATUS |
| MorningCheckIn, EveningWrapUp, WeeklyLookBack, WeeklyPlan, TidyUp | Daily and weekly routines; quiet hours 22:00–07:00 for all of them (ADR-651) | 220, 261, 306, 228, 651 | MORNING_CHECKIN_STATUS, EVENING_WRAPUP_STATUS, TIDY_UP_STATUS, RINGING_REMINDERS_AND_WEEKLY_PLAN |
| News, Updates | Daily news, server notifications and texts; **Following** (`News/FollowingView.swift`, Home › •••): the publishers' stories behind what the person follows, as a feed of cards, Poland by default; "śledź CPK" by voice (`follow_news`, on the live agent since 28 Oct); on `claude/message-tracking-plugin-rd0cbn`, **SwiftUI NOT COMPILED** | 174, 175, 656, 657 | N1_NEWS_STATUS, S1_SERVER_STATUS, FOLLOWING_STATUS |
| Photos, VoiceMemos | Photo notes (picker and, since ADR-569, Doddy's camera), the photo search card, voice memos | 218, 230, 569 | PHOTO_NOTES_STATUS, VOICE_MEMOS_STATUS, APPLE_CONNECTIONS |
| Privacy | Face ID lock, "What leaves this iPhone" | 310 | - |
| Settings | Fourteen rows in four groups and their pages (`SettingsView`, `SettingsHubs`, `SettingsScreens`); the Action Button choice | 580, 579, 607 | SETTINGS_SIMPLIFIED, ACTION_BUTTON_ISLAND |
| Release scope (`Infrastructure/ReleaseScopeStore.swift`, DoddyCore `ReleaseScope.swift`) | Which features this build shows: `ReleaseScope.shipping` hides a feature's every way in (voice tool, Home, Settings, Connections, quick actions, languages); Debug builds can show everything from Settings › About › Advanced. **NOT COMPILED** (7 Nov) | 813 | RELEASE_SCOPE |
| Onboarding | "Before we start": Terms acceptance (`LegalAcceptanceView`, `LegalAcceptanceStore`), then the optional introduction | 581 | LEGAL_PAGES_OWNER_CHECKLIST |
| QuickActions, Spotlight | Icon menu, iPhone search | 339, 330 | - |
| Setup | Ways to open Doddy: Back Tap guide, Action Button (talks in the island, ADR-632), control, Siri | 380, 558, 579, 632 | V2_SHORTCUT_SETUP_STATUS, ACTION_BUTTON_ISLAND |
| Sharing | Shared lists through iCloud | 263 | SHARED_LISTS_STATUS |
| Translator | Translator mode | 215 | TRANSLATOR_STATUS |
| Watch | iPhone side of the Watch app | 232 | APPLE_WATCH_STATUS |
| Widgets | Keeps the widget snapshot current | 219, 331 | WIDGETS_STATUS |
| Recordings (DODDY Capture) | Record a meeting or conversation (button, Siri, the Action Button's control, the island), on-device words, search, "Remember this". Logic in `DoddyCore/Capture/`, rows in `v16_recordings`. The app layer compiles in the hosted Mac job; **not run on a device** | 588–592 (579–583 on its branch) | CAPTURE_STATUS, CAPTURE_AUDIT |

**Other app folders:**
- `DoddyApp/App`: entry, `RootView`, iPad sidebar.
- `DoddyApp/Infrastructure`: stores, Keychain, network transports, shortcut router.
- `DoddyApp/Intents`: Siri and App Shortcuts.
- `DoddyApp/DesignSystem`: theme, components, Doddy art.

**Extensions:**
- `DoddyWidgets/`: Home and Lock Screen widgets, controls, Live Activities.
- `DoddyShare/`: "Save to Doddy" in the Share Sheet.

## Checks that run without a Mac
`scripts/ci.sh --core-only`: DoddyCore tests, the capability guard, the strings catalog, the voice agent spec and the platform specs. SwiftUI code compiles only in Xcode.

## The hosted build on a pull request (ADR-680)
Two jobs start together: `core` on Linux (`scripts/ci.sh --core-only`, about 15 minutes) and `ci` on a Mac (`scripts/ci.sh --app-only`: DoddyCore on Apple's Foundation, the app build, the unit tests and the UI tests, on one simulator). Both must be green. The Mac skips only what `core` runs and lists it as SKIPPED. Locally, `scripts/ci.sh` with no flag still runs everything; `DODDY_UI_TEST_WORKERS=2` runs the UI tests on two simulator clones, which a Mac with more cores than the hosted one may manage. For a design change to the Dynamic Island, the quick island-only run (ADR-618, Actions › iOS build and tests › Run workflow, `only: island`) gives pictures in 15 to 20 minutes.
