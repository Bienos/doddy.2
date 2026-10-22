# DODDY Studio: audit before building (22 Oct 2026)

**What this is:** the first deliverable of the Studio brief ("research it, make it, keep it, share it"): what Studio can reuse, what is missing, the platform limits re-checked, the risks and costs, and the owner's decisions. **Nothing in this document is built.** No code changed with it. No milestone has started: the brief says to build only the milestone the owner names, and the owner hasn't named one yet.

Read on main at `8aa42c5` (branch `claude/new-session-ayk8tq`, identical tree). Last ADR on main: 578.

## The short version

1. **Most of the plumbing exists.** The background worker (Errands, ADR-570) already has the official SDK, approval by digest, a time limit, a cancel path, three runs at once, the research loop with web search and fetch, and the rule that drops links the run never saw. Studio is an Errand that does more after the research.
2. **The file-making half has never run.** `make_document` (ADR-564) has never called the real Anthropic API. Its request shape matches the current Skills docs, but it uses raw `fetch`, sets no effort, never checks that its deletes at Anthropic worked, and runs inside the backend that sleeps on Render's free plan. It is a reference, not a working base.
3. **Studio couldn't be switched on today even if it were built.** The messaging server is a free Render service that sleeps and stops the worker. The free database is deleted on 10 Nov. Errands are off (`ERRANDS_ENABLED=0`) and have never run. The paid plan comes first, whichever milestone is chosen.
4. **Costs are estimates only.** This container has no Anthropic key, so the brief's "3 real runs of each kind" were **not run**. Estimate for one research brief plus infographic: **about $1.50 to $4** (below). Nothing caps spending in dollars today.
5. **Platform facts mostly hold.** Five corrections, in "Platform limits": the container has no LibreOffice (so no PPTX-to-PDF there); only files at the top of `$OUTPUT_DIR` come back; the Batch API refuses `fallbacks`, so it doesn't suit the make step; `allowed_domains` and `blocked_domains` can't be combined; and web research with dynamic filtering is not zero-retention, which also applies to Errands.
6. **Four corrections to the brief's repository facts** (details below):
   - The brief's line numbers come from the unmerged DODDY Capture branch. Recordings, `RecordingPrompts` and `InterruptionPolicy` are not on main.
   - The Vercel "Account is blocked" statuses are not blocking team `doddyyyy`: its site built normally on 21 Oct.
   - Website sign-in with Apple needs a second Apple identifier and the paid Apple membership, which is still pending.
   - The worker's "only search and fetch" promise (ASK-01's exception) is enforced by code structure alone, with no CI check. Studio adds tools to that worker, so it needs a new ADR and a guard.
7. **Recommended next milestone: B1 (the phone-call bug),** as the brief says. It needs none of the cloud decisions. Its DoddyCore tests need Swift on Linux, which this container doesn't have (see "Environment").

## How this was checked

| What | How | Result |
|---|---|---|
| Repository facts in the brief (Part 0.2) | Read the code and docs named there | Table "What exists" below; corrections marked |
| Call-bug and Talk-on-Home line references (Parts 7, 8) | Every reference re-read on main | Section "B1 and V1 notes, re-checked" |
| Platform facts (Part 2) | Claude docs read again on 22 Oct | Section "Platform limits, re-checked" |
| Hosting | Vercel team `doddyyyy` read with the Vercel connector (read only); Render and storage prices from their sites | Sections "Hosting" and "Costs" |
| Existing tests Studio builds on | `npm ci`, typecheck and `npm test` in `backend/` and `server/messaging/` | Section "Tests run" |
| Real Claude runs, 3 per kind | **NOT RUN**: no `ANTHROPIC_API_KEY` here, and cloud AI for Studio isn't approved yet (CLAUDE.md rule 6) | Estimates only |
| `blog/` (the blog sources) | **Not read**: this session's permissions refuse that folder | The brief's description is taken as given |

## What exists today, and what Studio does with it

