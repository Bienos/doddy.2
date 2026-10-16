# iPhone and iPad

**Build:**
- `make project-iphone`, scheme `Doddy`: no Watch app, the fastest way to work on the iPhone.
- `make project`, scheme `Doddy`: the shipping build, with the Watch app embedded.
- iPad is the same app target (`TARGETED_DEVICE_FAMILY 1,2`).

**State:** this is what the owner builds and uses. The known-good branch and the unmerged changes are in `/STATUS.md`. iPad work (sidebar, fixes) is in `docs/implementation/IPAD_STATUS.md`. Most of it is not compiled yet (PR #61).

## Voice: the core of the app
- **Code:** `DoddyApp/Features/Voice/` (18 files). Session: `VoiceSessionController.swift`. Screen: `VoiceView.swift`. Wake word: `WakeWordListener.swift`. Provider config: `VoiceConfig.swift`.
- **Agent:**
  - ElevenLabs `agent_0501m4et27vyeawrwqfdxxfszfa6`. The prompt and tools are in `voice-agent/` (`instructions.md`, `tools.json`, `session.json`). `python3 -I scripts/voice_agent_spec.py check` validates them.
  - The live agent is changed by the owner, never from the app.
  - The app sends dynamic variables at start (notes, lists, profile, `learned_context`, opening line). A variable the live prompt requires but the app doesn't send stops the call before it starts.
- **Providers:** ElevenLabs (default) or OpenAI Realtime, as a test switch on Home (ADR-265). `docs/implementation/VOICE_PROVIDER_TEST_STATUS.md`.
- **Status docs:** `V1_VOICE_STATUS`, `V3_ISLAND_STATUS` (Dynamic Island), `HEY_DODDY_STATUS`, `OPENING_SCENE_STATUS` (the intro and listen-on-open).
- **Requested follow-up gaps:** `docs/implementation/IOS_NEXT_FEATURES_STATUS.md` (kitchen timer Live Activity, wake-word setup, no-code voice setup, and notes sync).
- **To debug a voice problem,** look at the ElevenLabs conversation log for the agent first:
  - no conversation at all means the app failed before connecting;
  - a conversation with no messages means the session started without its start data.

## Feature map
Code lives under `DoddyApp/Features/<Folder>/`. Status docs are in `docs/implementation/`. Rules with no UI are in `Packages/DoddyCore/Sources/DoddyCore/`.

| Folder | What it is | ADR | Status doc |
|---|---|---|---|
| Voice | Voice conversation, plan cards, island, wake word | 254, 265 | V1_VOICE_STATUS, VOICE_PROVIDER_TEST_STATUS |
| Opening | Animated intro, listen on open | 225 | OPENING_SCENE_STATUS |
| Onboarding | Introduction, storybook welcome | 299, 380 | ONBOARDING_STATUS |
| Home | Home screen | 323, 380 | ONBOARDING_STATUS |
| Memories | Notes list, find, detail, corrections | 252, 310 | MEMORY_HISTORY_STATUS, M1_STATUS |
| Capture | New-note editor, "Save to Doddy" | 179 | M1_STATUS |
| Lists | Lists, templates, share card, shopping mode | 216, 257, 334 | LISTS_STATUS, SHOPPING_MODE_STATUS |
| NoteReminders | Time and place reminders on notes | 196, 211 | M4A_NOTE_REMINDERS_STATUS, PLACE_REMINDERS_STATUS |
| Settings | Settings, Hey Doddy, island style, personality, what Doddy learned | 254, 440 | HEY_DODDY_STATUS, M6_LEARNING_LOOP_STATUS |
| Ask | Typed questions (gateway) | - | M2_STATUS |
| Activity | "What Doddy did" and undo | 268, 271 | ACTIVITY_UNDO_STATUS |
| Alarms | Alarms by voice (AlarmKit, iOS 26) | 260, 283 | ALARMS_STATUS |
| Backup | Encrypted backup file | 222 | ENCRYPTED_BACKUP_STATUS |
| Birthdays | Birthday reminders from contacts | 288 | BIRTHDAYS_STATUS |
| Calls | Calling Doddy on the phone, PIN | - | S2_CALLS_STATUS |
| Connections, ConnectedApps, OnlineAccounts | Calendar, Reminders, Contacts; online apps | 291, 309 | - |
| Focus, Tools | Focus timer, breathing, their Live Activity | 241, 242 | - |
| Import | Google Keep and text import | 231 | NOTE_IMPORT_STATUS |
| LeaveBy, Parking, Today | Time to leave, parking spot, Today card | 335, 301 | TODAY_STATUS |
| Meaning | Find by meaning (on-device) | 227 | MEANING_SEARCH_STATUS |
| MorningCheckIn, EveningWrapUp, WeeklyLookBack, TidyUp | Daily and weekly routines | 220, 261, 306, 228 | MORNING_CHECKIN_STATUS, EVENING_WRAPUP_STATUS, TIDY_UP_STATUS |
| News, Updates | Daily news, server notifications and texts | 174, 175 | N1_NEWS_STATUS, S1_SERVER_STATUS |
| Photos, VoiceMemos | Photo notes, voice memos | 218, 230 | PHOTO_NOTES_STATUS, VOICE_MEMOS_STATUS |
| Privacy | Face ID lock, "What leaves this iPhone" | 310 | - |
| QuickActions, Spotlight | Icon menu, iPhone search | 339, 330 | - |
| Setup | Back Tap guide | 380 | V2_SHORTCUT_SETUP_STATUS |
| Sharing | Shared lists through iCloud | 263 | SHARED_LISTS_STATUS |
| Translator | Translator mode | 215 | TRANSLATOR_STATUS |
| Watch | iPhone side of the Watch app | 232 | APPLE_WATCH_STATUS |
| Widgets | Keeps the widget snapshot current | 219, 331 | WIDGETS_STATUS |

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
