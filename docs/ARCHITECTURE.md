# Doddy architecture: what the code does today

Written 2026-10-18 from a read of branch `claude/affectionate-lovelace-4qyfwm` (main is `claude/loving-dirac-uuxoux`; this branch is 2 commits ahead, see §14). It describes the code, not the plans in `docs/architecture/` (several of those are stale, §14). Nothing was compiled for this page: there is no Xcode or Swift on the machine that wrote it. The Node test suites were run (§13).

Labels: **built** = code exists and is wired; **live** = seen working against the real provider; **not run** = never exercised for real.

---

## 1. Stack

| Layer | Technology | Where |
|---|---|---|
| iPhone and iPad app | SwiftUI, Swift 6, iOS 17+, `@MainActor @Observable` stores, XcodeGen (`.xcodeproj` is generated, never committed) | `DoddyApp/`, `project.yml`, `project-iphone.yml` |
| Shared core (no UI) | Swift package `DoddyCore`: products `DoddyCore` (rules), `DoddyPersistence` (SQLite through GRDB 7.9.0), `DoddyDesignTokens`. Foundation, GRDB and CryptoKit only, so it builds and tests on Linux | `Packages/DoddyCore/` |
| Extensions | Widgets, Live Activities and controls; Share Sheet "Save to Doddy" | `DoddyWidgets/`, `DoddyShare/`, `Shared/` |
| Apple Watch | watchOS 10 app plus complications; WatchConnectivity only, no database or network | `DoddyWatch/`, `DoddyWatchWidgets/` |
| Mac | Menu bar prototype plus a widget; own database; never compiled | `DoddyMac/`, `DoddyMacWidgets/`, `project-mac.yml` |
| Live voice | OpenAI Realtime (default when a token server is set, ADR-442) or ElevenLabs Agents (Swift SDK 3.3.1, LiveKit). Wake word: Picovoice Porcupine, on the device | `DoddyApp/Features/Voice/`, `voice-agent/` |
| Voice token server | Vercel functions (plain JS): Sign in with Apple sessions and provider tokens | `server/voice-token/` |
| Online accounts backend | Node 22 TypeScript, raw `node:http`, `node:sqlite`; Composio for Gmail, Drive, Notion, Todoist, Outlook, Google Calendar; Monid for web search; Render | `backend/`, `render.yaml` |
| Ask gateway | Vercel functions (JS), OpenAI Responses API, Upstash Redis for limits | `gateway/` |
| Messaging server | Node 22 TypeScript, Fastify, Postgres 16; APNs push, Twilio SMS and Verify, phone calls through ElevenLabs and Twilio, daily news (Anthropic or OpenAI); Render | `server/messaging/` |
| Landing page | Static HTML, CSS and JS plus waitlist functions on Vercel; www.doddy.lol | `site/`, `blog/`, `tools/build_*.py` |
| Checks | `scripts/ci.sh` (Linux: `--core-only`), GitHub Actions `ios.yml` (macOS and Linux jobs) | `scripts/`, `.github/workflows/` |

## 2. Folder map

```
DoddyApp/                 iPhone/iPad app
  App/                    DoddyApp.swift (entry), RootView.swift, SidebarLayout.swift (iPad)
  Infrastructure/         AppEnvironment.swift (composition root), stores, Keychain, HTTP transports,
                          Connections/DeviceConnections.swift (the only EventKit/Contacts/notifications code)
  Features/<41 folders>/  one folder per feature; Voice/ is the core (VoiceSessionController.swift, 3.5k lines;
                          VoiceView.swift, 1.6k lines). Feature map: docs/platforms/iphone.md
  Intents/                Siri and App Shortcuts
  DesignSystem/           Theme, components, Doddy art
  Resources/              Localizable.xcstrings, InfoPlist.xcstrings, AppShortcuts.xcstrings, Assets, PrivacyInfo
Shared/                   code compiled into the app and its extensions (Live Activity attributes, widget snapshot,
                          share inbox, island art)
DoddyWidgets/ DoddyShare/ DoddyWatch/ DoddyWatchWidgets/ DoddyMac/ DoddyMacWidgets/
DoddyTests/ DoddyUITests/ app unit and UI tests (need Xcode)
Packages/DoddyCore/       Sources/DoddyCore (rules), Sources/DoddyPersistence (SQLite), Sources/DoddyDesignTokens, Tests/
voice-agent/              the voice agent's spec: instructions.md (prompt), tools.json (58 tools), session.json;
                          phone/ = the separate phone agent
backend/                  online accounts and web search (Composio, Monid)
gateway/                  typed "Ask Doddy" (OpenAI)
server/voice-token/       voice sign-in and provider tokens
server/messaging/         push, SMS, phone calls, news (Postgres; migrations/)
contracts/ schemas/       JSON fixtures shared by app and server tests; JSON Schemas
l10n/                     translation tables that generate the String Catalogs
Config/                   Info.plists and entitlements for every target
scripts/ tools/           CI, guards, generators (strings, site, island art)
docs/                     status docs (docs/implementation/*_STATUS.md), platform pages, trust constitution, design
site/ blog/ design/ VISUAL_REVIEW/ assets/   website and design material
reference/                historical archives; not instructions
DECISIONS.md              the ADR log (one table row per decision, ADR 001-482). There is no docs/decisions/
STATUS.md                 one-page current state
```