| Piece | Where | State (checked) | For Studio |
|---|---|---|---|
| Errands worker | `server/messaging/src/errands/` (`researcher.ts`, `worker.ts`, `service.ts`, `card.ts`, `schema.ts`) | Built. `@anthropic-ai/sdk` 0.128.0, Opus 5.5, effort `high`, adaptive thinking, `fallbacks: "default"` with `server-side-fallback-2026-07-01`, prompt caching, streamed. `pause_turn` resumed; the fallback echo rule handled (`echoable`). 30-minute limit, Cancel polled every 15 s, 3 runs per process, 5 open per account. **Never run against the real API**; off by default | **Reuse** as Studio's runner: the claim loop, the deadlines, the cancel path and the failure codes. Studio is a new errand kind with more phases |
| Errands researcher | `researcher.ts` | Web search and fetch `_20260209`, **no `max_uses`** (owner: no cap), no `blocked_domains`. `SeenSources` collects every URL the run saw | **Reuse** the loop and `SeenSources`. **Add** `max_uses` and `blocked_domains` for Studio jobs only (the owner's "no cap" covers Errands) |
| Errands card | `card.ts`, `schema.ts` | Structured output (`zodOutputFormat`); code drops links the run never saw and prices without their page | **Reuse the pattern** for the research pack. The pack is a new schema (claims with source, quote, date) |
| Approval by digest | `service.ts`, `Errand.swift` (DoddyCore) | The app recomputes the server's SHA-256 over the canonical JSON and approves only that | **Reuse**. Studio's digest covers the typed job (`kind`, `topic`, `audience`, `length`, `style`, picked sources) |
| Errands lifecycle | `worker.ts`, `v15_errands` | The app saves the result, reads it back, acks, and the server deletes its copy | **Changes**: Studio keeps the server copy for the gallery until the owner deletes the item. Needs its own retention rule and receipts |
| Push with no words | `worker.ts` `PUSH_TEXT` | "Done. Your task's result is waiting in the app." | **Reuse** as is |
| `make_document` | `backend/src/tools/claude.ts` | Raw `fetch`, `code_execution_20250825`, Anthropic skills `pptx`/`docx`/`xlsx`/`pdf` at `latest`, up to 8 `pause_turn` resumes, 8-minute limit, 15 MB cap. Model `claude-sonnet-5-5`, no `effort` (Sonnet 5.5 then runs at `high`), no beta header (none is needed: "Platform limits"). Files deleted at Anthropic best effort (`void … .catch(() => {})`, never checked). Picks the last file with the right extension. **Never called the real API** (ADR-564) | **Replace** inside the worker on the SDK (brief Part 2). Keep its Zod argument schemas, file naming and the `fileIdsOf` reader as references |
| Documents store | `backend/src/documents.ts`, table `documents` | File bytes in Postgres. HMAC link over ID and expiry, 7 days; Safari opens it without the app's token. Pruned after a week | **Not reused for Studio** (the brief moves files to object storage). Its capability-link idea carries over to signed storage links |
| Documents in the app | `RunDocument` (`DoddyCore/OnlineAccounts/OnlineAccountsContracts.swift:128`), `VoiceSessionController.documents` (`:312`, filled at `:2997`) | Kept only in the running conversation | **Add** a Studio library in DoddyCore (SQLite, like `v15_errands`) that these cards also save into |
| On-device decks | `make_presentation`, `PresentationFile.swift` (ADR-567) | Office Open XML writer, brand colours (`#FFF7E9`, `#171715`, `#FF6A00`, `#A64B00` as accent 2), no images, no embedded font | **Keep separate.** Studio decks are made on the server; this stays the "Keynote, on the phone, no cloud" path |
| ASK-01 gate | `backend/src/tools/askFirst.ts`, `AskFirst.swift`, `scripts/check_forbidden_capabilities.sh`, `scripts/voice_agent_spec.py` | Enforced. ADR-570's exception: one yes covers every lookup of one errand | **New exception needed** (below, Risk R5) |
| Daily caps | `backend/src/policy.ts:151` `reserveClaude` | 40 Claude runs per user and 100 for the service per UTC day, counted in requests | **Not dollars.** Errands have no cap at all. Studio needs the three limits in the brief |
| Brand tokens | `DoddyDesignTokens/CandidateTokens.swift` | `accentText` `#A64B00` (dark `#FFB56B`); ink, paper, orange as the brief says | **Reuse** as the source for `doddy-brand/brand.py`, ideally generated like `tools/gen_site_tokens.py` does for the site |
| Pack art | `DoddyApp/Resources/Assets.xcassets/WholeDoddy_*` (17 sets), `UploadedDoddy_*` (5 sets); provenance in `docs/design/UPLOADED_MEMORY_ASSETS.md` | 39 PNG files, about 2.4 MB in all | Fits in a skill (30 MB limit). **Recommendation: no character art in S0.** Add it with an allow-list and hashes when a kind needs it |
| Website | `site/` | Static pages with strict CSP (`default-src 'self'`, `frame-ancestors 'none'`, `form-action 'none'`). Vercel functions already exist (`site/api/waitlist*.js`, Vercel Blob, Basic auth admin). Fonts come from Google Fonts at run time; no font file is committed | The studio pages are new functions. The CSP needs a narrow change if pages load files from a storage host (or the function streams them) |
| Secrets | `secrets/manifest.json` | `ANTHROPIC_API_KEY` targets both `render:doddy-messaging` and `render:doddy` | **Reuse**. A storage token, and a GitHub token for blog pull requests, would be new entries |
| DODDY Capture (Recordings) | Branch `claude/gifted-pascal-3e117c`, 8 commits ahead of main, ADR-579 to 583, **unmerged** | Recordings screen, Home's ••• "Recordings" entry, `RecordingIntelligence.swift`, `CaptureStateMachine.swift` | Studio's menu spot ("below Recordings"), ADR numbering (584 and up if Capture merges first) and "turn this recording into…" (ADR-582, open) all depend on it |

## What is missing, by milestone

| Missing | Milestone | Notes |
|---|---|---|
| The typed job contract (`kind`, `topic`, `audience`, `length`, `style`, `sources`) and its validation, in DoddyCore and on the server | S0 | One schema shared by both sides: the digest is computed over the same canonical JSON |
| Studio item model and states (queued, researching, making, checking, ready, needs a look, failed), and the delete rules, in DoddyCore with Linux tests | S0 | Same pattern as `Errand.swift` |
| Plan step with structured output | S0 | Opus 5.5 at effort `high`, `output_config.format` |
| Research pack schema (claims with URL, quote and date fetched) and its validator | S0 | Reuses `SeenSources`; a claim whose URL the run never saw is dropped |
| `max_uses` and `blocked_domains` on Studio's research calls | S0 | A starting blocklist of content farms needs the owner's eye |
| Make step on the SDK: code execution with skills, files downloaded, then deleted at Anthropic with the delete **read back** | S0 | `make_document` deletes without checking. Studio must check |
| `studio-skills/` (`doddy-brand`, `doddy-research`, `doddy-infographic`, `doddy-docs` for the brief), `scripts/studio_skills.sh check` and `upload`, wired into `scripts/ci.sh` | S0 | The Linux check needs python-pptx, python-docx, reportlab, pypdf, matplotlib and pillow. In this container matplotlib is **missing**; CI would need it installed |
| Check step in code | S0 | What code can and cannot check: Risk R7 |
| Object storage for files and thumbnails, with signed links that expire | S0 | Choice below |
| Spend limits: a token budget per job, a dollar cap per owner per day, the cost on each item | S0 | Errands have none today |
| The ASK-01 card for a Studio job, the new exception's ADR, and the four enforcement files | S0 | Card text is English only today (ASK_FIRST.md gaps) |
| Studio list screen, item view (Quick Look, the image, sources, Share, Delete), Home ••• entry | S0 | **Not compilable here** (no Xcode). The hosted Mac build is the first compile |
| `make_something` voice tool, and the live agent update | S0 (spec), owner's "do it" (live) | The live agent also still lacks `hand_over_errand` and `check_errands` |
| Strings in the catalogs, Polish included | S0 | Studio needs about 40 new strings |
| `doddy-deck`, `doddy-docs` (documents), previews in Keynote and Pages | S1 | |
| Private studio and public showcase on the website, publish with approval, unpublish | S2 | Website sign-in with Apple is blocked on the Apple account (Risk R9) |
| Blog pull requests from the server | S2 | Needs a repository-write token on the server (Risk R10) |
| `doddy-interview-prep`, `doddy-explainer`, the voice mock interview | S3 | |

## Platform limits, re-checked

Read again in the Claude docs on 22 Oct (platform.claude.com: code execution tool, Skills guide, Agent Skills overview, Files, pricing, models, Opus 5.5 "what's new", batch processing, structured outputs, web search and web fetch tools, data retention, task budgets, refusals and fallback, the 2026-10-21 API version migration, prompt caching, Managed Agents). "Changed" means the brief needs a correction.

| Brief's fact | Verdict | What the docs say now |
|---|---|---|
| Container: Linux, 5 GiB RAM, 5 GiB disk, 1 CPU, no internet, pre-installed libraries only, reusable by `container.id`, 30-day expiry | Confirmed | Python 3.11. The library list includes python-pptx, python-docx, reportlab, pypdf, pdfplumber, matplotlib, seaborn, pillow, pandas and openpyxl. **No Node.js and no LibreOffice**, so a PPTX can't be turned into a PDF by LibreOffice in the container (S1's "then exports a PDF" needs another way, such as drawing the PDF directly with reportlab). The container expires 30 days after it was made; after about 5 idle minutes it is checkpointed, not lost |
| `pause_turn`: send the turn again with the same container | Partly | The docs say to send the response back as it is. They don't spell out the container; pass `container.id` (as `make_document` does) and test that files persist |
| Container cost: free with web search or fetch in the request, else 1,550 free hours a month, then $0.05 an hour | Confirmed, plus | Each execution bills **at least 5 minutes**. If files are attached to the request, time bills even when the tool isn't called |
| Code execution version: `code_execution_20250825`; "`20260521` only adds programmatic tool calling" | **Changed** | `_20250825`: bash and file operations. `_20260120` added REPL state and programmatic tool calling. `_20260521` is the same runtime with a note on 90-second cells. The Skills guide's examples still use `_20250825`. Web search and fetch `_20260209` provision code execution themselves, and a code execution tool declared next to them must be `_20260120` or later |
| Beta headers | Confirmed: none | The Skills guide's examples send only `x-api-key` and `anthropic-version`, with `code_execution_20250825`: **the same shape `make_document` sends.** The Skills and Files APIs are generally available; `skills-2025-10-02` and `files-api-2025-04-14` are optional legacy headers |
| Up to 20 skills per request | Confirmed | 20. Anthropic's are `{type: "anthropic", skill_id: "pptx" \| "xlsx" \| "docx" \| "pdf"}`; custom ones are `{type: "custom", skill_id: "skill_…", version: "latest" \| "skver_…"}` |
| Custom skills: `POST /v1/skills`, `SKILL.md`, `name` ≤ 64 (lowercase, digits, hyphens), `description` ≤ 1,024, upload < 30 MB, versions are full snapshots, visible to the whole workspace | Confirmed, plus | The 30 MB counts all files, uncompressed. `name` may not contain "anthropic" or "claude". **Any key in the workspace can use or delete any skill** |
| Files come back as `file_id`s in the code-execution results; download, then delete | Confirmed, plus | Only files at the **top level of `$OUTPUT_DIR`** are captured; the skills must say so. Images get C2PA content credentials on download, so their bytes differ from the container's copy (hash after download). 500 MB per file, 1 TB per organization. **No documented expiry for generated files**: they stay until deleted. File IDs are workspace-wide, so the server never accepts a `file_id` from the app |
| Code execution isn't eligible for zero data retention | Confirmed, wider | Also not zero-retention: Skills, the Files API, the Batch API and Managed Agents. **Web search and fetch with dynamic filtering (the `_20260209` tools Errands use) aren't zero-retention either**; only their basic use is. "What leaves this iPhone" should say this for Errands too |
| Opus 5.5: $4 / $20, 1M context, thinking always on, effort defaults to `medium` | Confirmed | 128K output. **Forced `tool_choice` (`any` or `tool`) returns 400** on Opus 5.5: use structured output or `strict` tools with `auto`. Text between tool calls arrives in `thinking` blocks by default, so a progress line from the model needs `display: "updates"` |
| Haiku 5.5 for titles and tags | Confirmed | $0.10 / $0.50 per million tokens up to 100K prompt tokens |
| `stop_reason: "refusal"` with server-side fallbacks | Confirmed | `fallbacks: "default"` with `server-side-fallback-2026-07-01`, as Errands already sends. **Not available in the Batch API** |
| Batch API at half price | Confirmed, limits | Accepts web search, web fetch and code execution, and multi-turn requests. Rejects `stream` and `fallbacks`. Skills and `pause_turn` inside a batch: not documented. **So batch doesn't fit Studio's make step**; at most a "no rush" research phase, after a pilot |
| `temperature`, `top_p`, `top_k` rejected from 21 Oct | Changed (how) | They are removed in API version `2026-10-21`, chosen by the `anthropic-version` header, not the date. The TypeScript SDK sends it from 1.0.0. Neither server sends these fields today (messaging uses SDK 0.128.0; the backend uses `2023-06-01`) |
| Structured output (`output_config.format`) | Confirmed, limits | **Can't be combined with citations** (400). Rejects numeric and string constraints, recursive schemas and external `$ref`. Whether it combines with server tools isn't documented. So, as Errands do already: research with tools first, then a separate schema-only call for the pack |
| Task budget in `output_config` | Confirmed | Beta `task-budgets-2026-03-13`, minimum 20,000 tokens, **advisory only**. `max_tokens` is the hard limit per response; the dollar cap must be Doddy's own code |
| `max_uses` and `blocked_domains` on web tools | Confirmed, one limit | Both supported. **`allowed_domains` and `blocked_domains` together return 400.** Web search costs $10 per 1,000 searches; web fetch costs only its tokens and only fetches URLs already in the conversation |
| Managed Agents (beta) | Confirmed | Header `managed-agents-2026-04-01`. Session budgets in dollars (the check runs between model requests, so a session can overshoot); outcomes graded by a separate grader against a rubric (up to 20 iterations); scheduled deployments with cron; webhooks. Runtime $0.08 per session-hour on top of tokens. Not zero-retention |
| Cache the system prompt and the skill list | Confirmed | Opus 5.5 caches prefixes from 512 tokens; reads $0.20, writes $5 (5 minutes) or $8 (1 hour) per million. **Changing the skill list breaks the cache**, so each kind should send a fixed list |

