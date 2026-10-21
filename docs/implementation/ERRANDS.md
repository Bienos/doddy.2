# Errands: Doddy works on a task in the background (ADR-566)

**Status, 21 Oct 2026:** built on `claude/doddy-sidekick-character-ofgjf5` (server, shared core, iPhone screens, voice spec); **switched off by default** (`ERRANDS_ENABLED=0`) until the owner turns it on. Owner: "2. Ok and no cap 3. Ok" (one yes per task, no limit on look-ups; a background task runner). **Nothing here has run against the real Anthropic API, a real database, APNs or a device.** The sections marked *Built* say what exists in code and which tests ran.

"Errand" is the code name for a *sprawa* the user hands over (`Task` is taken by Swift concurrency). The user never sees the word "errand": the app says "sprawa" in Polish and "task" in English.

## The flow

1. **In a conversation** the user hands Doddy something that takes real work ("sprawdź loty i hotele do Rzymu…"). Doddy repeats it in the user's words and asks at most one question (`voice-agent/instructions.md`, Task mode).
2. **One ask.** Doddy calls `hand_over_errand` with the user's exact words, its one-line brief (with any assumption it said out loud) and a short title. The app shows one card:
   > **Hand this to Doddy?**
   > "chcę jechać do Rzymu w przyszłym miesiącu na 7 dni, sprawdź loty i hotele do 2000 zł"
   > Doddy searches the web and reads pages as often as this needs, in the background, and sends you a notification when it's done. Nothing is booked, bought or sent.
   > **Yes, go**

   A spoken yes or a tap starts it (it reads the web and changes nothing; ASK-01's read rule). **That one yes covers every look-up of this errand, with no limit on how many** (owner, 21 Oct). It covers nothing else: no booking, no message, no other errand.
3. **The app creates the errand on the server, then approves it** with the digest the server returned for exactly those words (`POST /v1/errands`, then `POST /v1/errands/:id/approve`). The agent hears `started: …` and tells the user they can close the app.
4. **The server's worker researches it** with Claude and Anthropic's web search and web fetch tools, then writes the result card in a second call with a fixed schema.
5. **Done:** a push notification with no words in it ("Gotowe. Wynik sprawy czeka w aplikacji." / "Done. Your task's result is waiting in the app."), like call results (ADR-500). Pushes can't carry an id yet (`apns.ts` sends only title and body), so the app checks its open errands when it comes to the front and shows the finished one on Home and in Sprawy. The app saves the result on the iPhone, then tells the server (`ack`), which deletes its copy of the words, brief and result.
6. **Next conversation:** the app sends the recent errands (title, state, the result's first line) as `{{errands}}`; `check_errands` reads a whole result back to Doddy.

## Server API (`server/messaging`, bearer = the account's device token)

| Route | Body | Reply | Notes |
|---|---|---|---|
| `POST /v1/errands` | `{ words, brief, title, language }` | `201 { id, digest, title, words, brief, expiresAt }` | A draft, nothing runs. `words` ≤ 1,000 characters, `brief` ≤ 1,000, `title` ≤ 80, `language` a two-letter code. The digest is SHA-256 over the canonical JSON of `{words, brief, title, language}`. A draft expires after 10 minutes. |
| `POST /v1/errands/:id/approve` | `{ digest }` | `202 { id, state: "queued" }` | Only a draft, only with its own digest (`409 digest_mismatch`), only before it expires (`409 not_approvable`). `409 too_many_open_errands` past the per-account limit. `503 errands_disabled` when switched off or not set up. |
| `GET /v1/errands` | | `200 { errands: [ { id, title, state, createdAt, finishedAt } ] }` | Newest first, drafts left out. |
| `GET /v1/errands/:id` | | `200 { id, title, words, brief, language, state, createdAt, approvedAt, startedAt, finishedAt, searches, fetches, result?, resultDigest?, failure? }` | `result` only when `done`; `failure` is a code (below). After `ack`, only id, state and times are left. |
| `POST /v1/errands/:id/cancel` | | `204` | A queued errand never starts; a running one stops at its next step (Cancel is also checked every 15 s during a request) and ends `cancelled`. Cancelling a draft deletes it. `409 not_cancellable` for one that already finished. |
| `POST /v1/errands/:id/ack` | `{ resultDigest }` | `200 { deletions: [ { what, reason, deletedAt } ] }` | The app saved the result on the iPhone. The server deletes words, brief, title and result and keeps the id, state, times and look-up counts. `409 no_result` / `result_mismatch`. |
| `DELETE /v1/errands/:id` | | `204` | Deletes the row. |

States: `draft` → `queued` → `running` → `done` | `failed` | `cancelled`.

Failure codes: `interrupted` (the worker stopped mid-run; it is **not** re-run by itself, the user hands it over again), `time_limit`, `refused` (the model declined), `provider_error`, `unreadable_result` (the result didn't fit the schema).

## The result card (`ErrandResult`)

```json
{
  "answer": "Najlepszy układ: wylot 12.11, powrót 19.11 …",
  "sections": [
    { "heading": "Loty", "kind": "options",
      "items": [ { "title": "Ryanair WAW–CIA", "detail": "bezpośredni, 2 h 20 min", "when": "12.11–19.11", "price": "389 zł / os.", "url": "https://…", "site": "ryanair.com" } ] }
  ],
  "recommendation": "…",
  "budget": { "asked": "hotele do 2000 zł", "within": "yes" },
  "next": ["Zawęzić do Trastevere?", "Sprawdzić inny tydzień?"],
  "sources": [ { "title": "…", "url": "https://…", "site": "…" } ],
  "checkedAt": "2026-10-21T09:12:00Z"
}
```

- `kind` is one of `options` (a comparison table), `brief` (short research), `checklist` (steps) or `places`.
- At most 6 sections, 8 items each, 3 `next` lines, 20 sources. `answer` ≤ 600 characters.
- `budget.within` is `yes`, `no` or `unknown`; `budget` is left out when the user gave none.

**Rules the code enforces (not only the prompt):**
- **Every link comes from the run.** A `url` in an item or in `sources` is kept only if a web search result or a fetched page in this run had exactly that URL. Others are removed (DOD-02).
- **No price without its page.** An item whose `url` was removed, or that never had one, loses its `price`, and its detail says the price wasn't confirmed.
- **The user's words are kept as given**, never rewritten. The brief is labelled as Doddy's.
- **Web content is data.** The research prompt says so, and nothing the run reads can start another errand, a message or a booking: the runner has no tool except search and fetch.

## The runner

- **Model:** `claude-opus-5-5` (env `ERRANDS_MODEL`), adaptive thinking, effort `high` (env `ERRANDS_EFFORT`), streamed, with prompt caching (each resumed turn resends the whole history). Server-side fallbacks are on (`fallbacks: "default"`), so a safety decline on one model is retried on another inside the same call. The card call uses the same model at effort `medium`, no tools, and may run up to 4 minutes past the time limit.
- **Tools:** `web_search_20260209` and `web_fetch_20260209`, **with no `max_uses`** (owner: no cap). `pause_turn` is resumed until the model ends its turn.
- **What stops a run:** the model finishing; the user's Cancel; the time limit (env `ERRAND_TIME_LIMIT_MINUTES`, default 30), so a stuck run ends as `failed: time_limit` instead of running forever; a refusal or provider error.
- **Limits that are not look-up caps:** at most 5 open errands per account (env `ERRANDS_MAX_OPEN`); 30 creates and 30 approvals an hour per device; up to 3 runs at once per server process; the switch `ERRANDS_ENABLED`, **off (`0`) by default**. There is no daily spend cap (owner decision open).
- **Costs** are logged per errand (input and output tokens, searches, fetches), never the words.

## Where it runs

`server/messaging` (Render): it already has the accounts the app uses, Postgres with encrypted text, the APNs sender, the outbox and a worker loop with `FOR UPDATE SKIP LOCKED` claims. **Caveat:** the live service is a free Render web service with the worker inside it (`RUN_WORKER_IN_WEB=1`), and a free service sleeps after about 15 minutes without requests, which stops the worker. A run that starts while the app is open usually finishes; for errands to be dependable the service needs a paid instance or the separate `doddy-messaging-worker` (`render.yaml`). The searches don't go through `backend/` (Monid): the runner uses Anthropic's own web search and web fetch tools, so it can also open pages.

## Privacy

- **Sent to Anthropic:** the user's words, the brief, the language and today's date (not the title), plus whatever the run searches and reads; search words made from the task go on to Anthropic's search provider. Nothing from notes, lists, the profile or earlier conversations.
- **On the server:** the words, brief, title and language as one encrypted blob, and the result, encrypted with the existing text key (`MEMORY_ENCRYPTION_KEY`), until the app acknowledges the result. The approved digest covers exactly the stored blob and the worker checks it again before running. A draft that's never approved is deleted after 10 minutes; any finished errand's content is deleted after 30 days. Receipts go in `errand_deletions`. Without the key the server refuses errands (`503 errands_disabled`).
- **On the iPhone:** the result, in Doddy's database (`v15_errands`), with the user's words. Deleting it in the app deletes it there; the server copy is already gone after `ack`.
- **The push** carries no words from the errand, not even its title (owner decision open: the title on the Lock Screen would be more useful and less private).

## Failure paths

| What fails | What the user gets | What's kept |
|---|---|---|
| The server has no Anthropic key, no text key, or errands are off | Doddy says it can't work on it in the background yet and offers to look it up now, asking before each search | Nothing |
| No network when handing over | Doddy says it couldn't hand it over; nothing started | Nothing |
| The approve request's answer never comes back | `unknown`: Doddy says it may have started and to check Sprawy in the app; it doesn't approve again | The draft on the server, or the queued errand |
| The run hits the time limit, a refusal or a provider error | A push with no words ("Nie udało się dokończyć sprawy." / "Doddy couldn't finish a task.") and the card says why | The words and brief, until deleted |
| The worker restarts mid-run | `failed: interrupted`, never re-run automatically | Same |
| Notifications are off | The result waits in Sprawy | Same |
| The result can't be saved on the iPhone | The card says so; the server keeps its copy (no `ack`) | The server copy |

## Built so far (21 Oct 2026)

**Server (`server/messaging`):** migration `009_errands.sql` (`errands`, `errand_deletions`), `src/errands/` (schema, digest, service, the research loop and Claude client, the card rules, the worker), `src/routes/errands.ts`, an `errandLoop` in `workerLoop.ts`, config and env. Tests: `npm test` with a local Postgres 16 (`TEST_DATABASE_URL`): **153 pass, 0 fail, 0 skipped**, of which 20 offline errand unit tests and 14 errand DB/API tests (create → approve → research with a fake researcher → result → ack with receipts; digest, expiry and owner checks; open limit; disabled; cancel; interrupted; account deletion). Without the database, 78 pass and six DB suites skip. The real SDK was pointed at a local stand-in once to check the request shape. **Never called the real Anthropic API, APNs or a real Render database.**

**Shared core (`Packages/DoddyCore`):** `Errand.swift` (types, the ask card, `ErrandsPrompt`, `ErrandResultText`, the tool replies), `ErrandsClient.swift`, `SQLiteErrandRepository` with migration `v15_errands`, the two voice tools in `VoiceTools.swift`, `AskFirst`, the car, Pause all, the activity log, the capability catalog and a "What leaves this iPhone" row. The app recomputes the server's digest and refuses to approve if it differs. `swift test` on Linux (Swift 6.1.2): **1,312 tests, 0 failures** (45 new).

**iPhone (`DoddyApp`):** `Features/Errands/ErrandsModel.swift` (hand-over, refresh that saves a result before acknowledging it, cancel, delete server-first, the agent's texts, asking for notifications at the first hand-over), `ErrandsView.swift` (Tasks list and result card), Home's ••• → Tasks and its "Done: …" card, the refresh when Doddy comes to the front, the two tools and `{{errands}}` in `VoiceSessionController`, the store in `AppEnvironment` and Delete everything, Polish lines. `ErrandsModel.swift` was type-checked on Linux in Swift 6 mode against the real DoddyCore with stand-ins for the push and server-config types. **The SwiftUI views and the controller changes were never compiled: BLOCKED / NOT RUN (no Xcode).**

**Voice spec:** `hand_over_errand` and `check_errands` in `tools.json` (`not_synced`), `{{errands}}` in `session.json` (placeholder `none`), the Task wording in `instructions.md`. `voice_agent_spec.py check` passes (84 tools). **Not on the live ElevenLabs agent:** it gets them with an app build that answers them.

## To turn it on

1. A Mac build of this branch, then a phone build (the Swift above has to compile first).
2. On the messaging server: `ANTHROPIC_API_KEY` and `MEMORY_ENCRYPTION_KEY` set (both already exist for news and calls), then `ERRANDS_ENABLED=1`. The migration runs at start-up.
3. A paid Render instance or the separate worker (see "Where it runs").
4. The live ElevenLabs agent: create and attach the two tools, add the `errands` placeholder, switch the live Task lines to handing over (owner's yes on the exact text first).
5. The first real run: check `fallbacks: "default"` with its beta header, `cache_control` next to the server tools, the web fetch result shape, and the look-up counts against Anthropic's usage.
