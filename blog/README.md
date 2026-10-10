# DODDY blog

Notes from building Doddy, *your mate in your pocket*, in the open. Posts are Markdown files in
`posts/`. Posts with `status: published` appear on the Doddy site at **`/blog/`**
(https://doddy-eight.vercel.app/blog/ once deployed). See ADR 131 in `../DECISIONS.md`.

## Posts

| Date | Title | Status |
|---|---|---|
| 2026-10-10 | [Meet Doddy, the AI agent that remembers what you tell it](posts/2026-10-10-meet-doddy-ai-agent.md) | Published |
| 2026-10-10 | [Hello, Doddy: why our favourite first result was "I couldn't find it"](posts/2026-10-10-hello-doddy.md) | Published |

Post ideas waiting for a slot: [IDEAS.md](IDEAS.md). New post: copy [_TEMPLATE.md](_TEMPLATE.md).

## Editorial rules

The blog follows the same honesty contract as the code (`CLAUDE.md`, `README.md`):

1. **Every capability claim needs evidence.** Link the status doc or test that backs it
   (`docs/implementation/M0_REPORT.md`, `M1_STATUS.md`, `V1_VOICE_STATUS.md`). If it was not run,
   say "not verified yet", the same way `scripts/ci.sh` says `NOT RUN`.
2. **Built, tested and shipped are different words.** "Built" means code exists. "Tested" names
   where (Linux package tests, Xcode simulator, real iPhone). Nobody outside the team has used
   Doddy, so never write "users love" or imply validation. Product ideas are hypotheses (H1–H4 in
   `docs/00_START_HERE/DECISIONS_AND_STATUS.md`).
3. **No screenshots of mockups presented as the app.** Design images from `design/` must be
   captioned as design. Character art is a candidate until ADR 010 (brand master) is decided;
   caption it "candidate art, not final".
4. **No secrets or identifiers.** No API keys, agent IDs, bundle IDs, provider tool IDs, private
   repo links or real personal data. Example memories use made-up content.
5. **Voice:** warm, plain, a little funny about small everyday friction, never hype. Short
   sentences. Doddy's behavioural rules apply to the blog too: no guilt, no fake feelings, no
   promises about features that are not built.
6. **Name third parties accurately** (e.g. ElevenLabs for voice) and do not imply endorsement.

## Front matter

Each post starts with:

```yaml
---
title: "…"              # keep under ~60 characters for search results
date: YYYY-MM-DD
keywords: "…"           # optional; rendered as <meta name="keywords">
author: "…"            # owner fills in
status: draft          # draft | review | approved | published
summary: "One sentence for link previews."
evidence:              # repo docs that back the claims in the post
  - docs/implementation/M1_STATUS.md
---
```

`status: published` only after the owner approves the text and the venue.

## Publishing

1. Write the post in `posts/YYYY-MM-DD-slug.md` (copy `_TEMPLATE.md`). The URL becomes
   `/blog/slug/`.
2. Check every claim against the status docs it lists under `evidence`.
3. Set `status: published` once the owner has approved the text.
4. Run `python3 -I tools/build_blog.py`. It writes `site/blog/` (index, one page per post and
   `feed.xml` for RSS). Commit the post and the generated files together.
5. `scripts/ci.sh` runs `tools/build_blog.py --check` and fails if `site/blog/` is out of date.

Drafts (`status: draft` or `review`) are never rendered. The generator supports `#`/`##`/`###`
headings, paragraphs, `-` and `1.` lists (one level), `>` quotes, tables, `**bold**`, `*italic*`,
`` `code` ``, `[links](url)` and HTML comments (dropped). Keep posts to that subset.