**What this changes in the design:**
- Keep research and making in separate requests, as the brief says: structured output can't carry citations, and the check step sits between them. The making request pays container time (within the free hours, 5 minutes at least each run).
- Doddy's skills must tell Claude to write deliverables to the top level of `$OUTPUT_DIR`.
- S1's "deck, then a PDF of it" can't use LibreOffice in the container.
- Batch is not a fit for Studio's make step; skip it until a pilot shows Skills work there.
- The privacy page must say that web research (dynamic filtering) is not zero-retention, for Errands as well as Studio.

## Hosting (read 22 Oct)

- **Render.** `render.yaml` was never applied; the running services were made by hand (its header, 18 Oct). `doddy-messaging` is a free web service with the worker inside it (`RUN_WORKER_IN_WEB=1`); it sleeps after about 15 minutes idle, which stops any running job. **The free database is deleted on 10 Nov** (STATUS). The Blueprint already names the paid shape: `doddy-messaging` and `doddy-messaging-worker` on `starter`, the database on `basic-256mb`. Render lists Starter at about $7 a month per service and Basic-256mb Postgres at about $6 a month plus storage, so about **$20 a month** for that shape. Read the prices on render.com before paying; they were not confirmed from an invoice.
- **Vercel.** Team `doddyyyy`'s production deployments read on 22 Oct: the latest builds of `doddy`, `doddy-voice-token` and `doddy-gateway` were **CANCELED** by the Ignored Build Step (docs-only merges), not blocked. The site's last READY build is from #120 on 21 Oct. No BLOCKED or ERROR production deployment came back. STATUS already reads the red "Account is blocked." statuses as coming from an old team's projects. **Owner: say which account shows "blocked"**; if it is the old team, it doesn't block Studio.
- **Object storage: Vercel Private Blob or Supabase Storage.**

  | | Vercel Private Blob | Supabase Storage |
  |---|---|---|
  | Already used | Yes: the waitlist (public blobs) | Supabase Auth is accepted by the backend (ADR-526); two old Supabase functions are waiting to be deleted (STATUS) |
  | Private files, links that expire | Yes. Private Blob is generally available; a signed URL covers one operation on one path, for at most 7 days | Yes. Private buckets with signed URLs |
  | Writing from the Render worker | A read-write token as a server secret | A service key as a server secret |
  | Serving the studio pages | Same platform as the site's functions; functions on Vercel use a short-lived token instead of a stored key | A second vendor in the request path |
  | Concerns | Vercel's Hobby plan is for personal, non-commercial use. Check whether Doddy already needs Pro | Free projects can be paused when idle (check the current rule); a paused project means missing files |

  **Recommendation: Vercel Private Blob.** It keeps files next to the pages that show them, and adds no vendor. Supabase Storage is the fallback if the owner wants files and sign-in in one place.