## 3. How the app is put together

- **Composition root:** `DoddyApp/Infrastructure/AppEnvironment.swift`. `AppEnvironment.live()` opens the one SQLite file and builds the GRDB repositories (memories, profile, lists, list shares, photos, audio, note reminders, learning), the recall service, the Ask wiring and the capability catalog. It is passed down as a SwiftUI environment value (`\.appEnvironment`). One process-wide instance (`AppEnvironment.shared`) is shared by the app and Siri.
- **If the database can't open,** every repository becomes an `Unavailable*` adapter, saving is switched off, and nothing is reset or deleted (`storageProblem`).
- **State:** 32 `@MainActor @Observable final class` types. There is no `ObservableObject` or `@Published` anywhere.
  - Stores in `DoddyApp/Infrastructure/`: `MemoryStore`, `ActivityLogStore`, `ConversationLogStore`, `LearningStore`, `ProfileStore`, `UnfinishedNoteStore`.
  - Feature controllers: `VoiceSessionController`, `SharedListsController`, `CallsModel` and others.
  - `DoddyApp.swift` puts `MemoryStore`, `ProfileStore` and `NoteReminderStore` in the environment (`@Environment(MemoryStore.self)`); most views reach the repositories through `store.environment`.
  - There are 32 `static let shared` singletons (for example `ShortcutRouter`, which owns every presentation flag, `ActivityLogStore`, `VoiceAuthSession`).
- **Boundary:** DoddyCore defines protocols ("ports": `Ports.swift`, `Assistant/GatewayPorts.swift`, `Learning/LearningPorts.swift`, plus `ReminderStore`, `CalendarEventWriter`, `OnlineAccountsClient`, `ServerTransport`). The app implements the platform side: EventKit in `DeviceConnections.swift`, Keychain, `URLSession` transports. Rules (time parsing, idempotency, plan parsing, action status, undo rules, exports) live in DoddyCore and are tested on Linux.
- **Capability guard:** `scripts/check_forbidden_capabilities.sh` allows each sensitive API in one named place only. Examples: networking only in 6 transport files; EventKit, Contacts and CoreLocation only in `Infrastructure/Connections`; CloudKit only in `Features/Sharing`; no analytics SDKs. **It fails on this branch** (§14).

## 4. Data models and where notes are stored

### On the iPhone (the default home of all data)

**Notes, lists and everything attached to them** are in one SQLite file:
- Path: `Application Support/Memories/memories.sqlite` (`AppEnvironment.databaseURL`).
- The folder has iOS Data Protection `completeUntilFirstUserAuthentication`, and `PRAGMA secure_delete = ON`.
- **No SQLCipher**: the file itself is not encrypted beyond iOS Data Protection.
- The schema is in `Packages/DoddyCore/Sources/DoddyPersistence/DoddyDatabase.swift`: 13 migrations, append-only, and a newer-schema file is refused untouched.

| Table | Swift type | Notes |
|---|---|---|
| `memories` (+ FTS5 `memories_fts`) | `MemoryRecord` (`DoddyCore/MemoryTypes.swift`) | `raw_text` (exact words as accepted, never changes), `current_text` (latest correction), `source` (`explicit_text`, `explicit_voice`, `shared_content`, `imported_file`, `imported_legacy_unknown`, `sample_fixture`), `category` (9 note types, or `list`), `captured_at_ms`, `updated_at_ms`, `user_edited`. A list is a `memories` row with category `list` |
| `memory_corrections` | `MemoryCorrection` | Every correction, numbered, with its time (ADR-252) |
| `list_items` | `ListItem` (`Lists.swift`) | text, source, added, done, position |
| `note_reminders` | `MemoryReminder` (`NoteReminders.swift`) | One per note: time (with time zone, repeat, snooze) or place (lat/lon, radius, arrive or leave) |
| `memory_photos`, `memory_audio` | `MemoryPhoto`, `MemoryAudio` | One photo or recording per note. The files sit next to the database (`PhotoFiles` / `AudioFiles.beside(database:)`) |
| `profile_fields`, `onboarding_progress` | `ProfileField`, `OnboardingProgress` (`Profile.swift`, `Onboarding.swift`) | Approved "About you" answers. SQL CHECKs repeat the domain rules |
| `list_shares` | `ListShare` (`SharedLists.swift`) | Which list is linked to which iCloud zone, plus the last-sync base as JSON |
| `learned_facts` (+ FTS, revisions), `procedures` (+ FTS), `outcome_events` | `LearnedFact`, `Procedure`, `OutcomeEvent` (`Learning/LearningTypes.swift`) | Learning loop (ADR-440). Facts carry provenance and an evidence digest; status proposed, confirmed, retired or rejected |

**Write discipline:** every repository write is one transaction, read back before it reports success (`SQLiteMemoryRepository`). `MemoryStore.save` returns only after that read-back.

