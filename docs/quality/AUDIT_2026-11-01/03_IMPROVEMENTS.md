# Where to make Doddy better (audit backlog, 1 Nov 2026)

Part of the research audit of 1 Nov 2026, read at commit `1a7dd21`. These are opportunities, not bugs. Each one comes from code that was read, with `file:line`. Security findings are left out here and went to the owner privately. Nothing was built or measured unless a line says so: timings come from repo documents or are marked "not measured". Native iOS code was read, not run (no Xcode).

**Effort:** S = under a day, M = a few days, L = a milestone. **Needs the owner** = changes a recorded decision, the live agent (changed only on the owner's instruction), a provider, or the cost.

## Ranked

| # | Improvement | Why it helps the person | Effort |
|---|---|---|---|
| 1 | Trim the voice agent's prompt and tools from about 48k to about 20–25k tokens per turn (P1–P3) | Faster first word and lower cost on every turn; the rules stay enforced in code | S, needs the owner (sync) |
| 2 | Wake the free backend before it's needed, and say "slow", not "offline" (R1, R2, R6) | No more "You're offline" on good Wi-Fi after a quiet spell | S |
| 3 | Put a 10-second limit on starting a voice session (R4) | The documented fix for silent 30-second "ghost" sessions | S |
| 4 | Make the first word sooner: refresh the voice token ahead of time, fetch it alongside local loading, and run the token server's two Redis reads at once (S1–S3), measured first (S5) | Shorter wait after tapping | S |
| 5 | One place that shows, exports and deletes everything Doddy keeps, on the phone and every server (V1–V4) | Someone can see and remove their data in one go | M |
| 6 | A time limit on the main voice agent's recordings (V1) | The other two agents already have one; this one keeps recordings with no limit | S, needs the owner |
| 7 | Pushes that open the right screen, and waiting call notes on Home (I1, I2) | Today every server push lands on Home | S–M |
| 8 | Errands survive a deploy (R8) | A deploy no longer turns a running task into "Doddy couldn't finish" | S–M, needs the owner (cost) |
| 9 | Share one memory-search module between servers (H4) | Search by phone finds inflected Polish names ("Anny" for "Anna"), as the app and web do | S |
| 10 | Faster, truthful test runs: one PGlite per backend test file; messaging database suites that fail, not skip, in CI (T1, T2) | The backend suite goes from about 7 min to well under 2 (estimate); a green local run means what it says | S–M |
| 11 | Durable replies when texting Doddy (R9) | A restart no longer drops a reply without a trace | M |
| 12 | Cheaper model calls: prompt caching (S); Sonnet for most errands, and a shared leaflet catalogue (owner decisions) (C1–C3) | Lower running cost | S to L |
| 13 | Retire dead paths: `gateway/`, `POST /v1/assist`, the old Connected Apps calendar, the `ToolExecutor` stub, `IslandStyle` (H1) | Less code, less CI time, fewer wrong screens | M, needs the owner (decision 11) |
| 14 | Fix settings text that says built things aren't built (H3) | Honest screens | S |
| 15 | Fix the website's "Your notes stay on your iPhone" lines (H5) | A true privacy claim | S |

## Speed and cost

### The voice prompt (P)
Measured on `1a7dd21` (bytes; tokens estimated as characters ÷ 4):

| Part | Size | About |
|---|---|---|
| `voice-agent/instructions.md` | 52,360 bytes, 225 lines | 13.0k tokens. The `# Tools on the phone` section (`instructions.md:112-171`) is 23,964 characters, 46% of it |
| `voice-agent/tools.json` | 165,990 bytes, 100 tools (96 on the phone, 4 web) | 41.4k tokens. The `x_doddy` fields (17.2k characters) are stripped before the model sees them |
| tools as the model sees them | 132,191 characters | 33.0k tokens: 83.3k characters of descriptions, 41.3k of parameter JSON |
| runtime variables | up to about 10k characters | notes budget 6,000 and conversations 4,000 (`VoiceContext.swift:80-81`) |
| **per conversation turn** | | **about 48k tokens** |

Growth: from 24 Oct to 1 Nov the tools went from 94 to 100, `tools.json` from 154 KB to 166 KB and the instructions from 48.5 KB to 52.4 KB. That is about 1.5–2 KB of prompt per new tool, and nothing sets a budget. The 40 online-account tools are 48.5k characters (about 12k tokens), sent even to someone who connected no account.

The largest tools (characters the model sees: total / description / parameters):
1. `remind_me_about_note`: 3,918 / 1,749 / 2,089.
2. `hand_over_errand`: 3,568 / 2,150 / 1,342.
3. `change_reminder`: 3,339.
4. `create_calendar_event`: 2,831.
5. `change_calendar_event`: 2,799.
6. `find_deals`: 2,622.
7. `create_reminder`: 2,563.
8. `make_presentation`: 2,142.

Suggestions, largest saving first:
- **P1. Drop the ASK-01 endings repeated in 55 tool descriptions** (26,061 characters, about 6.5k tokens). The rule is stated once in `instructions.md:19-27`. Code enforces it through `x_doddy.ask`, `AskFirst`, `ToolCatalogTests` and `check_forbidden_capabilities.sh:205`, and `speak_before: "force"` is already on 89 tools. Keep at most a short tag per tool. S.
- **P2. Move repeated sentences into `instructions.md:214` (`# Online account rules`).** About 7k characters (1.8k tokens) are repeats:
  - "If the tool is switched off or the account isn't connected… Settings, Online accounts", 19 times;
  - "Never say it was done unless the result says so; 'unknown'…", 14 times;
  - the result-prefix list, 14 times;
  - "If the result starts with DEMO DATA…", 9 times;
  - 83 Polish examples (4.2k characters) for an agent that speaks 37 languages. S.
- **P3. Give each tool's guidance one home.** `# Tools on the phone` names 95 of the 100 tools in 55 bullets, and much of it repeats the tool descriptions (`read_health_week` 0.74 overlap, `hand_over_errand` 0.67, `save_memory` 0.64). Cut it to cross-tool policy. Saves about 10–14k characters and removes a second source of truth. S–M.
- **P4. Put the 40 online-account tools behind one tool** (e.g. `online_account {account, action, args}`). The server already checks every action's arguments with typed schemas (`backend/src/tools/catalog.ts`). Saves about 9–10k tokens. The trade-off is that the model loses each action's schema, and the card and the server's approval must include the action. M–L. A smaller step is to merge families by a parameter (calendar `phone|google|outlook`: 16 → 5 tools; mail `gmail|outlook`: 17 → 9).
- **P5. Load conditional text only when it applies:** the translator rulebook (`instructions.md:3-18`, 2.9 KB) in the `start_translator` result, and the morning check-in and first-conversation text in their own variables. About 1k tokens. S.
- **P6. Add a size budget** to `scripts/voice_agent_spec.py check`, both per tool and in total. S.

Two notes:
- A tool's name is kept by hand in about 7 places: `tools.json`, `ToolCatalog.swift`, `CloudToolName` (`OnlineAccountsContracts.swift:174-240`), `CLOUD_TOOLS` and `TOOL_COPY` (`catalog.ts:2623-2720`), `LOGBOOK_TOOL_IDS` (`backend/src/web/logbook.ts:26`), `web/src/logbook/catalog.ts`, and the instructions. Renames therefore cost more than they look, and they change ElevenLabs tool ids.
- `voice-agent/README.md:76-81` says the live prompt was edited "in its own style", so it may not match `instructions.md` byte for byte. `voice_agent_spec.py compare` would show it.

### Time to Doddy's first word (S)
Not measured. The only recorded latencies are per turn: "LLM first token ≈ 0.8–1.0 s, first audio after the user stops speaking ≈ 1.3–2.2 s" (`docs/implementation/V1_VOICE_STATUS.md:63`).

The path from a tap on Home:
1. `VoiceAuthSession.restore()` (`HomeConversation.swift:71-77`). The access token lives 600 s (`server/voice-token/src/voice-auth.js:21`), so most starts make a round trip to refresh it first (`VoiceAuthSession.swift:34-52`).
2. Three local loads run one after another: `store.reload()`, `learning.voiceContext()` and `ErrandsModel.promptText()` (`VoiceSessionController.swift:670-687`).
3. The token request (`VoiceTokenClient.swift:22`). Inside it, two Upstash calls and the ElevenLabs token call run one after another (`voice-auth.js:314`, `handler.js:93,110`).
4. `ElevenLabs.startConversation` (`VoiceSessionController.swift:820`): connect, wait for the agent, send the start data, speak `{{opening_line}}`.

Changes:
- **S1** Refresh the access token when the app comes to the front and when Home appears (`RootView.swift:242`). S.
- **S2** Start the token request right after the microphone and consent checks, alongside the local loads, and await it where it's used (`VoiceSessionController.swift:631,796`). S.
- **S3** On the token server, run `getSession` and `hitLimits` at the same time, or merge them into one script (`voice-auth.js:312-316`). S.
- **S4** Skip `store.reload()` when nothing changed (`:670`). Measure first. S.
- **S5** Fill the empty table in `docs/implementation/LAUNCH_PROFILING.md`, and add signposts for tap → token → connected → first agent audio. S.

### App start-up
The deferred jobs (ADR-547) wait 1.5 s and run one at a time (`DoddyApp/App/LaunchWork.swift:51-83`). The launch task still resends failed conversations and refreshes the "open ways" reminder on the critical path (`RootView.swift:211-228`). Move `retryConversations` and `OpenWaysReminderScheduler.refresh` into `LaunchWork.later()`. S, not measured.

### Model calls (C)
- **C1. Prompt caching.** The Messages assistant's system prompt (about 3.7k characters) has no `cache_control` (`server/messaging/src/assistant/responder.ts:38-47`), and neither does the backend's `structured()` used by web chat (`backend/src/tools/claude.ts:266-276`). Leaflet vision already caches (`deals/vision.ts:395-396`). S.
- **C2. Sonnet for most errands.** Errands default to Opus 5.5 at high effort for up to 30 min (`server/messaging/src/config.ts:82,323`). The repo's cost research suggests Sonnet 5.5 for most errands and the Batch API for non-urgent ones (`docs/research/2026-10-24/research_costs.md:100`). S, needs the owner.
- **C3. A shared leaflet catalogue.** Leaflet search repeats the same vision work on every search (`deals/vision.ts:362-375`; "nothing is stored… no index shared between users", `docs/implementation/SHOPPING.md:82`). The doc estimates about 256,000 input tokens to screen Biedronka alone on every search (`SHOPPING.md:152`). Read each leaflet week once, independent of the query, and match items in code. M–L, needs the owner (it reverses a recorded choice).

### Queries and housekeeping (Q)
- **Q1.** News housekeeping (one UPDATE and two DELETEs) runs on every digest pass, every 10 s (`news/digest.ts:177-180`, `workerLoop.ts:130-139`). That is about 26,000 statements a day, and neither table has an index on the time column it filters (`migrations/003_news.sql:50,64-69`). Move them into the hourly tidy (`workerLoop.ts:114-120`). S.
- **Q2.** The backend prunes `attempts`, `approvals` and `documents` by time columns that have no index (`backend/src/store.ts:673-674,746`). Add indexes if these tables grow. S.
- **Q3.** Several messaging tables have no retention sweep: `outbound_messages` after the body is erased, `calls`, `assistant_usage`, `deals_usage`. Add an hourly sweep. S.
- **Q4.** The backend's hourly sweeps run only while the free instance is awake (`backend/src/app.ts:148-169`), so stated retention can run late. Also filter expired rows when reading. S.

## Reliability (R)
- **R1.** The free `doddy` backend sleeps (`render.yaml:21`); a repo doc says it takes about 20 s to wake (`docs/implementation/MESSAGES_STATUS.md:60`). The app's client for it gives up after 20 s (`DoddyApp/Infrastructure/URLSessionTransport.swift:25,31`), and nothing warms it up. Send `GET /v1/health` when the app comes to the front and when a conversation starts, if a backend feature is in use, and retry idempotent GETs once with a longer timeout. S.
- **R2.** A slow server reads as "offline":
  - `Offline.isNoConnection` counts a timeout as no connection (`Packages/DoddyCore/Sources/DoddyCore/Offline.swift:18`);
  - Files and Doddy Web memory show "No connection" for any transport error (`FilesView.swift:219`, `WebMemoryModel.swift:247`);
  - the voice token client turns any error into offline (`VoiceTokenClient.swift:46-48`), which becomes "You're offline. Doddy's voice needs the internet." (`VoiceSessionController.swift:801,2274-2276`).
  
  Add a third state, "Doddy's server is slow to answer, trying again…", using the mapping in `AppHTTPTransport.failure(for:)` (`DoddyApp/Infrastructure/Network/AppHTTPTransport.swift:157-167`). S.
- **R3.** When the voice token server's session store is briefly down, it answers `server_not_configured` (`server/voice-token/src/handler.js:76-78,93-94`), and the app shows "Voice isn't set up yet" (`VoiceTokenClient.swift:98`). Use a separate code and message. S.
- **R4.** Nothing limits how long `ElevenLabs.startConversation` takes (`VoiceSessionController.swift:820`). "Bound the start (about 10 s)" is the recorded fix for the ghost sessions, still not built (`docs/implementation/VOICE_SESSION_STARTS.md:97`). S.
- **R5.** When voice fails to start, the only option is the error text (`VoiceView.swift:432-440`). Offer "Type it to Doddy instead", which opens Messages with what was already said. S.
- **R6.** An online-account write whose answer was lost is retried once after 1 s (`OnlineAccounts/CloudActions.swift:26-41`). On a sleeping backend both tries land inside the wake-up. R1 fixes this; waiting 5 s would help too. S.
- **R7.** Every voice start depends on the voice token server on Vercel, and STATUS records the Vercel account as blocked for previews (`STATUS.md:17`). Confirm production is unaffected, or move `handler.js` and `voice-auth.js` onto the always-on messaging service. M, needs the owner.
- **R8.** A worker deploy or restart fails every running errand: they end `interrupted`, the person gets "Doddy couldn't finish a task", and they never run again (`workerLoop.ts:76-90`, `errands/worker.ts:72-75`). After a crash the person waits up to the time limit plus 5 min (`errands/worker.ts:21-22,166-186`). Research only reads the web, so requeue once on a graceful shutdown. S–M, needs the owner (extra model cost).
- **R9.** A reply to a text sent to Doddy exists only in memory until it is queued (`routes/twilioWebhooks.ts:52-58`, `smsChat.ts:62-70`), so a restart drops it with no record. Store the inbound text, encrypted, in a small job table and let the worker answer it. M.
- **R10.** A push that times out isn't retried (`providers/apns.ts:89-93`), and there's no `apns-collapse-id` (`apns.ts:52`), so a retry would show a second banner. Add the collapse id, then allow one retry. S, needs the owner (the "unknown is never blindly retried" rule).
- What already works: outbox claims use `FOR UPDATE SKIP LOCKED`; a message stuck in sending becomes unknown and is never resent; idempotency keys are bound to the payload; backoff is 30/60/120/240 s (`server/messaging/src/outbox.ts`). Task calls commit their claim before dialling and never redial an unknown.

## Half-built (H)
- **Every tool has a handler, and every handler a tool.** All 100 names are handled: 50 in `VoiceTools.swift:283-391`, 45 in `CloudToolName`, `propose_plan` in `ToolGate.swift:30`, and 4 web tools. `ToolCatalogTests` and `AskFirstTests` check both directions. On the OpenAI voice the 4 web tools always answer "unavailable" (`voice-agent/README.md:307`); run them on the token server or leave them out of that path.
- **H1. Code with no caller:**
  - `POST /v1/assist` with `BackendAssistantClient.swift`: the app uses `ServerAssistantClient`, `AppEnvironment.swift:16`.
  - `PUT /v1/web/logbook/days/:day`: no Swift code sends Logbook days.
  - The whole `gateway/` package: unused since ADR-587, yet still tested in CI.
  - The old Connected Apps Google Calendar path: `backend/src/service.ts`, `calendar.ts`, `providers/*`, reachable only from the development server section, `SettingsScreens.swift:806-811`.
  - The `ToolExecutor` port, always `UnavailableToolExecutor` (`AppEnvironment.swift:68,96,123`).
  - `IslandStyle`, which has one case left after ADR-653 (`Shared/IslandArt/IslandScene.swift:18,123,368`; `DoddyToolAttributes.swift:28`).
  
  Retire them together. M, needs the owner.
- **H2. Doddy Web.**
  - Logbook: the page and the server routes exist, but `IPHONE_SENDS_LOGBOOK = false` and no iPhone code sends days, so the chat's Logbook context is always empty (`backend/src/web/chatContext.ts`). Build the sender (ADR-602), or hide Logbook from chat until it exists.
  - Kept memory: `IPHONE_SYNCS_MEMORY = false` says the iPhone part isn't built, but it is (`WebMemoryClient.swift:178-190`, `WebMemoryView.swift`); it just hasn't been compiled. Fix the comment, and turn the flag on when it ships.
  - `web/src/logbook/catalog.ts` marks 13 of its 30 tools as not asking first, which differs from `tools.json`, and puts 70 of the 100 tools under "Other". Generate it from `tools.json`. S.
- **H3. Settings text that says built things aren't built:**
  - `ConnectedAppsView.swift:68-77,320-329` lists Apple Calendar and Reminders as "Planned · Not built yet", though both are built through EventKit.
  - `SettingsScreens.swift:576` says "Cloud AI: Off (not built)".
  - `Capabilities.swift:84-91` leaves out Outlook and the Google and Outlook writes.
  - The comment at `Ports.swift:181` is stale. S.
- **H4. Memory search is copied between servers and has drifted.** `fold`, `STOPWORDS` and `queryTerms` are identical in `backend/src/memory/search.ts:11-28` and `server/messaging/src/memorySearch.ts:6-23`. Only the backend trims the last letter of longer words (`search.ts:38-44`), so search by phone (`routes/elevenlabs.ts:139`) can miss Polish inflected names. Share one module. S.
- **H5. Website copy.** `site/index.html:146` and `:449` say "Your notes stay on your iPhone." with no qualifier. They came back with the 24 Oct rewrite (`23e099d`, ADR-610), after the 2026-10-11 site review fixed them. The privacy note at `:390` is right but leaves out typed Messages (backend → Anthropic) and the kept-notes copy for Doddy Web. S.
- **H6. Other helpers duplicated across servers:**
  - AES-GCM wrappers (`backend/src/memory/crypto.ts`, `server/messaging/src/crypto.ts`);
  - `canonicalJson` (`backend/src/policy.ts:8`, `taskCalls/payload.ts:102`);
  - HTML entity decoding, four ways (`websearch.ts:190`, `deals/chains/common.ts:103`, `natura.ts:47`, `news/feeds.ts:23`);
  - local dates (`backend/src/time.ts:67,71`, `news/schedule.ts:19`, `deals/chains/common.ts:51`);
  - money (`shopping/money.ts:46,74`, `ccc.ts:94`, `common.ts:40`, `aldi.ts:63`, `natura.ts:146-147`);
  - ask-prompt building, three times (`gateway/src/prompt.js`, `backend/src/assist.ts`, `server/messaging/src/assistant/prompt.ts`);
  - tool titles in Swift and TypeScript that already differ.
  
  A small shared server package would hold them. M.
- **ADR spot-check.** One concrete claim each was checked in code for ADR-640, 641, 653, 655, 656, 657, 659, 660/669, 661, 663, 666 and 668, and none was contradicted.

## Tests (T)
- **T1. Backend tests take 416 s.** 98 tests take under 100 ms, and 347 take 2 s or more (median 2.95 s). Each harness boots a fresh PGlite and runs the whole schema (`backend/test/helpers.ts:49`, `webRig.ts:80`, `toolsRig.ts:40`; `store.ts:308-323`). One PGlite per file, with `TRUNCATE` between tests or a restored snapshot, should bring it well under 2 minutes (estimate). S–M.
- **T2. Messaging database suites skip quietly.** 11 suites print `# SKIP TEST_DATABASE_URL not set` (`server/messaging/test/helpers.ts:16-17`): server, Messages, calls, the deals route, errands, news, shopping, texting, call cases and their worker, and price watches. Yet the run reports `skipped 0`. CI supplies Postgres (`.github/workflows/ios.yml:130-142`), so a local green run means less than it looks. Use PGlite as the backend does, or fail when `CI` is set and the variable is missing. A schema per test file would also allow dropping `--test-concurrency=1`, which is needed today because every suite drops and recreates `public` on one shared database (`helpers.ts:19-22`). M.
- **T3. Untested paths:**
  - the task-call webhooks `connect-ended` (the "voice didn't connect, apologise" branch, `taskCalls/webhooks.ts:101-113`), `takeover-status` and `fallback` (`routes/taskCallWebhooks.ts:49,55,87`);
  - `GET /v1/news/catalog`;
  - `/healthz`.
  
  All of them take an injected clock, so they are easy to test. S.
- **T4. Tests that time real clocks:**
  - upper bounds on elapsed time (`dealsFetcher.test.ts:146`, `unit.test.ts:75`, `news.test.ts:83`, `errandsUnits.test.ts:283`);
  - polling the real worker loop, which sleeps 1 s (`news.test.ts:452-463`, `workerLoop.ts:20-24`);
  - races on 10–30 ms timers (`errandsUnits.test.ts:293,305`, `dealsFetcher.test.ts:149`, `dealsAction.test.ts:251`).
  
  Inject `sleep` and `now`, as `backend/test/helpers.ts:63` already does. S.
- **T5. Tests that fake what they test:**
  - `gateway/test/assist.test.js:169-176` swaps out global `setTimeout` for one literal value;
  - `server/messaging/test/errands.test.ts:228-231` re-implements the runner's cancel polling;
  - `web/test/memoryIphone.test.tsx:10` and `logbookIphone.test.tsx:11` force flags that are off in the shipped build. S.
- **T6. The app's riskiest code has the fewest tests.** Voice tool execution lives in the 4,354-line `VoiceSessionController.swift` and is covered only by Xcode tests. Moving it into DoddyCore behind the existing `ToolExecutor` port would make it testable on Linux. L.
- **Ports are fine:** every test server listens on port 0. DoddyCore coverage is broad: only 2 of 278 source files have types no test names.

## Privacy UX (V)
What Doddy keeps, and where someone can see, export or delete it:

| Data | Kept on | See | Export | Delete |
|---|---|---|---|---|
| Notes and lists | iPhone | Memories | JSON, text, Markdown (`SettingsScreens.swift:272-286`) | Delete all (`:314`), per note |
| Remembered conversations | iPhone | Settings | text (`RememberedConversationsView.swift:72`) | per item and all |
| What Doddy learned | iPhone | Settings | JSON (`LearnedView.swift:293`) | Delete everything (`:69`) |
| Recordings | iPhone | Recordings | transcript (`RecordingDetailView.swift:448`) | all (`RecordingsView.swift:56`) |
| Call cases | iPhone and server | Calls | Export my calls (`CallCasesView.swift:128`) | in Delete all; the server copy is removed on acknowledge |
| What Doddy did | iPhone | Activity | none | Clear this list (`ActivityView.swift:63`) |
| Notes and conversations kept for Doddy Web | backend | web Memory | yes (`backend/src/memory/routes.ts:119-127`) | app and web |
| Messages copy | backend | web, read-only | none | from the iPhone (`MessagesView.swift:70`) |
| Logbook | backend | web | yes | yes |
| Files Doddy made | backend, 7 days | app and web | one at a time | none; they expire |
| Connected accounts | backend and Composio | app | — | Disconnect, which revokes at Composio (`backend/src/providers/composioShared.ts:93-106`) |
| Tool receipts | backend, 90 days or 200 rows | web Activity | none | none |
| The backend account itself | backend | — | — | no delete route (`backend/src/http.ts`) |
| Messaging account, phone, consents, errands, watches, news, call notes, memory copy | messaging server | per feature | no export route | "Delete my Doddy messaging data" (`UpdatesSettingsView.swift:29`, `routes/account.ts:35-41`) |
| Voice account | voice token server | — | — | Delete voice account, which also revokes at Apple (`SettingsSupport.swift:266`) |
| Main voice agent recordings and transcripts | ElevenLabs | — | — | none; kept with no time limit (`STATUS.md:188`) |
| Phone line and task-call conversations | ElevenLabs | — | — | 30 days and 1 day, no audio (`voice-agent/phone/session.json:41-44`, `task-call/session.json:50-52`) |

- **V1.** Give the main agent the same `privacy` block the other two have (no audio, a retention in days) in `voice-agent/session.json`, and update `DataFlow.swift:134`. S, needs the owner (live agent).
- **V2.** One "What Doddy keeps" screen with a single "Delete everything everywhere". Today deletion is spread over four screens and three servers. "Delete all memories" (`SettingsScreens.swift:380-423`) leaves the conversation log, the activity log, the voice account, the messaging account, the backend and the Doddy Web copies. M.
- **V3.** Add `GET /v1/account/export` on the messaging server, and `DELETE /v1/account` on the backend: disconnect every account, delete receipts, documents, sessions, memory, Logbook and Messages, and read back zero. Then have the app's delete flow call all three servers. M.
- **V4.** "What is shared" says "Your memories stay on this iPhone" and lists only the account id, token and phone (`UpdatesSettingsView.swift:44`). The same server can also hold the memory copy for calls, errands, call cases, watches and news, and the delete text leaves them out (`:30`). S.

## Product ideas (I)
1. **Pushes that open the right screen.** Server pushes carry only an alert (`providers/apns.ts:51`), and the app routes only local notifications (`NoteReminderNotifications.swift:169-215`). So "Doddy took a note on your call" (`routes/elevenlabs.ts:177`), "your task's result is waiting" (`errands/worker.ts:25-27`) and the call result (`taskCalls/worker.ts:213`) all land on Home. Add a content-free field such as `{"open":"call-notes"}` and route it through `ShortcutRouter`. S–M.
2. **Waiting call notes on Home.** Today they are under Settings › Calls (`CallsSettingsView.swift:61-86`). S.
3. **A morning check-in that covers the night.** `MorningBriefing` holds only reminders and lists (`MorningCheckIn.swift:100-106`). Finished errands (`ErrandsModel.swift:47`), waiting call notes, price drops and call results are already on the phone or one fetch away. M.
4. **Logbook's iPhone half.** The server and web are live; the phone part isn't built (`docs/product/WEB_LOGBOOK.md:3,173`). The plan is accepted (ADR-602) and needs scheduling. M, new milestone.
5. **Keep made files on the phone.** The server deletes them after 7 days (`backend/src/store.ts:746`), and then the app says the server no longer has them (`FilesView.swift:206`). Offer "Keep on this iPhone", or save when a file finishes. S–M.
6. **When voice fails, keep going.** Offer typing (R5) and, when consent for the other voice is already on, "Try the other voice" (`VoiceSessionController.swift:734-737`). The second part needs the owner (the OpenAI voice is marked as testing, ADR-265). S.
7. **"Forget this conversation everywhere."** Reuse the task-call deletion at ElevenLabs (`providers/taskCalls.ts:196-200`, `server_data_deletions` in `migrations/008_call_cases.sql:211-233`) for app conversations. Not verified: whether the Swift SDK gives the app the conversation id. M, needs the owner.
8. **Errand, call and news results on Doddy Web.** Web shows only backend data. This needs one sign-in across both servers. L, new milestone.