- **Encryption at rest.** Errands encrypt words and results with `MEMORY_ENCRYPTION_KEY`. Files in object storage are readable by the storage provider unless the worker encrypts them first. Encrypting means every viewer, including the website's function, needs the key to decrypt. Recommendation: no extra encryption in S0 (private store, signed links). Record it as an owner decision with the privacy page saying so.

## Costs

**First real measurement, 22 Oct 2026 (one run, partial): plan + research + pack + write came to $1.42 for a short Polish brief with 8 searches and 8 fetches (research $0.92, pack $0.24, two write attempts $0.24, plan $0.01), 321 s; the make step has not run, so the make rows below remain estimates. See `STUDIO.md` "First real run".** The rest are estimates from list prices and typical sizes; the first three real runs per kind replace them. Prices: Opus 5.5 at $4 / $20 per million tokens in and out, cache reads $0.20; web search $10 per 1,000 searches; code execution free in a request that also has web search or fetch, otherwise within 1,550 free container hours a month.

| Step | Model and effort | Assumed size | Estimate |
|---|---|---|---|
| Plan | Opus 5.5, high, structured output | 2k in, 3k out (thinking included) | about $0.07 |
| Research | Opus 5.5, high, web search and fetch, `max_uses` 15 each | 100k to 200k fresh input, 100k to 300k cache reads, 10k to 25k out, 10 to 15 searches | $0.75 to $1.60 |
| Make: brief PDF and infographic | Opus 5.5, medium, code execution with 3 to 4 skills | 40k to 120k input over the turns, 10k to 30k out; container time billed in at least 5-minute runs, inside the 1,550 free hours | $0.40 to $1.10 |
| Check, one retry of Make (worst case) | as Make | as Make | $0 to $1.10 |
| Title and tags | Haiku 5.5 | under 2k | under $0.01 |
| **One research brief and infographic** | | | **about $1.50 to $4** |

