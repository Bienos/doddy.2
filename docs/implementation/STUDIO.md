# Studio: research it, make it, keep it (S0, ADR-584)

> All measured results (runs, costs, showcase files, tests) are collected in `STUDIO_TEST_RESULTS.md`.

**Status, 22 Oct 2026: S0 is built on `claude/new-session-ayk8tq` (ADR-584). Off by default (`STUDIO_ENABLED=0`).** On 22 Oct one real job ran against the Anthropic API as far as the write step (see "First real run"); nothing here has run against APNs, Render or a device, and the make step has never run for real; the server ran against a local Postgres 16 with a fake model API. The SwiftUI views and the voice controller change are not compiled (no Xcode here). The audit that came first is `STUDIO_AUDIT.md`. The owner chose S0 on 22 Oct ("S0: Studio") after the audit; the open decisions are listed at the end, and where S0 had to pick, the pick is marked **default**.

S0 is one kind: **a research brief and an infographic.** The owner says "research X" (or "make me an infographic about X"); Doddy shows one card; on Allow, the messaging server's worker plans, researches the web, writes the content, has Claude render it with Doddy's own scripts in Anthropic's container, checks the files in code, stores them, and sends a push with no words. The item appears in Home ••• → Studio, where it opens, shares and deletes.

## The job (the contract the app and the server share)

`POST /v1/studio` body, strict (unknown fields refused):

| Field | Type | Rule |
|---|---|---|
| `kind` | string | `"brief"` only in S0 (research brief + infographic) |
| `topic` | string | 1 to 300 characters, kept exactly as given |
| `audience` | string, optional | up to 120 characters |
| `length` | string | `"short"` (about 1 page), `"standard"` (2 to 3 pages), `"long"` (4 to 6 pages) |
| `style` | string | `"plain"` or `"lively"` |
| `language` | string | two lowercase letters (`pl`, `en`, …): the language Doddy writes in |
| `details` | string, optional | up to 1,000 characters: the owner's own words about what they want, kept exactly. Data in every prompt, never instructions |
| `sources` | array, optional | up to 5 `{ "url": "https://…", "title": "…" }` the owner picked (title up to 200, URL up to 2,048, `http(s)` only) |

Optional fields are left out, never `null`. Strings must not be blank.

**The digest** the owner approves: SHA-256 (hex, lowercase) over the canonical JSON of the job: keys sorted at every level, no spaces, strings as `JSON.stringify` writes them, optional fields absent when not given, `sources` in the order given. Same canonical JSON as Errands (`canonicalJson` on the server, `CanonicalJSON` in DoddyCore). The app recomputes it and refuses to approve if it differs.

Reply `201`: `{ "id", "digest", "job": {…exactly as stored…}, "expiresAt" }`. A draft expires after 10 minutes.

## Server API (`server/messaging`, bearer = the account's device token)

| Route | Body | Reply |
|---|---|---|
| `POST /v1/studio` | the job | `201 { id, digest, job, expiresAt }`. Nothing runs |
| `POST /v1/studio/:id/approve` | `{ digest }` | `202 { id, state: "queued" }`. Refusals: `409 digest_mismatch`, `409 not_approvable` (`state`), `409 too_many_open_items`, `409 daily_cap_reached` (`{ capUsd, spentUsd }`), `503 studio_disabled` |
| `GET /v1/studio` | | `200 { items: [ { id, kind, title, state, createdAt, finishedAt, failure?, costUsd } ] }`, newest first, at most 50, drafts left out. `title` is null until the plan step named it |
| `GET /v1/studio/:id` | | `200` the item (below) |
| `GET /v1/studio/:id/files/:name` | | `200` the file's bytes with its content type, `cache-control: private, no-store`. `404` when the item or file isn't there |
| `POST /v1/studio/:id/cancel` | | `204`. A draft is deleted; a queued item never starts; a running one stops at its next step and ends `cancelled` |
| `DELETE /v1/studio/:id` | | `200 { deleted: true, files: <count>, anthropicFiles: { pending: <n> } }` after the row and its files read back as gone. `pending` counts copies at Anthropic whose delete isn't confirmed yet; they move to `studio_orphan_files` and the worker keeps deleting them (also after the account is deleted). The app then says "Deleted from Doddy. Anthropic's copy is still being removed." |

**Item states the app sees:** `queued`, `researching`, `making`, `checking`, `ready`, `needs_look`, `failed`, `cancelled`. (`draft` items are never listed.) On the server a running item has `state = 'running'` and a `stage` (`plan`, `research`, `write`, `make`, `check`, `store`); `researching` covers plan, research and write; `making` is make; `checking` is check and store.

