# Studio: research it, make it, keep it (S0, ADR-584)

**Status, 22 Oct 2026: S0 is built on `claude/new-session-ayk8tq` (ADR-584). Off by default (`STUDIO_ENABLED=0`).** Nothing here has run against the real Anthropic API, APNs, Render or a device; the server ran against a local Postgres 16 with a fake model API. The SwiftUI views and the voice controller change are not compiled (no Xcode here). The audit that came first is `STUDIO_AUDIT.md`. The owner chose S0 on 22 Oct ("S0: Studio") after the audit; the open decisions are listed at the end, and where S0 had to pick, the pick is marked **default**.

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
  "model": "claude-opus-5-5", "skills": [ { "id": "skill_…", "version": "…" } ],
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

1. **Plan** (Opus 5.5, effort high, structured output, no tools): title, 3 to 5 sub-questions, the outline, the audience.
2. **Research** (Opus 5.5, effort high, `web_search_20260209` and `web_fetch_20260209` with `max_uses` and `blocked_domains`, task budget, streamed, `pause_turn` resumed, server-side fallbacks): notes with the URL behind each fact. Then a **pack** call (structured output, effort medium, no tools): claims with a quote and the source URL. Code drops claims whose URL the run never saw; fewer than 3 left is `too_little_found`.
3. **Write** (structured output, effort medium, no tools): `content.json` as above; code validates every rule.
4. **Make** (code execution `code_execution_20250825` with the custom skills `doddy-brand`, `doddy-docs`, `doddy-infographic`; effort medium; `pause_turn` resumed with the same container): Claude writes `content.json` and runs the skills' scripts, which save the four files at the top of `$OUTPUT_DIR`. Files are downloaded with the Files API, then deleted there; each delete is read back.
5. **Check** (code only): the table above. A failure goes back to Make once, with the failed checks listed. A second failure stores the item as `needs_look` with its checks, never as ready.
6. **Store and tell**: files encrypted and stored, read back and compared by SHA-256; then the push ("Gotowe. Twój materiał czeka w Studiu." / "Ready. Your Studio item is waiting in the app."), no words from the item.

**Data, not instructions:** the job's `topic`, `details` and `sources`, everything the web returns, and the pack are passed as JSON data in every prompt, and every system prompt says so.

**Money:** each job has a token budget on the research call (advisory to the model), a dollar limit per job (`STUDIO_JOB_LIMIT_USD`, **default** $4, checked between steps), and a daily cap per account (`STUDIO_DAILY_CAP_USD`, **default** $5, checked at approve against today's spend plus a $2 reserve per open job). Each item records its cost from the API's usage (tokens at Opus 5.5's list price, searches at $10 per 1,000; container time is recorded but counted as $0, inside the free hours).

## Settings (`server/messaging`)

| Env | Default | What |
|---|---|---|
| `STUDIO_ENABLED` | `0` | `1` turns Studio on (also needs `ANTHROPIC_API_KEY`, `MEMORY_ENCRYPTION_KEY` and `STUDIO_SKILLS`) |
| `STUDIO_MODEL` | `claude-opus-5-5` | |
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
- **No Haiku for titles.** The plan step already returns the title; one model keeps one cache namespace.
- **No server-side fallbacks on the make step.** Whether a fallback model runs Doddy's custom skills isn't documented; a refusal there ends the job as `refused`.
- **Files in the messaging database, not object storage** (decision 4 is open); **no website, no publishing** (S2).
- **The item screen speaks the infographic's alt text** (`summary.altText`), which the brief didn't list.

## Tests

Run on 22 Oct 2026 in a Linux container (Node 22.22.0, Swift 6.1.2, Postgres 16, Python 3 with reportlab and matplotlib):

| Command | Result |
|---|---|
| `TEST_DATABASE_URL=… npm test --prefix server/messaging` | **181 pass, 0 fail, 0 skipped** (28 new: 18 offline in `studioUnits.test.ts`, 10 through the HTTP API against Postgres in `studio.test.ts`). Mutation checks: removing the daily cap, making every item ready, keeping unseen URLs, allowing `<script>` or allowing orange text each fail tests; removing the owner check on file downloads is still caught, because the file's encryption is bound to its owner's account |
| `scripts/check_studio_crosscheck.sh` | PASS: the server's 14 checks accept the files the real renderers made from both samples |
| `scripts/studio_skills.sh check` | PASS: 3 skills (frontmatter, sizes, no font or image files), 4 render variants (Polish bar, English column, line with numbered facts, donut), a broken SVG caught |
| `swift test --package-path Packages/DoddyCore` (Linux flags) | **1,395 tests, 0 failures** (24 new in `StudioTests`, plus updated `ActivityTextTests` and `DataFlowTests`); the shared digest vectors match the server's |
| `scripts/typecheck_app_logic.sh` | PASS: 26 app files, `StudioModel.swift` included |
| `python3 -I scripts/voice_agent_spec.py check` | PASS: 95 tools, `make_something` included (its generic rules cover it; no change was needed) |
| `scripts/check_forbidden_capabilities.sh` | PASS; mutation-checked (see the evidence log) |
| `python3 -I tools/build_strings_catalog.py --check` | PASS: Polish 1,700 of 1,778 |
| `TEST_DATABASE_URL=… scripts/ci.sh --core-only` | **RESULT: PASS for core-only scope**: all 31 steps PASS, including both new Studio steps; the messaging server's database suites ran (not skipped). iOS app NOT verified (`--core-only`) |

**Not run:** the real Anthropic API (no key in this container; the skills were never uploaded), so no real job, no measured cost and no check of the request shapes against the live API; the SwiftUI views and the controller, `VoiceView`, `HomeView`, `RootView` and `SettingsView` changes (no Xcode; the hosted Mac build is their first compile); APNs; Render; a device; the live ElevenLabs agent.

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

Cloud AI and the card wording (1), Render paid plan (2), brand fonts (3), storage and the website (4), the daily cap (5; default $5), the blocklist and `max_uses` (10; defaults empty and 15/15).