What that means: one item a day costs about $45 to $120 a month; three a day about $135 to $360. A daily cap of $5 allows one to three items a day. The Batch API halves token prices, but it can take hours and refuses `fallbacks`, and Skills inside a batch aren't documented: leave it out until a pilot.

Fixed costs: about $20 a month on Render (above), plus Vercel Pro ($20 a month) if the Hobby terms rule Doddy out. Google's yearly security assessment (CASA) for restricted Gmail scopes is a separate, larger cost, only for the G milestones.

## Risks

| # | Risk | What happens | Mitigation |
|---|---|---|---|
| R1 | No file has ever been made through the API from this repository. `make_document`'s shape matches the docs, but it has never run | The first live job fails on something only a real run shows (where files land, `pause_turn` with a container, file sizes) | Studio's make step is written on the SDK and run against the real API in S0, three runs per kind, before anything is called done |
| R2 | Render free plan sleeps; database deleted 10 Nov | Jobs die mid-run (`interrupted`); every stored item is lost on 10 Nov | Paid instance and kept database before S0 is turned on (owner decision 2) |
| R3 | No dollar cap anywhere | A runaway research loop or a busy week costs far more than expected. Errands' lookups are uncapped by the owner's choice | Studio jobs get `max_uses`, a token budget and a per-owner daily dollar cap checked **before** a job is queued and between phases. Task budgets are advisory to the model, so the code cap is the real one |
| R4 | Web pages steer the output (prompt injection) | A page's text adds a link, a claim or an instruction into a published item | Tool and web content fenced as data in every prompt (as `RESEARCH_SYSTEM` does); the item may only contain claims that map to the pack; links only from the run; the worker has no tool that writes outside the container |
| R5 | ASK-01's Errands exception says the worker has **only** web search and fetch; nothing in CI checks that | Adding code execution and skills to the same worker silently widens what one yes allows | New ADR for the Studio exception (one yes covers this job's searches, fetches and file making, nothing else). Change `askFirst.ts`, `AskFirst.swift`, `check_forbidden_capabilities.sh` and `voice_agent_spec.py`. Add a test or guard that pins the exact tool list of each worker phase |
| R6 | Code execution isn't eligible for zero data retention | The topic, the research and the files stay at Anthropic under its normal retention | Say so on the ASK-01 card and on "What leaves this iPhone"; delete files at Anthropic and read the delete back |
| R7 | "Every claim maps to the pack" can't be fully checked by code | A sentence in a PDF or slide can say more than its source, and only a person or a model would notice | Make from structured content: the model writes the item as JSON where each fact carries a claim ID; code checks IDs, URLs, quotes, lengths, alt text and colours on the JSON and on the SVG (text); the PDF and PNG are rendered from that JSON by Doddy's own script. Say plainly that wording faithfulness is not machine-checked |
| R8 | "Every link resolves" means the server fetches arbitrary URLs | Server-side request forgery against internal addresses | The link check refuses private and link-local addresses, follows few redirects, times out fast and reads no body |
| R9 | Website sign-in with Apple needs a Services ID, a verified domain and the paid Apple membership (still pending, STATUS). The voice token server accepts only the app's bundle ID as the audience today | S2's private studio can't sign in | S2 waits on the Apple membership; the token server learns a second audience |
| R10 | "Put this on the blog" opens pull requests from the server | A repository-write token sits on a server that also reads the web | A fine-grained token limited to `Bienos/doddy.2` contents and pull requests, or a GitHub App; the owner merges every post |
| R11 | Fonts: the container can't download, CLAUDE.md forbids unreviewed font files | Brand fonts are missing from files; Polish letters could fall back badly | Use the container's fonts in S0 and say so; check Polish diacritics in the first runs; Bricolage Grotesque and Caveat (SIL Open Font License) go into `doddy-brand` only on the owner's yes |
| R12 | Character art misuse | A model draws or traces Doddy | No character art in S0; later only the pack PNGs, by allow-list and hash, never generated |
| R13 | Public showcase | A published item is wrong, quotes too much of a source, or names a person | One approval per publish showing the page exactly; sources and dates on every page; unpublish verified; short quotes only |
| R14 | Capture and Studio touch the same files | Merge conflicts in `HomeView.swift`'s ••• menu, `DECISIONS.md` numbering, the strings catalog | Merge Capture first or renumber; Studio's ADRs start after the last merged one |
| R15 | The app half can't be compiled here | SwiftUI and controller changes ship uncompiled until the hosted Mac build | Keep logic in DoddyCore (Linux tests); views small; the hosted run is the first compile, as for every recent PR |
| R16 | Google restricted scopes (G milestones) | A public app reading Gmail needs Google's verification and a yearly security assessment | Minimum scopes; the Picker with `drive.file`; check Composio's verified app first (owner decision 6) |

