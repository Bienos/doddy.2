# On my radar shows its sources, and a tapped story gets a short summary by Claude Haiku

- **Date:** 2026-11-13
- **Decided by:** owner, 13 Nov 2026 (in Polish, translated): "On my radar should get a better design too … choosing [what to follow] makes no sense, you need to know which sources you can connect so that it works, not this random showing … when you tap it … you can get an AI summary of the article … with a model, maybe Haiku, doing a quick review." The shape below (what is sent, the caps, the errors, the labels) is this change's proposal.
- **Status:** proposed (built; not deployed)
- **Replaces:** ADR-656's "No AI writes, picks or summarises anything" for the summary on a tap only. Cards are unchanged: the publishers' own words, no AI.

## Why
The Add sheet offered a topic, words or a feed without showing which publishers Doddy reads, so a follow looked like a random choice. The catalog endpoint already knew each topic's publishers (`sources`); the app showed them only in a one-line caption.

## Decision
1. **Sources list** (`DoddyApp/Features/News/RadarViews.swift`, `RadarAddSheet`): the three ways to follow in plain words (a topic from Doddy's list, your own words looked for in every listed publisher's feed, your own RSS/Atom feed), a field to type anything, and Doddy's list on shelves (News, Technology and AI, Money, Science, health and sport), each topic with every publisher and the host its feed is read from. Picking anything opens a form that shows where its stories will come from before Add.
2. **`GET /v1/news/catalog`** gains, additively, `group`, `groupLabel` and `publishers: [{name, domain}]` per topic (`catalogTopics` in `server/messaging/src/news/catalog.ts`). `sources` is unchanged.
3. **AI summary on a tap** (`POST /v1/news/summary`, `server/messaging/src/news/summary.ts`): the app sends the story's address, the card's headline and its language, never the follows. The server reads the page with the polite fetcher (robots.txt and `Content-Signal: ai-input=no` respected, HTTPS only, public addresses, 10 s, 3 MB, no bot wall worked around), takes the article's own text (JSON-LD `articleBody` or the `<article>` paragraphs, at most 14,000 characters), refuses pages marked not free (`isAccessibleForFree: false`) and pages with too little text, and asks `claude-haiku-5-5` (effort low, structured output) for 3 to 5 points and one line on why it matters. The article is fenced as untrusted data; the code keeps 2 to 5 points of bounded length. A summary is remembered in memory for 6 hours per address and language (at most 400), linked to nobody.
4. **Caps:** per account 30 a UTC day, for the server 2,000, new accounts 200 together (`NEWS_SUMMARY_DAILY_*`, migration `035_news_summaries.sql` widens the two count tables' CHECKs). Counted only when an article was read and goes to the model.
5. **Honest answers:** `422 unreadable` with a reason (paywall, too_short, not_article, blocked, not_allowed, unreachable), `429 limit_reached`, `503 not_configured` (no Anthropic key), `502 summary_failed`. The app shows a summary only from a 200 and says why otherwise; the summary carries "Written by AI (Claude Haiku) from the article. It may contain mistakes."
6. **What leaves the iPhone** (`DataFlow.swift`, row `storySummaries`) and the screens' fine print say it: the story's address and headline to Doddy's server, the article's text to Anthropic, only on a tap.

## Consequences
- **Privacy:** Anthropic now receives public article text when a person taps a story. No personal data goes with it; the server logs codes only. The privacy policy and the App Store privacy answers don't mention it yet (owner step).
- **Cost:** about 5,000 input and up to about 1,500 output tokens (thinking included) of Claude Haiku 5.5 per summary (USD 0.10 / 0.50 per million tokens): roughly USD 0.001 each; the server's daily cap of 2,000 bounds it at about USD 2 to 3 a day.
- **Publishers:** one polite fetch per story per 6 hours at most; a site that says no to AI input is never read for this.
- **Not built:** summaries in the voice agent; caching across restarts (the memory empties when the server restarts or sleeps).

## Evidence
- `server/messaging`: `npm test` against a local PostgreSQL 16, all tests pass (the new `test/newsSummary.test.ts`, the extended catalog test in `test/radar.test.ts`).
- DoddyCore tests written (`NewsSummaryTests`, a `DataFlowTests` case); **not run** (no Swift toolchain in this session).
- **Not compiled:** the SwiftUI (`FollowingView.swift`, `RadarViews.swift`, `StorySummaryView.swift`) and `FollowingModel.swift`. No device run; no real Anthropic call; no live page fetched from Render.