**Other on-device stores:**

| What | Where | Format |
|---|---|---|
| "What Doddy did" (activity log) | `Application Support/Activity/activity.json` (`ActivityLogStore`) | JSON array of `ActivityEntry`; pruned to 30 days / 300 rows; after 24 h a row loses its receipt, history and undo (`ActivityLog.withoutUndo`) |
| Recent conversations | `Application Support/Conversations/recent.json` (`ConversationLogStore`) | JSON transcript lines, only if "Remember recent conversations" is on |
| Unfinished notes | `Application Support/Drafts/unfinished-notes.json` (`UnfinishedNoteStore`) | JSON |
| Settings, switches, private-note IDs | `UserDefaults` (`PreferenceKey`, `privateNotes.ids`) | — |
| Secrets | Keychain: voice refresh token (`VoiceAuthSession`), messaging device token (`ServerKeychainStore`), gateway device credentials (`KeychainCredentialStore`), backend session (`KeychainSessionStore`) | `AfterFirstUnlockThisDeviceOnly` |
| Widget and Watch snapshot, share inbox | App Group `group.$(DODDY_APP_BUNDLE_IDENTIFIER)` (`Shared/Widgets/WidgetSnapshotFile.swift`, `Shared/Share/ShareInboxFile.swift`) | JSON files; never the full note text on the Watch complications |

### What leaves the iPhone today

| Data | Goes to | When |
|---|---|---|
| Saved notes (shareable ones, newest first, up to 6,000 chars), recent conversations, list names, approved profile, confirmed learned facts, personality | The voice provider (OpenAI or ElevenLabs) as session variables | **Every voice conversation start** (`VoiceSessionController.swift` ~531, `VoiceContext.savedNotes`). Profile and learned facts only if the user switched sharing on |
| Tool results (note text, calendar, reminders, contact names and birthdays) | The voice provider | During a conversation |
| Up to 8 matching notes, under aliases | Ask gateway (OpenAI) | Typed Ask only |
| Full current note list (corrected text, no private notes) | Messaging server, encrypted there with a server-held key (not end-to-end) | Only with "Memory on calls" on (`MemoryCopySync`) |
| Shared lists | iCloud (CloudKit) | Only if the build has the iCloud container and the user shares a list |
| Tool arguments (email drafts, Todoist tasks, search words) | Backend → Composio or Monid | When the user asks |

- **Static summary only:** Settings › "What leaves this iPhone" (`DoddyCore/DataFlow.swift`) describes these flows from the current settings. **There is no per-item log of data leaving the device.**
- **Private notes are excluded** from voice, Siri and Ask (`PrivateNotes.shareable`).
- **Memory-copy bug:** the first upload when "Memory on calls" is switched on sends `store.memories` unfiltered (`CallsSettingsView.swift:130` → `CallsModel.setMemoryCopy` → `uploadNow`). Private notes reach the server until the next change replaces the copy. Later uploads filter them (`RootView.swift:173`).
- **Exports don't filter private notes.**

### On servers

| Server | Stores |
|---|---|
| Messaging (Postgres, `server/messaging/migrations/001`-`007`) | `accounts`, `devices` (token hash, APNs token), `phone_numbers`, `outbound_messages` (outbox; body encrypted and erased when final), `call_settings` (PIN hash, lockout, consents), `memory_copies` and `call_notes` (AES-256-GCM), `calls`, `call_sessions`, `news_*`, `phone_verification_starts` |
| Backend (`node:sqlite`) | ID map to Composio user, connections (status, granted scopes), approvals (digest, outcome), receipts (content-free), usage counters, switches. **No OAuth tokens** (Composio holds them) **and no email, task or event content.** The free Render plan wipes the file on every redeploy |
| Voice token (Upstash Redis) | Voice sessions (refresh-token hashes), rate-limit counters |
| Gateway (Upstash Redis) | Rate and spend counters only |

## 5. The approval card

There is no single reusable "approval card" component. There is **one pending-card slot in the voice screen**, with one layout per action kind.

**From the model's tool call to a card:**
1. The provider sends a tool call. `VoiceToolRequest.parse` (`DoddyCore/VoiceTools.swift`) turns its JSON into a typed draft, or into `needsClarification` (for example, a time that has passed or is ambiguous) or `invalid`. Nothing is guessed.
2. `ToolGate.decide` (`DoddyCore/ToolGate.swift`) checks, in order: translator mode, plan, "Pause all", then the connection switch for that tool (Settings › Connections).
3. Look-ups run at once and reply. Every tool that changes something calls `propose()`, which sets `VoiceSessionController.pendingAction` (`PendingAction` enum: memory, event, reminder, timer, alarm, cancelAlarm, map, shortcut, message, cloud, noteReminder, createList, changeEvent, changeReminder, deleteEvent, deleteReminder, bulk, plan, undo, parking, leaveBy, ingredients). Only one card at a time; a second proposal is refused.
4. `VoiceView.actionCard` draws the card: a headline ("Add this reminder?"), the exact values that will be written (title, day, time and time zone, repeat, notes), a confirm button and a decline button. Which tools need a card is declared in `voice-agent/tools.json` (`x_doddy.confirm_on_screen`, 28 tools) and `DoddyCore/ToolCatalog.swift`; `scripts/voice_agent_spec.py` and `ToolCatalogTests` keep them in step.