## Privacy and the constitution

| Rule | Studio's answer | Where it would be enforced |
|---|---|---|
| ASK-01: ask first, exact payload | One card per job showing the exact typed job, Anthropic and web search named, and that code execution isn't zero-retention | App: `AskFirst.swift`; server: digest check in the Studio service (as Errands) |
| DOD-07: external writes need a tap on the exact payload | Publishing (website, blog pull request, Google export) is a separate card each time, showing the page or file exactly | Server: a publish route that refuses without a fresh approval bound to the item's digest |
| DOD-08: done only when confirmed | "Ready" only after the files are stored, a thumbnail made and the item read back; publish done only on the provider's answer | Worker and publish route |
| DOD-09: unknown is never success, no blind retry | A job whose worker died is `interrupted`, not re-run; a publish whose answer never came back is `unknown` and checked before any retry | Worker (as Errands); publish route |
| DOD-02: honest | Links only from the run; claims only from the pack; "needs a look" when checks fail twice | Check step |
| Data, not instructions | Web, tool and document text fenced in every prompt | Prompts, plus the tool allow-list (R5) |
| DOD-06: no invented memory | Interview stories only from what the owner says in the job or picks | The job contract has no field for anything else |
| Delete | Files removed from storage, the website and Anthropic's Files API, each read back before "deleted" is said | Studio service, with receipts like `errand_deletions` |