**Failure codes:** `interrupted` (the worker stopped mid-run; never re-run by itself), `time_limit`, `refused`, `provider_error`, `unreadable_result`, `too_little_found` (fewer than 3 usable claims), `cost_limit` (the job passed its own dollar limit).

The item (`GET /v1/studio/:id`):

```json
{
  "id": "…", "kind": "brief", "job": { "…": "as approved" }, "digest": "…",
  "title": "Heat pumps in Polish homes", "state": "ready",
  "createdAt": "…", "approvedAt": "…", "startedAt": "…", "finishedAt": "…",
  "summary": { "answer": "…", "confidence": "medium", "altText": "…the infographic's, for VoiceOver…" },
  "sources": [ { "id": "s1", "url": "https://…", "title": "…", "fetchedAt": "2026-10-22T10:01:02Z" } ],
  "files": [ { "name": "brief.pdf", "role": "brief", "mime": "application/pdf", "bytes": 81234, "sha256": "…" } ],
  "checks": [ { "name": "claims_map_to_pack", "passed": true, "detail": "" } ],
  "cost": { "usd": 1.84, "inputTokens": 0, "outputTokens": 0, "cacheReadTokens": 0, "cacheWriteTokens": 0, "searches": 12, "fetches": 9, "containerSeconds": 140 },
  "model": "haiku-5-5+sonnet-5-5", "skills": [ { "id": "skill_…", "version": "…" } ],
  "failure": "…"
}
```

Content fields (`job`, `title`, `summary`, `sources`) are stored encrypted with `MEMORY_ENCRYPTION_KEY`, like Errands. Files are stored encrypted in the same database (table `studio_files`), **default** for S0 because no storage provider has been chosen yet (audit decision 4); the website milestone (S2) moves them to object storage.

## The files

| Name | Role | What | Check in code |
|---|---|---|---|
| `brief.pdf` | `brief` | A4 PDF: title, the answer first, a section per sub-question with footnoted claims, where sources disagree, confidence and gaps, sources with the date each was fetched | Starts `%PDF-`; at most 15 MB; at least 1 page; no `/JavaScript`, `/JS`, `/Launch` or `/EmbeddedFile` |
| `infographic.svg` | `infographic` | 1080×1350, the headline fact, 3 to 7 facts, one chart, a source line; alt text in `<title>` and `<desc>` | Parses as SVG; no `<script>`, no `<image>`, no `<foreignObject>`, no external `href`; the headline and every fact present; text fills from the brand palette and never orange `#FF6A00`; every text at least 22 px; text contrast at least 4.5:1 on the background |
| `infographic.png` | `infographic_png` | the same at 1080×1350 | PNG signature; IHDR exactly 1080×1350 |
| `infographic-a4.png` | `infographic_print` | the same on A4 at 150 dpi (1240×1754) | PNG signature; IHDR exactly 1240×1754 |

Any other file Claude saves is not kept (it is still deleted at Anthropic).

## The content (what the write step returns, and what the renderers read)

`content.json`, validated by the server before anything is rendered:

```json
{
  "title": "≤ 90 chars",
  "answer": "≤ 500 chars: the answer first, in plain words",
  "sections": [
    { "heading": "≤ 90 chars (one per sub-question)", "points": [ { "text": "≤ 400 chars", "claims": ["c1", "c4"] } ] }
  ],
  "disagreements": [ { "text": "≤ 400 chars", "claims": ["c2", "c5"] } ],
  "confidence": "high | medium | low",
  "gaps": [ "≤ 200 chars" ],
  "infographic": {
    "headline": { "text": "≤ 90 chars", "claims": ["c1"] },
    "facts": [ { "text": "≤ 110 chars", "claims": ["c3"] } ],
    "numbered": false,
    "chart": { "kind": "bar | column | line | donut", "title": "≤ 70 chars", "unit": "≤ 20 chars", "data": [ { "label": "≤ 24 chars", "value": 12.5 } ], "claims": ["c3"] },
    "sourceLine": "≤ 160 chars",
    "altText": "≤ 400 chars"
  },
  "language": "pl",
  "sources": [ { "id": "s1", "title": "…", "url": "https://…", "fetchedAt": "2026-10-22T10:01:02Z" } ],
  "claims": [ { "id": "c1", "text": "…", "quote": "…", "source": "s1" } ]
}
```

Limits: 2 to 5 sections, 1 to 6 points each; 0 to 4 disagreements; 0 to 5 gaps; 3 to 7 facts; chart data 2 to 8 rows, finite numbers, donut values not negative. Every `claims` list names claims that exist; every claim names a source that exists; every source was seen in this run (search result, fetched page or citation). `numbered` is true only when the facts are a sequence. The server adds `language`, `sources` and `claims` from the research pack, so the renderers get one self-contained file.

