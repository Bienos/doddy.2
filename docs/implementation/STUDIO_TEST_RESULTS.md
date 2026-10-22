# Studio S0: every test and showcase result in one place (22 Oct 2026)

Everything measured for Studio S0 (ADR-584) on 22 Oct 2026, in one page. Details per run are in `STUDIO.md` "First real run". Studio is still off by default (`STUDIO_ENABLED=0`). The iPhone app half is **not compiled** (no Xcode here), so nothing in this page says the app works.

## 1. Tiers (owner, 22 Oct 2026)

| Tier | Model (every step) | `STUDIO_TIER` | Measured cost of one short Polish brief |
|---|---|---|---|
| Free | Haiku 5.5 | `free` | $0.26 |
| Mid | Sonnet 5.5 | `plus` (**default**: the owner's account runs here for now) | $0.88 |
| Pro | Opus 5.5 | `pro` | $2.02 |
| Top, opt-in | Fable 5.1 | `max` | $4.38 and stopped by the $4 job limit (see below) |

Doddy has no accounts or plans yet, so the tier is one server setting for now; a per-account tier comes with accounts. `STUDIO_MODEL` and `STUDIO_MODEL_<STEP>` still override. The Haiku-plans, Sonnet-writes mix measured as run 4 ($0.51) stays available as `--mix cheap` in the live-run driver, not as a tier.

## 2. The real runs (one Polish job, `short`, 8 searches and 8 fetches)

Topic: "Pompy ciepła w Polsce: ile kosztują i czy się opłacają?" Script: `server/messaging/scripts/studio-live-run.mjs`. Task spend about **$10.18** (limits changed twice by the owner: first $15, then $5, then up to $10 for the Opus and Fable runs; the Fable job crossed the budget by the step that crossed its limit).

| # | Models | Result | Cost | Time | Why |
|---|---|---|---|---|---|
| 1 | Opus, every step | failed `unreadable_result` at write | $1.42 | 321 s | Two write attempts each broke a length limit (chart title 77 > 70, label 26 > 24); the retry saw only the list of problems |
| 2 | Haiku + Sonnet | failed `too_little_found` | $0.35 | 134 s | Sonnet's notes were 6,290 characters with no figures or quotes; Haiku found 2 claims and said so |
| 3 | Haiku + Sonnet | failed `too_little_found` | $0.36 | 87 s | The research request ended with `stop_reason: "tool_use"` and no tool call of ours; the code took it as the end |
| 4 | Haiku + Sonnet | **made, ready, 14 of 14 checks** | $0.51 | 280 s | |
| 5 | Haiku only | **made, ready, 14 of 14** | $0.26 | 265 s | 7 searches, **0 pages opened** |
| 6 | Sonnet only | **made, ready, 14 of 14** | $0.88 | 353 s | |
| 7 | Opus only | **made, ready, 14 of 14** | $2.02 | 476 s | |
| 8 | Fable only | failed `cost_limit` | $4.38 | 505 s | The $4 job limit is checked after each call; Fable's make call crossed it, the four files it made were deleted without download |

By step (USD):

| | Plan | Research | Pack | Write | Make | Searches |
|---|---|---|---|---|---|---|
| Haiku only | 0.0004 | 0.112 | 0.008 | 0.011 | 0.061 | 0.07 |
| Sonnet only | 0.007 | 0.432 | 0.099 | 0.100 | 0.167 | 0.08 |
| Opus only | 0.014 | 1.030 | 0.207 | 0.265 | 0.424 | 0.08 |
| Fable only | 0.032 | 1.895 | 0.618 | 0.735 | 1.016 | 0.08 |
| Mix (run 4) | 0.0004 | 0.367 | 0.007 | 0.044 | 0.010 | 0.08 |

(The step figures are token costs; searches are $0.01 each and are added to the run total.) The cost the code computes and the cost implied by each call's recorded usage agreed in every run.

Content measured: Haiku 39 claims from 28 sources; Sonnet 35 from 18; Opus 35 from 21; Fable 40 from only 5.

## 3. The showcase (`docs/implementation/studio-showcase/`)

| Model | Brief (PDF, 4 pages) | Infographic (1080×1350) |
|---|---|---|
| Haiku only | `haiku-brief.pdf` | `haiku-infographic.png` |
| Sonnet only | `sonnet-brief.pdf` | `sonnet-infographic.png` |
| Opus only | `opus-brief.pdf` | `opus-infographic.png` |
| Fable only | `fable-brief-rendered-locally.pdf` | `fable-infographic-rendered-locally.png` |
| Haiku plans, Sonnet writes (run 4) | `cheap-mix-brief.pdf` | `cheap-mix-infographic.png` |

Side by side: `compare-haiku-vs-sonnet.png`, `compare-opus-vs-fable.png`. **Fable's files were rendered on the server's machine with the same skill scripts from Fable's written content**, because its own make step was stopped by the cost limit before download; the server's 14 file checks pass on them, but they are not what Studio would have shipped. Nothing here has been checked against the live web pages.

What each looked like:
- **Haiku:** clear headline for one case (pump 10 kW, 26–42 thousand zł). Never opened a page. Ground-source price (80–120 thousand zł) above every other run (60–100). Chart has two bars from one source.
- **Sonnet:** headline covers both pump types; five-bar yearly-cost chart; hedges that return figures come from a seller. Best value.
- **Opus:** careful and balanced: 38–65 thousand zł, payback 5 to 15 years, four-bar chart, "may not pay back in an old uninsulated house". 5 sections, 4 gaps, 4 disagreements.
- **Fable:** the richest content (grant ladder 22,280 / 38,990 / 55,700 zł, gas as a comparison bar, radiators about 11% dearer than underfloor), but built on 5 sources, and a 77-character title.
- **Weak points seen in the first finished run (cheap mix):** the infographic headline used the lowest price from one seller without saying so, and left "with a grant" off the payback; the chart was about grants, not about the headline.

## 4. What the real API confirmed

Accepted and working: skills upload (`files[]`, no beta header); `beta.messages.parse` and `.stream` with `fallbacks: "default"` and `server-side-fallback-2026-07-01` (Opus, Sonnet, Fable; not offered for Haiku, which the code skips); top-level `cache_control` next to the web tools; `output_config.task_budget` with `task-budgets-2026-03-13`; `web_search_20260209` and `web_fetch_20260209` with `max_uses`; `container.skills` with `{type: "custom", skill_id, version}` plus `code_execution_20250825` and no beta header; the four files saved at the top of `$OUTPUT_DIR` returned as `file_id`s; `retrieveMetadata`, `download`, `delete`, and a deleted file then 404 (`fileGone`); a Files API listing after the runs showed **0 files at Anthropic**; the usage fields as read by the code. The `_20260209` web tools run code (`code_execution_tool_result` blocks appear in a research result) without a code-execution tool in our request.

**Not tried:** `blocked_domains` together with `max_uses` (none blocked); a topic in English; a Fable or Opus make step shown to completion in Studio; Haiku with `fallbacks`.

## 5. Bugs the real runs found, and the fixes (each tested with the fake, not a paid run)

1. Write retries now carry the previous attempt, there are up to 3 attempts, and the write prompt states the length limits (`studio-s0-2`).
2. Research prompt now demands detailed findings: figure, exact quote, full address, at least 20 where the pages have them (`studio-s0-3`).
3. A `tool_use` stop with no tool call of ours is resumed like `pause_turn` (`resumable()` in `pipeline.ts`).
4. Tiers and a Fable mix; the default is now Sonnet for every step (this page, section 1).

Open: the cost limit is checked after a call, so an expensive last step can cross it and waste its files (Fable, run 8). A pre-check against an estimate of the make step would stop that; not built.

## 6. Tests (Linux container, Node 22.22.0, Postgres 16, Python 3 with reportlab and matplotlib)

| Command | Result |
|---|---|
| `TEST_DATABASE_URL=… npm test --prefix server/messaging` | **190 pass, 0 fail, 0 skipped** |
| `scripts/studio_skills.sh check` | PASS (3 skills, 4 render variants, a broken SVG caught) |
| `scripts/check_studio_crosscheck.sh` | PASS |
| `scripts/check_forbidden_capabilities.sh` | PASS |

**Not run this session:** `swift test` for DoddyCore (last run earlier on 22 Oct: 1,395 pass), the SwiftUI app, APNs, Render, a device, the live ElevenLabs agent. A deck is not a Studio feature (S1); the decks sent to the owner were made locally from the written content and cost nothing.