## B1 and V1 notes, re-checked against main

The brief's line numbers were taken on `claude/gifted-pascal-3e117c` (Capture). On main they are mostly right with shifted lines:

- **Call bug (B1): the root cause holds.** `watchAudioInterruptions` is at `VoiceSessionController.swift:995-1008`; `audioInterruption` (`:1016-1022`) only sets `audioPausedByOtherApp` and `audioNote` behind `guard isLive`; nothing reads `.shouldResume`, calls `setActive` or ends the conversation. The observer is installed only after connect (`:787` ElevenLabs, `:900` OpenAI). Nothing observes `mediaServicesWereResetNotification`, and nothing uses `CXCallObserver`. `isLive` (`:483-488`) covers connecting, listening, thinking and speaking, so the gate (`:839-846`) and the island stay busy; the Live Activity heartbeat is `VoiceLiveActivity.swift` (stale after 90 s, beat every 40 s). The three blocked ways back are as described (`VoiceView.swift:115-121`, `RootView.swift:189-191`, `TalkInIsland.swift:49-52`). OpenAI's `RealtimeAudioIO.restart()` (`OpenAIRealtimeSession.swift:384-393`) restarts the engine without `setActive(true)`. LiveKit is `from: 2.10.0` in `project.yml:31-33`; the app's `Package.resolved` isn't committed.
- **Corrections for B1:**
  - `VoiceSessionEnd.Drop` lives in DoddyCore's `SessionRecovery.swift:22-29` with `offline`, `connectionLost` and `error(String)`. `audioInterrupted` is new.
  - `fail(...)` (`:2165-2184`) frees the microphone, the gate, the pill and the island, and keeps the transcript and the recovery note (only if the call connected once). Unlike `stop()`, it does **not** clear `permissionRequest`, `callsAsReceived` or the ask ledger. B1 should check that a held permission sheet can't outlive the conversation.
  - **`InterruptionPolicy` is not on main.** It exists only on the Capture branch, so B1 either waits for Capture, or writes `VoiceInterruptionPolicy` on its own.