## Brand (from `DoddyDesignTokens` and Brand Guidelines V2.2)

Paper `#FFF7E9` background; ink `#171715` text; orange `#FF6A00` for decoration only (bars, rules, the headline's underline), **never text**; accent text `#A64B00`; secondary text `#5E584F`; night `#16171C`. Chart series: orange `#FF6A00`, ink `#171715`, green `#326746`, muted `#B9AE9D`. Type: the container's own sans-serif (DejaVu Sans) until the owner approves the brand fonts (audit decision 3); no font file is shipped. No character art in S0.

## The pipeline (worker, `server/messaging/src/studio/`)

1. **Plan** (Haiku 5.5, effort medium, structured output, no tools): title, 3 to 5 sub-questions, the outline, the audience.
2. **Research** (Sonnet 5.5, effort high, `web_search_20260209` and `web_fetch_20260209` with `max_uses` and `blocked_domains`, task budget, streamed, `pause_turn` resumed, server-side fallbacks): notes with the URL behind each fact. Then a **pack** call (Haiku 5.5, structured output, effort medium, no tools): claims with a quote and the source URL. Code drops claims whose URL the run never saw; fewer than 3 left is `too_little_found`.
3. **Write** (Sonnet 5.5, structured output, effort medium, no tools): `content.json` as above; code validates every rule.
4. **Make** (code execution `code_execution_20250825` with the custom skills `doddy-brand`, `doddy-docs`, `doddy-infographic`; Haiku 5.5, effort medium; `pause_turn` resumed with the same container): Claude writes `content.json` and runs the skills' scripts, which save the four files at the top of `$OUTPUT_DIR`. Files are downloaded with the Files API, then deleted there; each delete is read back.
5. **Check** (code only): the table above. A failure goes back to Make once, with the failed checks listed. A second failure stores the item as `needs_look` with its checks, never as ready.
6. **Store and tell**: files encrypted and stored, read back and compared by SHA-256; then the push ("Gotowe. Twój materiał czeka w Studiu." / "Ready. Your Studio item is waiting in the app."), no words from the item.

**Data, not instructions:** the job's `topic`, `details` and `sources`, everything the web returns, and the pack are passed as JSON data in every prompt, and every system prompt says so.

**Money:** each job has a token budget on the research call (advisory to the model), a dollar limit per job (`STUDIO_JOB_LIMIT_USD`, **default** $2, checked after every request), and a daily cap per account (`STUDIO_DAILY_CAP_USD`, **default** $3, checked at approve against today's spend plus a $1 reserve per open job). Each item records its cost from the API's usage, **each call priced with its own step's model** (`src/studio/models.ts`: Opus 5.5 $4 / $20, Sonnet 5.5 $2 / $10, Haiku 5.5 $0.10 / $0.50 per million tokens, Haiku $0.50 / $2.50 beyond 100K prompt tokens; cache reads at the model's own fraction; searches at $10 per 1,000; container time is recorded but counted as $0, inside the free hours). An unknown model is counted at the dearest price.

## Settings (`server/messaging`)

| Env | Default | What |
|---|---|---|
| `STUDIO_ENABLED` | `0` | `1` turns Studio on (also needs `ANTHROPIC_API_KEY`, `MEMORY_ENCRYPTION_KEY` and `STUDIO_SKILLS`) |
| `STUDIO_MODEL_PLAN`, `_RESEARCH`, `_PACK`, `_WRITE`, `_MAKE` | Haiku 5.5, Sonnet 5.5, Haiku 5.5, Sonnet 5.5, Haiku 5.5 | The model of each step (owner, 22 Oct: the all-Opus plan cost too much). `STUDIO_MODEL`, when set, is the starting point for every step; a step variable then overrides it. `claude-opus-5-5` everywhere is the old, dearest mix |
| `STUDIO_SKILLS` | empty | Comma-separated custom skill IDs, each optionally `@version` (from `scripts/studio_skills.sh upload`). Empty: not set up |
| `STUDIO_MAX_SEARCHES`, `STUDIO_MAX_FETCHES` | 15, 15 | `max_uses` per job |
| `STUDIO_BLOCKED_DOMAINS` | empty | Comma-separated hostnames for `blocked_domains` (owner decision 10) |
| `STUDIO_TASK_BUDGET_TOKENS` | 150000 | The research call's task budget (minimum 20,000) |
| `STUDIO_JOB_LIMIT_USD` | 4 | |
| `STUDIO_DAILY_CAP_USD` | 5 | Per account, per UTC day |
| `STUDIO_TIME_LIMIT_MINUTES` | 20 | |
| `STUDIO_MAX_OPEN` | 3 | Queued or running per account |

## The app

- **Voice:** `make_something` (`kind`, `topic`, optional `audience`, `length`, `style`, `details`, `language`; `language` defaults to `pl`, as `hand_over_errand` does). A read under ASK-01 (it changes nothing outside Doddy): one card, a spoken yes or a tap. Card: **Make this with Doddy?** / Research "<topic>" on the web and make a research brief (PDF) and an infographic. / <details, if any> / Your topic goes to Anthropic (Claude), which searches the web and makes the files. Anthropic keeps this work under its normal retention: code execution isn't zero-retention. / It takes a few minutes. Nothing is published or sent anywhere. / **Allow** · **Not now**. Allow creates the job, recomputes the digest, approves, and the agent hears `started: …` ("On it, I'll tell you when it's ready"). Never "done".
- **Studio screen:** Home ••• → Studio (next to Tasks; main has no Recordings entry yet). Newest first; each row shows the title (or the topic while it has none), the state and the cost. An item opens with the brief (Quick Look), the infographic (the PNG), its sources with dates, Share (the files), and Delete. Delete calls the server, then reads the list back; it says "Deleted" only when the item is gone.
- **DoddyCore** (`Studio.swift`, `StudioClient.swift`): the job and its validation, the canonical digest (pinned by the same two test vectors the server's tests use), the item and its states, the card text, the tool replies, the delete rule. Linux tests. A downloaded file is used only if its size and SHA-256 match what the server listed.
- **No copy on the iPhone in S0:** the server holds the items; the app keeps only each job's topic (UserDefaults, until the server has a title) and opened files in Caches. Delete everything clears those and says Studio items stay on the server until deleted in Studio (or with the account).

## ASK-01 (ADR-584)

A second exception next to Errands: the yes on a `make_something` card covers that one job's web searches and page reads (capped by `max_uses`) and the making of its files in Anthropic's container, and nothing else. The worker's research request has only `web_search` and `web_fetch`; the make request has only code execution with Doddy's skills. Neither can book, buy, send, publish or start another job. Enforced in `AskFirst.swift`, `askFirst.ts` (documented: Studio doesn't go through the backend), `check_forbidden_capabilities.sh` (the worker's tool lists are pinned) and `voice_agent_spec.py`.

## What S0 does differently from the brief, and why

- **No `doddy-research` skill.** Research requests carry only web search and fetch, no container, so a skill can't load there; the research rules are the server's versioned prompt (`PROMPT_VERSION` in `src/studio/model.ts`) and the pack schema is code.
- **Cheaper models per step** (owner, 22 Oct: "a lot of money for that"): Haiku 5.5 (built for classification, extraction and routing) plans, extracts claims and runs the fixed render recipe; Sonnet 5.5 researches and writes. Research stays off Haiku because dynamic-filtering web search isn't confirmed for it. Whether the cheap mix is good enough is what the comparison runs decide (`studio-live-run.mjs --mix cheap|sonnet|opus`); the estimate is about $0.5 to $1 per brief against about $1.5 to $3 on Opus, but it is an estimate until a real run. A safety refusal can fall back on another model only where Anthropic offers it (Opus 5.5, Sonnet 5.5, Fable 5.1), so a Haiku step that is refused ends the job as `refused`.
- **No server-side fallbacks on the make step.** Whether a fallback model runs Doddy's custom skills isn't documented; a refusal there ends the job as `refused`.
- **Files in the messaging database, not object storage** (decision 4 is open); **no website, no publishing** (S2).
- **The item screen speaks the infographic's alt text** (`summary.altText`), which the brief didn't list.

## Tests

Run on 22 Oct 2026 in a Linux container (Node 22.22.0, Swift 6.1.2, Postgres 16, Python 3 with reportlab and matplotlib):

| Command | Result |
|---|---|
| `TEST_DATABASE_URL=… npm test --prefix server/messaging` | **188 pass, 0 fail, 0 skipped** (35 new: 23 offline in `studioUnits.test.ts` including the per-step models, per-call pricing and the live-run recorder, 10 through the HTTP API against Postgres in `studio.test.ts`, 2 in `config.test.ts`). Re-run on 22 Oct after the cheaper-models change. Mutation checks: removing the daily cap, making every item ready, keeping unseen URLs, allowing `<script>` or allowing orange text each fail tests; removing the owner check on file downloads is still caught, because the file's encryption is bound to its owner's account |
| `scripts/check_studio_crosscheck.sh` | PASS: the server's 14 checks accept the files the real renderers made from both samples |
| `scripts/studio_skills.sh check` | PASS: 3 skills (frontmatter, sizes, no font or image files), 4 render variants (Polish bar, English column, line with numbered facts, donut), a broken SVG caught |
| `swift test --package-path Packages/DoddyCore` (Linux flags) | **1,395 tests, 0 failures** (24 new in `StudioTests`, plus updated `ActivityTextTests` and `DataFlowTests`); the shared digest vectors match the server's |
| `scripts/typecheck_app_logic.sh` | PASS: 26 app files, `StudioModel.swift` included |
| `python3 -I scripts/voice_agent_spec.py check` | PASS: 95 tools, `make_something` included (its generic rules cover it; no change was needed) |
| `scripts/check_forbidden_capabilities.sh` | PASS; mutation-checked (see the evidence log) |
| `python3 -I tools/build_strings_catalog.py --check` | PASS: Polish 1,700 of 1,778 |
| `TEST_DATABASE_URL=… scripts/ci.sh --core-only` | **RESULT: PASS for core-only scope**: all 31 steps PASS, including both new Studio steps; the messaging server's database suites ran (not skipped). iOS app NOT verified (`--core-only`) |

**Not run:** the real Anthropic API (no key in this container; the skills were never uploaded), so no real job, no measured cost and no check of the request shapes against the live API; the SwiftUI views and the controller, `VoiceView`, `HomeView`, `RootView` and `SettingsView` changes (no Xcode; the hosted Mac build is their first compile); APNs; Render; a device; the live ElevenLabs agent.

## Skills uploaded (22 Oct 2026, real API)

`scripts/studio_skills.sh upload` worked first time against `POST /v1/skills` (the script's request format matches the current skills guide: `files[]` parts with the folder as the path, `anthropic-version: 2023-06-01`, no beta header). IDs and versions are not secrets:

| Skill | `skill_id` | Version |
|---|---|---|
| doddy-brand | `skill_01A75ob2c7ffXrWtzZUCnRVt` | `skver_01KH2yf9VsgJ5JBym9Y4xMDo` |
| doddy-docs | `skill_01KoVjXFPWSeVWM2pFisSj8R` | `skver_01W3vcsJXorqj85MTNKJSBbX` |
| doddy-infographic | `skill_01TQ6rfczzvXqeCrCTkv2Uak` | `skver_01MjEQ7nMjSEvLU8s7CUjmap` |

`server/messaging/scripts/studio-live-run.mjs <pl|en|short>` is the driver for the first real runs (key and `STUDIO_SKILLS` from the environment only). The first real job is described in "First real run" below.

## First real run (22 Oct 2026, one job, partly)

The owner lowered the limits for this run: US$5 for the whole task, US$2 per job, one job only, 8 searches and 8 fetches. One job ran: Polish, "Pompy ciepła w Polsce: ile kosztują i czy się opłacają?", length `short`, driver `server/messaging/scripts/studio-live-run.mjs`, `baseURL` set to `https://api.anthropic.com`. Topics (b) and (c) and any rerun were **not run**. This run used Opus 5.5 for every step (before the per-step model mix existed), so the mix is not measured. Spent: **US$1.42** (computed by the code and, independently, from the per-call usage: both 1.4153).

**Result: the job failed as `unreadable_result` at the write step. No file was made, so the make step (code execution with the custom skills, `pause_turn` with a container, `file_id`s, file download and delete) has still never run against the real API.**

| Step | Time | Tokens (fresh in / out / cache read / cache write) | Searches, fetches | Cost |
|---|---|---|---|---|
| Plan | 7 s | 782 / 530 / 0 / 0 | | $0.014 |
| Research (one request, `end_turn`, no `pause_turn`) | 188 s | 576 / 13,443 / 789,797 / 82,791 | 8, 8 | $0.92 |
| Pack | 63 s | 14,025 / 9,172 | | $0.24 |
| Write, attempt 1 | 34 s | 11,578 / 3,590 | | $0.12 |
| Write, retry | 29 s | 11,601 / 3,721 | | $0.12 |
| Total | 321 s wall clock | 38,562 / 30,456 / 789,797 / 82,791 | 8, 8 | **$1.42** |

**What the real API confirmed:** `beta.messages.parse` with `fallbacks: "default"` and `server-side-fallback-2026-07-01` was accepted (plan, pack, write); `beta.messages.stream` with top-level `cache_control` next to the web tools, `output_config.task_budget` with `task-budgets-2026-03-13`, `web_search_20260209` and `web_fetch_20260209` with `max_uses` 8 each was accepted (no `blocked_domains` in this run, so that combination is **not** confirmed); the usage fields are as the code reads them (`cache_creation_input_tokens`, `cache_read_input_tokens`, `server_tool_use.web_search_requests` and `web_fetch_requests`: 8 and 8, matching the `max_uses`). The research result also contained `code_execution_tool_result` blocks (the `_20260209` tools run code to filter results); the code counted nothing for them and the request had no code-execution tool of its own, so the code-execution rule in ASK-01 still holds, but the Studio guard text scan doesn't describe this. Skills upload: worked (above).

**What the output looked like:** the plan was sensible (title, 5 sub-questions, outline, audience). The research found 71 URLs; the pack kept all 38 offered claims from 27 sources, with figures such as air-source 35 to 55 thousand zł and ground-source 60 to 100 thousand zł for a 150 m² house. I did not open the pages myself, so neither the figures nor the quotes are checked against the live pages. The written content was good in substance: the answer, six facts, a bar chart whose five values (4,256, 5,426, 6,279, 7,375, 12,841 zł a year) match claim c10 from GLOBENERGIA. Mistakes: (1) **both write attempts broke a length limit**: attempt 1 had a chart title of 77 characters (limit 70), the retry fixed that but had a chart label of 26 characters (limit 24), so the job ended with nothing rendered; the retry got only the list of problems, not the previous text. (2) `short` ("about 1 page") gave 5 sub-questions and 6 facts, which would probably run past one page; not yet seen rendered. (3) One chart label ("Węgiel (kocioł Ekoprojekt)") is a brand-like name next to a generic one; fine.

**Fix made (tested with the fake, not with a paid run):** the write step now has up to 3 attempts and each retry carries the previous attempt as well as the problems; the write prompt states the main length limits and says to count characters (`PROMPT_VERSION` `studio-s0-2`). Test: `studioUnits.test.ts` "content that breaks the rules is sent back with its last attempt and the problems; three times is unreadable_result". **Whether this makes real write steps pass is unproven.**


### Runs 2 to 4 (same day, mix `cheap`: Haiku 5.5 plans, extracts claims and renders; Sonnet 5.5 researches and writes)

The owner then asked for a real report and deck and the cost by model. Three more runs of the same Polish job (8 searches and 8 fetches each), US$1.21 in all; total for the task **US$2.64**.

| Run | Result | Cost | Why |
|---|---|---|---|
| 2 (prompt `studio-s0-2`) | failed `too_little_found` | $0.35 | Sonnet's research notes were only 6,290 characters with no figures or quotes; Haiku's pack found 2 claims and said so (it did not invent any) |
| 3 (prompt `studio-s0-3`: detailed notes with quotes asked for) | failed `too_little_found` | $0.36 | The research request ended with `stop_reason: "tool_use"` and no tool call of ours (last block a thinking block); the code took it as the end, with a 30-character note. **Real bug.** |
| 4 (`tool_use` without our own tool call is resumed like `pause_turn`, `resumable()` in `pipeline.ts`, tested with the fake) | **made, `ready`, all 14 checks passed** | **$0.51** | 280 s |

**Run 4 by step:** plan Haiku $0.0004; research Sonnet $0.37 (+ $0.08 for 8 searches); pack Haiku $0.0067 (32 claims); write Sonnet $0.044; make Haiku $0.010. So Haiku cost about $0.02 in all, Sonnet about $0.41, searches $0.08; the code's cost and the cost implied by the per-call usage agree ($0.5076). Tokens: 27,700 fresh in, 46,352 out, 237,755 cache read, 82,896 cache write; container 43 s (not billed here). The same job with every step on Opus 5.5 (run 1, before the make step could run) was $1.42 up to write alone, so the cheap mix is about a third of the Opus price for a finished job.

### Runs 5 and 6: Haiku alone and Sonnet alone (same job, `--mix haiku` and `--mix sonnet`)

The owner asked to see each model by itself. Both made a brief and an infographic, `ready`, all 14 checks passed, Anthropic's files deleted and read back as gone (0 left). Task total after these: about **US$3.79**.

| | Haiku 5.5 only | Sonnet 5.5 only | (cheap mix, run 4) |
|---|---|---|---|
| Cost | **$0.26** | **$0.88** | $0.51 |
| By step (plan / research / pack / write / make) | 0.0004 / 0.112 / 0.008 / 0.011 / 0.061, + searches $0.07 | 0.007 / 0.432 / 0.099 / 0.100 / 0.167, + searches $0.08 | 0.0004 / 0.367 / 0.007 / 0.044 / 0.010, + $0.08 |
| Time | 265 s | 353 s | 280 s |
| Searches / fetches | 7 / **0** | 8 / 8 | 8 / 8 |
| Claims in the pack | 39 | 35 | 32 |

What the outputs look like (looked at both infographics and first pages): Haiku never opened a page (0 fetches), so its claims rest on search snippets; its headline gives one specific case ("pompa powietrze-woda 10 kW z montażem: 26–42 tys. zł") that is clear, but its ground-source price (80 to 120 thousand zł) is above every other run's (60 to 100), and its chart has only two bars (pump 3,210 against gas 4,310 zł a year), from one source. Sonnet read 8 pages, gave a headline with both pump types, a five-bar chart of yearly heating cost, and hedged ("dane o zwrocie pochodzą od sprzedawcy") where the source is a seller. The same Haiku make step rendered fine in all runs it was used. I did not check either run's figures against the live pages.

### Runs 7 and 8: Opus alone and Fable alone (`--mix opus`, `--mix fable`, job limit US$4)

The owner approved up to US$10 for the whole task for these two. Same Polish job, 8 searches and 8 fetches. Task total after these: about **US$10.18** (the Fable job overran the budget by the step that crossed the limit).

| | Haiku only | Sonnet only | Opus 5.5 only | Fable 5.1 only |
|---|---|---|---|---|
| Result | made, `ready` | made, `ready` | made, `ready` | **failed `cost_limit`** |
| Cost | $0.26 | $0.88 | $2.02 | $4.38 (limit $4 crossed after the make call) |
| Plan / research / pack / write / make | 0.0004 / 0.11 / 0.008 / 0.011 / 0.061 | 0.007 / 0.43 / 0.099 / 0.10 / 0.17 | 0.014 / 1.03 / 0.207 / 0.265 / 0.424 | 0.032 / 1.90 / 0.618 / 0.735 / 1.016 |
| Time | 265 s | 353 s | 476 s | 505 s |
| Pages opened / distinct sources in the pack | 0 / 28 | 8 / 18 | 8 / 21 | 8 / **5** |
| Claims | 39 | 35 | 35 | 40 |

Fable 5.1 (list $10 / $50 per million tokens, cache reads $0.25) cost about 2.2 times Opus and 5 times Sonnet for this job; its make step, a Fable run of the render recipe, cost $1.02 against Haiku's $0.06. Its research, pack and write steps all worked (including `fallbacks` and `task_budget` on a Fable request). The job limit is checked after each call, so the make call (made four files, all later deleted and read back as gone, 0 left at Anthropic) pushed it over $4 and nothing was downloaded. To compare content I rendered Fable's written content locally with the same skill scripts (no API); that is not what Studio would have shipped, but the server's 14 checks pass on it. Nothing in this run shows a Fable make step's files.

What the outputs look like: all four briefs are readable and on brand. Opus: headline 38–65 tys. zł, a four-bar yearly-cost chart (GLOBENERGIA model), a good "old uninsulated house may not pay back" point; confidence medium, 5 sections, 4 gaps, 4 disagreements. Fable: the richest brief (a grant ladder 22,280 / 38,990 / 55,700 zł, gas as a comparison bar, grates vs underfloor +11%, "60% still on a single-rate tariff"), but built from only 5 distinct sources, so it leans hard on a few pages; its title is 77 characters. It also needed a second write attempt, like every other run. Haiku: no page read. Sonnet: the best value, close to Opus for a third of the price. I did not check any run's figures against the live pages.

**What the real API confirmed in run 4:** custom skills as `container.skills` with `{type: "custom", skill_id, version}` plus `code_execution_20250825`, no beta header (accepted; Haiku 5.5 ran the skills' scripts first time, one request, no `pause_turn`); the four files saved at the top of `$OUTPUT_DIR` came back as `file_id`s in `bash_code_execution_tool_result`; `retrieveMetadata` gave the right names, `download` the bytes, `delete` worked and a deleted file then 404s (`fileGone` true for all 4); a Files API listing afterwards showed **0 files at Anthropic** (nothing left over from any run). The server's 14 file checks passed on the real files. `blocked_domains` together with `max_uses` is **still not tried** (no domains blocked in any run).

**What the output looked like** (brief 4 pages, infographic 1080×1350, I looked at both): readable, brand colours, orange only on bars and rules, footnoted points, a "where sources disagree" part and a confidence line. Mistakes and weak points: (1) the infographic headline says "25–40 tys. zł" for an air-source pump, the lowest figure (one pump seller, TS Energy); the brief's own answer says "according to one source" but the headline doesn't, and another run found 35 to 55 thousand; (2) "zwrot ok. 6–10 lat" leaves out that the source says "z dofinansowaniem" (with a grant); (3) the chart is about grants ("Maks. dotacja"), not about what the headline is about, and mixes the Moje Ciepło ceiling with Czyste Powietrze percentages; (4) one fact ("Poniżej −15 °C pompa powietrzna włącza grzałkę") I did not check against its source; (5) I did not open the cited pages, so figures and quotes are not checked against them; (6) the code checks that claims exist and that the pack's source was seen, not that a headline is as careful as its sources.

**The deck:** Studio S0 makes no decks (S1). The owner got a 9-slide deck made locally (python-pptx, no API) from run 4's written content, so it is not a Studio feature and cost nothing.

**Still unproven after run 1 alone** (run 4 above has since covered the make step and the Files API): the make step and everything in it (`container.skills` with `{type: "custom", skill_id, version}`, `pause_turn` with the same container, files at the top of `$OUTPUT_DIR` as `file_id`s, `retrieveMetadata`, `download`, `delete` and the 404 after delete), `blocked_domains` together with `max_uses`, a real rendered brief and infographic, and the checks on real files. No Anthropic-side file was made by this run, so there was nothing to delete (the Files API list was not queried).

## Constitution evidence log (S0)

| Rule | Enforcing code | Tests | Gaps and claims to keep limited |
|---|---|---|---|
| ASK-01 / DOD-07: ask first, exact payload | App: `AskFirst.swift` (`make_something` asks; spoken yes or tap), `StudioJob.digest`; server: `approveItem` refuses any digest but the draft's; worker re-checks the digest before running | `StudioTests` (shared digest vectors, card text), `studio.test.ts` (digest mismatch, expiry), `studioUnits.test.ts` (canonical JSON) | The card isn't compiled in the app yet (no Xcode); the live agent doesn't have the tool |
| ASK-01 exception scope (ADR-584) | `model.ts`: research has only `web_search_20260209`/`web_fetch_20260209` with `max_uses`; make has only `code_execution_20250825` with Doddy's skills; `check_forbidden_capabilities.sh` pins both workers' tool types | `studioUnits.test.ts` "research has only web search and fetch…"; the guard: PASS; mutation checked 22 Oct: code execution added to the Errands worker → FAIL (both rules), a `computer_20251124` tool added to Studio → FAIL; restored → PASS | The guard is a text scan of tool literals, not a runtime check |
| DOD-08: done only when confirmed | Worker stores files, reads each back and compares SHA-256 before `ready` and before the push; the agent hears `started`, never "done" | `studio.test.ts` (ready only after the run; files served match) | No real storage outage was simulated |
| DOD-09: unknown is never success, no blind retry | App: an approve whose answer never came is `unknown` and never re-sent; server: a dead worker's job is `interrupted`, never re-run | `StudioTests` (unknown approval), `studio.test.ts` (reaper) | |
| DOD-02: honest content | Claims kept only if their page was seen in the run (`buildPack`); every point, fact, headline and chart must name pack claims (`contentProblems`); two failed checks → `needs_look` | `studioUnits.test.ts` (unseen URL dropped, unknown claim refused, needs_look) | Code can't check that a sentence says no more than its claims; wording faithfulness is the model's |
| Data, not instructions | Every prompt (`model.ts`) carries the data rule; the job, web content and pack go in as JSON | Prompt text only | A prompt can't guarantee it; the tool lists are what limit harm |
| DOD-11: observable privacy | "What leaves this iPhone" row and the card name Anthropic and say code execution isn't zero-retention; job, result and files encrypted at rest; push has no words; logs carry ids and counts | `DataFlowTests`, `studio.test.ts` (ciphertext, push text, logs without words) | Web research with dynamic filtering isn't zero-retention either (also true of Errands); legal review still open |
| Delete is real | `deleteItem` reads back that the item and files are gone; Anthropic copies tracked until a delete reads back as gone, also after the account goes | `studio.test.ts` (delete, orphans, account deletion) | Copies at Anthropic exist for minutes during a run |
| No invented character art | No image under `studio-skills/` (allow list empty, checked); the make prompt and skills forbid drawing Doddy; SVG check refuses `<image>` | `studio_skills.sh check`, `studioUnits.test.ts` | |

**Not claimed:** that Studio works end to end (no real API run), that the app half compiles, that costs are what the estimate says, or that the output is accurate beyond the checks above.

## Open owner decisions (from the audit)

Cloud AI and the card wording (1), Render paid plan (2), brand fonts (3), storage and the website (4), the daily cap (5; default $3, $2 a job), the blocklist and `max_uses` (10; defaults empty and 15/15).