**What happens on the tap** (`confirmPendingAction`, `VoiceSessionController.swift` ~1063):
1. The card is cleared (a second tap does nothing).
2. An "in progress" row is written to the activity log **before** the change runs. If the app dies mid-way, the next launch shows "Not sure" (`ActivityLog.recoverInterrupted`).
3. The action looks before it writes, using an operation key. Keys are FNV-1a over normalised content: `v1-` reminder, `e1-` event, `n1-` note, `c1-` cloud call, and others.
4. It writes, then reads back. Only a matching read-back counts as done.
5. The outcome is recorded with `ActionStatus` (`DoddyCore/ActionStatus.swift`): `proposed → pending → confirmed | failed | unknown | handedOff`, or `declined`. `unknown` is never shown as success. `ActionRetry` makes Doddy look first after an unconfirmed try, and stop after 3 unconfirmed tries in 24 h.
6. A receipt (what was read back, the app's own ID) is kept in the row.
7. An undo is offered for 24 h where possible (`DoddyCore/ActivityUndo.swift`): added event or reminder, changed event or reminder, list add, tick or remove, saved note. It runs only if the item is unchanged since. **Deletes can't be undone.**
8. The agent gets a text reply that starts with a fixed prefix (`added:`, `failed:`, `unknown:` …). **The activity row's outcome is parsed from that prefix** (`ActivityEntry.outcome(of:)`), not from a typed result.

**Several items on one card, with tick boxes:**
- **Plan card** (`DoddyCore/Plan.swift`, ADR-204/205):
  - The agent calls `propose_plan` with 2-5 steps, drawn from save note, calendar event, reminder, timer, Gmail draft, Todoist task and add to list.
  - Each step is validated as if it were asked for alone. Steps that can't run are shown as blocked (`PlanBlock`).
  - The user can untick steps or edit them (`PlanStepEditor`), and one tap runs the ticked steps in order.
  - Each step reports its own result line (`PlanReply.summary`); the status card stays after the conversation (`PlanStatus`).
- **Bulk card** (`DoddyCore/BulkChanges.swift`): delete events in a range or move reminders, up to 20 items, all ticked by default, each re-checked and read back.
- **Ingredients card**: tick what to add to a list.

**Online-account writes** (Gmail or Outlook draft, Todoist add, complete or move) need a second, server-side approval:
1. Before the card is shown, the app calls `POST /v1/tools/prepare`.
2. The backend validates the arguments and builds the preview text the card shows. It returns a single-use `approvalId`, valid 120 s, bound to the user, the tool, the connection and `sha256(canonicalJSON(arguments [+ looked-up target]))` (`backend/src/tools/service.ts`, `policy.ts`).
3. The tap sends `POST /v1/tools/run` with that ID. The server re-runs any lookup and spends the approval atomically.
4. A repeat of a used approval replays the first answer. An unknown outcome is recorded as `outcome_unknown` and never retried.
5. The tap itself is enforced only by the app UI.

**Writes that run without a card** (by design today, in `voice-agent/instructions.md` line 99 and `tools.json`):
- `add_to_list`, `check_off`, `remove_from_list`, with a receipt and Undo on the list card;
- `note_capability_gap` (a local row);
- `start_translator` / `stop_translator` (this branch removed the translator card);
- Siri's `AddToListIntent` and `CheckOffListItemIntent` (`DoddyApp/Intents/ListIntents.swift`), which write at once and leave **no activity row**.
- The voice screen footer still says nothing is saved "unless you tap" (`VoiceView.swift:258`).

**What a local card is bound to:** the typed draft held in memory. There is no payload hash for local actions, and the card is never persisted, so it is lost if the app closes.

**Other confirmation surfaces.** Each is hand-built, none shares a component, and none writes to "What Doddy did" or offers its undo:
- In the voice screen: "Worth keeping?" save suggestions (ticks, then "Save N notes") and learning cards.
- Evening wrap-up: ticks, then "Move N to tomorrow" (`EveningWrapUpViews.swift`). This moves Apple reminders.
- Note import (a toggle per note), memo to-dos, Quick start, tidy-up.
- The call-notes inbox: a note taken on a phone call is saved only after the user taps Save (`CallsModel`).
- Learned facts, confirmed one by one (`LearnedView`).
- About 25 system `confirmationDialog`s (delete, restore, clear, sharing), plus the note editor's Save and Delete with an Undo bar.

## 6. ElevenLabs and the live voice

1. **Sign-in:** before the first conversation, `VoiceAccessGate` asks for Sign in with Apple and a per-provider consent (this branch, `754e5d6`). `VoiceAuthSession` trades the Apple identity token at `POST https://doddy-voice-token.vercel.app/api/voice-auth` for a rotating refresh token (Keychain) and a 10-minute access token. The endpoint is hard-coded in `VoiceConfig.swift`; it is a public URL, not a secret.
2. **Provider token:** `VoiceTokenClient` calls `POST /api/voice-token` with the access token.
   - For ElevenLabs, the server (`server/voice-token/src/handler.js`) asks `GET /v1/convai/conversation/token?agent_id=…` with its own `xi-api-key` and returns a conversation token.
   - For OpenAI it returns a 120 s Realtime client secret (models `gpt-realtime-2.1[-mini]`).
   - It can also hand out the Picovoice key for "Hey Doddy".
   - **The app never holds a provider API key.**
3. **Session:**
   - **ElevenLabs:** `ElevenLabs.startConversation(auth: .conversationToken)` with dynamic variables (`saved_notes`, `saved_notes_count`, `saved_notes_truncated`, `recent_conversations`, `doddy_personality`, `user_profile`, `learned_context`, `saved_lists`, `translator_start`, `morning_checkin`, `first_conversation`, `opening_line`). A variable the live prompt needs but the app doesn't send stops the call before it starts.
   - **OpenAI:** `OpenAIRealtimeSession` opens `wss://api.openai.com/v1/realtime` and sends `session.update` with the bundled `voice-agent/instructions.md`, rendered on the phone with the same variables, and the same `tools.json`. Both providers sit behind `LiveVoiceLink`.
4. **Tools:** 58 in `voice-agent/tools.json`.
   - 54 run on the phone as client tools, handled in `VoiceSessionController`.
   - 4 run on ElevenLabs as web tools (geocode, weather, Wikipedia ×2); on OpenAI these answer "unavailable".
   - Tool results that contain stored or outside text wrap it in `<<<DATA … DATA>>>` (`ToolData`); the prompt says that text is data, never instructions.
5. **The live agents:**
   - Main: `agent_0501m4et27vyeawrwqfdxxfszfa6`. Phone: "Doddy (phone)", not created yet.
   - They are changed only by the owner (dashboard or connector). The app never edits them.
   - `voice-agent/` is the spec. `python3 -I scripts/voice_agent_spec.py check` validates it in CI (including the AI-disclosure line, DOD-03), and `compare` diffs it against the live agent.
   - The live agent is behind the repo on several changes (`voice-agent/README.md`).
6. **Status:** voice on ElevenLabs was live on 2026-10-11 (a 139 s call with `search_memories`, `save_memory`, `web_search`). The OpenAI default and this branch's Apple sign-in have **not run** on a device. Known bug: sessions sometimes start twice ("ghost" sessions, `STATUS.md`).

## 7. Phone calls: the Twilio number and the PIN

Calls connect **Doddy and its own user only**. Doddy never calls a third party. Code: `server/messaging/src/routes/{elevenlabs,calls,phone}.ts`, `src/calls.ts`, `voice-agent/phone/`, app `DoddyApp/Features/Calls/`, `DoddyCore/CallsClient.swift`.

**Setup, in the app** (Settings › Phone calls):
1. The app creates an anonymous messaging account (`POST /v1/accounts` → bearer device token in the Keychain).
2. It verifies the user's number with Twilio Verify (`/v1/phone/verification`, `/check`), with caps per number, per token and per server.
3. It sets a PIN: `PUT /v1/calls/pin`, 6-8 digits, no repeats or straight runs, stored as scrypt.
4. Optionally it turns on "Memory on calls", which uploads the full note list for the server to encrypt (§4), and outbound consent (`calls-v1`).

**Inbound call (the user dials Doddy's Twilio number):**
1. The number is imported into ElevenLabs (native Twilio integration). The server serves no voice TwiML.
2. While the phone rings, ElevenLabs calls `POST /webhooks/elevenlabs/call-start`, authenticated by the shared `X-Doddy-Tool-Secret`, compared in constant time.
3. The server matches the caller ID to a verified number and opens a 2 h call session. It returns `doddy_caller` (known, unknown, calls_off or unavailable), `doddy_memory`, `doddy_pin`, `doddy_direction` and `secret__doddy_session`. The `secret__` variable only ever goes in tool headers, never to the model.
4. The phone agent (`voice-agent/phone/instructions.md`, Gemini 2.5 Flash, English only) opens with *"Hi, this is Doddy, an AI assistant. How can I help?"*.
5. Before any memory search or note, it asks for the PIN and calls `verify_pin`. Caller ID alone is never trusted.
   - 5 wrong tries lock PIN entry, escalating 15 min → 1 h → 4 h → 16 h → 24 h, and each lock sends the owner a push.
   - `search_memories` decrypts the memory copy and returns matches with their saved date.
   - `save_note` puts an encrypted note in an inbox (max 20); it becomes a memory only after the user taps Save in the app.
6. The agent cannot send messages, set reminders, pay or contact anyone (prompt rule 5).

**Outbound** ("Call me now", `POST /v1/calls/outbound`):
- Only to the user's own verified number, only with consent.
- Limits: 3 per hour and 10 per day.
- Placed through ElevenLabs `twilio/outbound-call`. A failed or timed-out request is `unknown` and is never redialled.

**Gaps:**
- No recording or transcript disclosure on the call (transcripts are kept 30 days at ElevenLabs; audio is not recorded).
- The PIN passes through the LLM and its transcripts.
- No `end_call` for unknown callers.
- No call-completed state.
- **Status: not run.** The phone agent and Twilio number were never created. The messaging server is deployed (Render free plan, `doddy-messaging-zw1n.onrender.com`; its free database expires 2026-11-10), but release builds can't reach it: `ServerConfig.defaultBaseURL` is empty, and a typed address counts only in debug builds.

## 8. Integrations

| Integration | Access today | How | State |
|---|---|---|---|
| **Gmail** | **Not read-only.** List recent emails (`check_email`), read one (`read_email`, off until switched on), create a draft or a reply draft after a tap (`draft_email`, `draft_email_reply`). No send, delete or label tool | Composio toolkit; scopes `gmail.readonly` + `gmail.compose`. Compose also permits sending at Google's level (ADR-099, owner to accept) | Built, mock-tested; **never run against a real account** |
| **Todoist** | List open tasks; add, complete, re-date a task after a tap. Can't delete or change text | Composio; no OAuth scope check (`allowedGrants: null`) | Built, mock-tested; not run live |
| **iCloud lists** (shared lists) | Share one Doddy list with other people; sync items and a shared place | CloudKit, one zone per list (`Features/Sharing/ListCloud.swift`, `SharedListsController.swift`, merge rules `DoddyCore/SharedLists.swift`) | Built; **off by default** (`DODDY_CLOUD_CONTAINER` empty in `project.yml`); never run with two Apple IDs |
| Apple Reminders and Calendar (iCloud-synced on the device) | Read; add, change, delete, bulk move or delete, each after a tap, with read-back and undo | EventKit, only in `Infrastructure/Connections/DeviceConnections.swift`; off until switched on in Settings › Connections | Built; device read-back cases not run |
| Contacts | Look up names and birthdays | Contacts framework | Built |
| Google Drive | Find files by name (metadata only) | Composio, `drive.metadata.readonly` | Built, not run live |
| Notion | Search titles shared with Doddy; read one page | Composio; no scope check | Built, not run live |
| Outlook | List and read mail, read calendar, create a draft | Composio, Microsoft Graph scopes; `Mail.Send` refused as too broad | Built, not run live |
| Google Calendar (backend) | Read the next 7 days | Composio, older `/v1/connected-apps` API; any grant beyond read-only is blocked as `not_read_only` | Built, not run live |
| Web search | Up to 5 results: title, snippet, **site hostname only, no URL, no date** | Monid (`backend/src/tools/websearch.ts`) | Seen live once |
| Ask Doddy (typed) | Answers from up to 8 matching notes, with citations checked twice (gateway schema enum and `CitationVerifier` on the phone) | `gateway/` (OpenAI) | Deployed once 2026-10-10 (pre-Redis); current code needs Redis in production |

- **Backend:** `backend/` runs in mock mode by default. It refuses live + production "until real app sign-in exists" (ADR-077); sessions are owner-minted signed tokens.
- **Disconnect:** switches go off first, then the remote grant is revoked and deleted at Composio, with retries tracked in a `cleanups` table.

## 9. Exports and backup

All exports are in Settings and go through the share sheet (`SettingsView.swift` ~141-182, `BackupViews.swift`).

| Export | Format | Contents | Code |
|---|---|---|---|
| **Memories as JSON** (`doddy-memories.json`) | `{formatVersion: 1, exportedAtMs, memories: [MemoryRecord…], listItems?, corrections?}`. Each record: `schemaVersion`, `id`, `rawText`, `currentText`, `source`, `category`, `capturedAtMs`, `updatedAtMs`, `userEdited` (matches `schemas/memory.schema.json`) | Notes, lists with items, correction history. Not reminders, photos, audio, activity, learning | `MemoryExport.json` in `DoddyCore/Search.swift` |
| Restore from that JSON | Same format; strict, 20 MB max, refuses newer formats; only adds, never overwrites | — | `DoddyCore/MemoryRestore.swift` |
| Memories as text / Markdown | Plain text; Markdown with verbatim block quotes and earlier wordings | Same as JSON | `MemoryExport.plainText`, `MarkdownExport.swift` |
| Profile as JSON (`doddy-profile.json`) or text | `{formatVersion: 1, exportedAtMs, profile[], settings{}}` | Approved profile fields, style settings | `DoddyCore/ProfileExport.swift` |
| Learned facts, procedures, outcome events | JSON | Learning loop data | `SQLiteLearnedFactRepository`, `SQLiteProcedureRepository`, `SQLiteOutcomeEventRepository` |
| Conversations | Plain text | Kept transcript lines | `VoiceContext.swift` |
| Encrypted backup (`.doddybackup`) | `{format: "doddy-backup", version: 1, kdf: pbkdf2-sha256 ×600k, cipher: aes-256-gcm, sealed}`; passphrase ≥10 chars | Memories JSON, time reminders, profile, photos, recordings. Not learning, activity, conversations, list shares, place reminders | `DoddyCore/EncryptedBackup.swift` |
| Import | Google Keep JSON, text or Markdown, reviewed before saving (`source: imported_file`) | — | `DoddyCore/NoteImport.swift` |

## 10. Localisation

- **App screens:** Apple String Catalogs, one per target (`DoddyApp/Resources/Localizable.xcstrings`, `InfoPlist.xcstrings`, `AppShortcuts.xcstrings`, plus the widget, share, Watch and Mac catalogs).
  - SwiftUI literals (`Text("…")`, `Button("…")`) are looked up automatically.
  - **The catalogs are generated**, never hand-edited: `tools/build_strings_catalog.py` builds them from `l10n/<code>.json` (English key → translation), `l10n/<code>_infoplist.json` and `l10n/<code>_shortcuts.json`. `--check` runs in CI.
- **Languages:** source `en`. Columns for `pl` (the most complete, still not natively reviewed) and 8 machine-translated drafts (de, es, fr, hr, it, ja, pt-BR, zh-Hans). **No `uk` UI table** (Ukrainian exists only as a voice and translator language).
- **Default language: English** until the user picks another in Settings › App language (ADR-459, `DoddyCore/AppLanguage.swift`). A Polish iPhone opens Doddy in English.
- **Not covered by the catalogs:**
  - About 47-72 strings built at run time stay English (`docs/implementation/POLISH_SCREENS_STATUS.md`).
  - `StatusRow(title: String, value: String)` passes a plain `String` to `Text`, so its 51 uses are never looked up, though the generator counts them as covered (`DesignSystem/Components.swift`).
  - About 50 `message =` / `return "…"` English strings in models (for example `CallsModel`, `VoiceAuthSession`).
  - DoddyCore has **no** `String(localized:)`: its user-facing text is English with hand-written Polish branches on `NotificationLanguage` (17 files).
  - Text sent to the voice agent is English on purpose.
- **Voice:** OpenAI follows the language spoken. ElevenLabs has 37 language presets (`voice-agent/session.json`). The phone agent is English only.

## 11. Tests and checks

| Suite | Size | Runs on | Result here (2026-10-18) |
|---|---|---|---|
| DoddyCore + DoddyPersistence + tokens (XCTest) | ~1,095 tests, 140 files | Linux or Mac (`make test-core`) | **Not run** (no Swift here). STATUS.md records 934 passing on Linux |
| App unit + UI tests (`DoddyTests`, `DoddyUITests`) | 35 unit + 29 UI tests | Mac with Xcode only | Not run. Hosted CI passed them (26 UI tests then) since `c8aff7a`. Not covered: Calls, memory copy, export and restore UI, shared lists, wrap-up and tidy-up writes, Ask |
| backend | 205 | Node 22 | **205/205 pass** |
| gateway | 73 | Node | **73/73 pass** |
| server/voice-token | 19 | Node | **19/19 pass** |
| server/messaging | 55 (37 need `TEST_DATABASE_URL`) | Node + Postgres | Not run |
| `scripts/check_forbidden_capabilities.sh` | guard | any | **FAIL** (§14) |
| `scripts/verify_imported_pack.py` | 259 locked files | any | PASS |

- **CI:** `.github/workflows/ios.yml` runs on pull requests and manual dispatch.
  - macOS job: XcodeGen, then `scripts/ci.sh`, which runs `xcodebuild test` of `project.yml`.
  - Linux job: `swift:6.1` with Postgres, `scripts/ci.sh --core-only`.
  - `project-mac.yml` is built nowhere.
- **Locked files:** `PACKAGE_MANIFEST.json` locks 259 imported pack files byte-for-byte. `CLAUDE.md` and `AGENTS.md` are append-only: their first 3,688 and 3,392 bytes must not change.

## 12. What looks half-built

**Voice**
- The OpenAI Realtime default has never run on a device. Weather, Wikipedia and voice style work only on ElevenLabs.
- Double-start / "ghost" sessions are a known, unfixed bug.
- "Hey Doddy" is missing `hey-doddy.ppn` and a Picovoice key; never run.
- The live ElevenLabs agent lags the repo (`note_capability_gap`, `learned_context`, the translator change, the "call 112" line).
- This branch's Apple sign-in needs `server/voice-token` redeployed with new env vars (`APPLE_BUNDLE_ID`, `DODDY_SESSION_SIGNING_KEY`, `UPSTASH_*`). The deployed server is the older access-code version, so **voice can't start on this build until that is done**.
- ElevenLabs agent authentication is still off (ADR-034).

**Calls**
- No phone agent, no Twilio number, no call ever placed.
- English-only agent with no TTS voice set, and no `end_call`.
- Release builds point at no messaging server.
- Memory-copy key rotation is not implemented (`key_version` is always 1).
- `DELETE /v1/updates/:id` sets only `body = NULL`. With encryption on, it violates the `outbound_messages_body_erased_when_final` constraint (500). It is untested and has no app caller.

**Integrations**
- Every Composio slug and Composio's scope reporting have only run against mocks.
- Notion and Todoist have no scope check at all.
- The backend's free-plan SQLite resets on redeploy and can orphan Composio accounts.
- Tool-path errors reuse Calendar wording (`backend/src/errors.ts`; the fixture `contracts/online-accounts/error-rate-limited.json` says "Google Calendar is busy" for Todoist).
- `GET /v1/connected-apps` still lists Notion and Todoist as "planned".
- Three unrelated auth systems: backend owner-minted tokens, gateway invite tokens, voice Apple sessions. None is a real multi-user sign-in.

**Core**
- `ToolKind` / `ToolProposal` / `ToolExecutor` / `ActionReceipt` (`DoddyCore/Ports.swift`) are a dead first action model; real actions bypass them (`UnavailableToolExecutor` is wired).
- `LearningProposer.model` has no implementation.
- Activity rows keep list names and items for 30 days despite the comment saying they don't.
- Learning `deleteAll` doesn't read back.
- `ServerClient.swift` says memories "were never on the server", which contradicts the memory copy.

**Platforms**
- Mac: merged, never compiled.
- Watch: compiles in CI, never run.
- iPad sidebar: never seen.
- Widgets' `LiveActivityIntent` tick may do nothing in the extension.
- CloudKit sharing off by default.

**Localisation**
- Nothing natively reviewed or seen on a device.
- Polish plurals follow the English shape.
- DoddyCore strings sit outside the catalogs.

**Release**
- Placeholder bundle ID `com.bienos.doddy2.dev` and an empty `DEVELOPMENT_TEAM`.
- Draft privacy policy; no legal review; ElevenLabs spending limits not set.

**App**
- Private notes reach the calls server on the first memory-copy upload (§4).
- "What Doddy did" covers voice only. Wrap-up, tidy-up, memo to-dos, Quick start and Siri list writes leave no row and no undo.
- Connected Apps and Online accounts in Settings need a hand-pasted dev session token.
- The opening still draws the v1.3 SVGs from `Resources/Character` (`OpeningModel.swift`), against the character-art rule.
- `DoddyApp/Doddy.entitlements` is unused.
- Wrong copy:
  - The voice consent toggle says "for this conversation" but is saved permanently.
  - The contacts prompt names ElevenLabs while OpenAI is the default.
  - Two transports each claim to be the only HTTP client.

**Repo hygiene**
- The capability guard fails on this branch (`VoiceAuthSession.swift` uses `URLSession` and `AuthenticationServices`; `VoiceAccessGate.swift` imports `AuthenticationServices`).
- ADR-458 is used twice.
- This branch's two commits have no ADR, and the Apple sign-in conflicts with ADR-077/147.
- Listen-on-open now defaults off, reversing the owner decision in `OPENING_SCENE_STATUS.md`.

## 13. Missing for the case (sprawa) spine

These have no code today. They are listed so nobody mistakes an existing piece for them.

- **A case model.** No sprawa, case, matter, deadline or complaint type anywhere. `MemoryCategory` is fact, preference, commitment, recommendation, decision, item, place, intention, other or list. The nearest pieces:
  - `Plan` (one card, ≤5 steps, in memory only);
  - `ActionStatus` (one action's status);
  - `Procedure` (a learned, reusable plan template).
- **A durable action log per case.** `activity.json` is global, pruned at 30 days / 300 rows, and strips receipts after 24 h.
- **A versioned rules file** (deadlines, consumer rules, official URL, last-verified date). Nothing like it exists.
- **Sources with dates on outside claims.** Notes carry source and date, and Ask verifies citations. The voice path doesn't verify citations, and web search drops the URL and date.
- **A log of what leaves the device**, per item and per case.
- **Calls to third parties** (clinic, urząd, landlord), with the disclosure "AI assistant calling on behalf of …" and a recording notice.
- **A persisted approval** (a card survives an app restart), and approval bound to a payload digest for local actions.

## 14. Stale docs and this branch

**Stale against the code:**
- `docs/architecture/IOS_ARCHITECTURE.md`, `MEMORY_AND_DATA.md`, `TOOLS_AND_ACTIONS.md`, `VOICE_AND_APPLE_SURFACES.md` and `AI_RUNTIME.md` are locked imported proposals; they describe a planned module split, "local only, no sync", and single-step actions.
- `CONNECTED_APPS_PROPOSAL.md` and `INTEGRATIONS_AND_CHANNELS.md` call built features "later".
- `STATUS.md` still lists PR #44, #61 and #67's parts as unmerged; all are merged.
- `render.yaml`, `gateway/README.md` and `ServerConfig.swift` say "not deployed"; the backend, gateway and messaging server were each deployed once.
- `voice-agent/README.md` says "10 function tools" (there are 58).

**This branch** (`754e5d6`, `f40861c`, not on main):
- Sign in with Apple voice access (`VoiceAccessGate`, `VoiceAuthSession`, `server/voice-token/src/voice-auth.js`).
- A first-launch profile card on Home.
- Listen-on-open off by default.
- `start_translator` without a card.
- It also breaks the capability guard.