- **Talk on Home (V1): holds, with shifts.** `talk()` is at `HomeView.swift:372-386`; the director's closure is set in `RootView.swift:246-249`; the pill hides at `ListeningStop.swift:109`; the permission sheet holds the call at `VoiceSessionController.swift:3728-3749`, and `permissionRequest` (`:287`) has no `didSet { syncIsland() }`, unlike `pendingAction` (`:241`). That confirms the island can't flag the sheet. **Correction:** `ShortcutRouter.swift:269-271` is unrelated code now; the blocks are the `!isVoicePresented` guards at `:79-153` and `isCaptureBlocked` (`:240-242`). Shared text and new notes are queued, not refused, while the screen is up.

## Small things found on the way (not changed)

- `server/messaging/src/config.ts:75-77` says errands are "On by default", but the default two lines later is `ERRANDS_ENABLED="0"` (off), which is what ERRANDS.md, ADR-570 and `render.yaml` say. The comment is wrong, not the setting.
- Nothing in CI pins the Errands worker's tool list (`RESEARCH_TOOLS`), although ASK-01's exception depends on it (Risk R5).

## Environment for the next milestone

- **No Xcode** (Linux container): app code is BLOCKED / NOT RUN here, as always.
- **No Swift toolchain in this container** (`swift: command not found`), although earlier sessions ran DoddyCore on Swift 6.1.2. B1's and S0's DoddyCore tests need it installed (from swift.org) or a session that has it.
- Node 22.22.0 is installed; `backend/package.json` asks for 22.22.3 or later (engines warning only).
- Python here has python-pptx, python-docx, reportlab, pypdf and pillow, but not matplotlib or cairosvg.
- No `ANTHROPIC_API_KEY` and no `ant` CLI: real runs need a key added to this environment's secrets, or runs done on Render.

## Tests run for this audit

Run on 22 Oct in this container (Linux, Node 22.22.0), on main's tree, with no change to any code. They show the base Studio builds on passes today; they test nothing of Studio, which doesn't exist.

| Command | Result |
|---|---|
| `npm ci --prefix backend`, then `npm run --prefix backend typecheck` | Passed (`tsc --noEmit`, no errors) |
| `npm test --prefix backend` | **274 tests, 274 pass, 0 fail, 0 skipped** (324 s). Includes ADR-564's: "ask_claude: card first, nothing sent before the yes", "make_document: answers at once with a link…", "make_document: a failure says so…", "Claude daily cap, counted after the yes and before the call", "Claude arguments are strict", "document links: signed, expiring, and bound to one ID". All against the mock and a fake Anthropic API |
| `npm ci --prefix server/messaging`, then `npm test --prefix server/messaging` (typecheck and tests) | **78 tests, 78 pass, 0 fail.** Six database suites **SKIPPED** (`TEST_DATABASE_URL` not set): server, phone calls, **errands**, news digests, call cases, call-case worker. The errand config and schema tests ran |

**Not run:** DoddyCore's Swift tests (no Swift toolchain here), anything in the app (no Xcode), the messaging database suites (no Postgres), any call to the real Anthropic API, Render or a device.

## The owner's decisions

From the brief, with what this audit adds:

1. **Cloud AI for Studio** (the Claude API on the server) and the ASK-01 card's wording. Proposed card, English:
   > **Make this with Doddy?**
   > Research "<topic>" on the web and make a research brief (PDF) and an infographic.
   > Your topic goes to Anthropic (Claude), which searches the web and makes the files. Anthropic keeps the work under its normal retention; code execution isn't zero-retention.
   > It takes a few minutes. Nothing is published or sent anywhere.
   > **Make it** · **Not now**
2. **Pay for Render before 10 Nov**: the Blueprint's shape (two Starter services and a Basic database), about $20 a month; and say which Vercel account shows "blocked".
3. **Fonts in the brand skill** (Bricolage Grotesque, Caveat): yes or no. Until yes, the container's fonts.
4. **Website storage and sign-in:** Vercel Private Blob (recommended) or Supabase Storage; whether the public showcase is wanted; encryption at rest, yes or no.
5. **A daily spend cap per owner**, in dollars. Suggested start: $5 a day. Also: should Errands share the cap? (They have none.)
6. **The Gmail route:** Composio's verified app, or Doddy's own Google verification and security assessment.
7. **V1:** what a tap on Doddy does mid-conversation (proposal: open the transcript).
8. *(New)* **Which milestone to build first.** The brief and this audit recommend **B1**.
9. *(New)* **Merge order with Capture:** merge Capture (`claude/gifted-pascal-3e117c`) before Studio, or build Studio's menu entry on main.
10. *(New)* **A starting blocklist** of content farms for Studio's searches, and the `max_uses` per job (suggested: 15 searches, 15 fetches).

## Next

Build only the milestone the owner names. Recommended: **B1**, then V1, then S0 once decisions 1, 2, 4 and 5 are made.
