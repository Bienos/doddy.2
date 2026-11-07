# N1 status — daily news DM from Doddy

> **Merged 2026-10-10:** this work now sits on the combined branch line. The server lives in
> `server/messaging/` (it was `server/`), its ADRs are 139–168 (were 036–065), the
> `/v1/voice/token` route is gone (the app uses the Vercel `server/voice-token`), and this line's
> M4 Reminders was replaced by the main line's. See `docs/implementation/MERGE_PLAN.md`.

Date: 2026-10-10. Owner decisions on that date:
- **Sources:** RSS feeds plus a paid news API (GNews).
- **Writer:** Claude Haiku writes the one-liners.
- **Frequency:** one daily digest at the user's chosen time.

> **28 Oct 2026:** the same sources now also feed **Following** (ADR-656, `FOLLOWING_STATUS.md`): a screen of cards for what the person follows, with no AI step and nothing stored on the server. The digest below is unchanged.

## Architecture
```
App: Settings → Daily news ──PUT /v1/news/settings──▶ Postgres (news_settings, news_topics, news_feeds)
                                                       │
Worker (every ~2 s) runDueDigests ── claims due accounts (FOR UPDATE SKIP LOCKED), sets tomorrow's time first
   │
   ├─ gather: curated RSS per topic + own feeds (cached 30 min, shared) + GNews for own keywords (cached 60 min, ≤3 per digest)
   ├─ shortlist (deterministic): ≤36 h old, not sent in 14 days, dedupe by URL/title, topic fit + freshness, ≤3 per source, top 25
   ├─ write: Claude Haiku (structured output, effort low) picks ≤5 and writes one line each from headline + summary only
   │         → lines for unknown stories dropped; on any failure: plain top-3 headlines
   └─ send: outbox → push (short list) and/or SMS (≤3 stories with links, ≤640 chars); items stored for the app
```

## How to connect it (owner)
Step-by-step guide: `GO_LIVE_DAILY_NEWS.md`. Since ADR-174 every digest is kept for the app; notifications (Apple Developer Program + APNs key) and texts (Twilio) are optional. With neither, Daily news works "in the app only".
1. **Anthropic or OpenAI:** create an API key and set `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` on the server (ADR-197). Without one, digests are plain headlines.
2. **GNews:** sign up at gnews.io and pick a **paid plan**. The free plan has a 12-hour delay and limits commercial use. Set `GNEWS_API_KEY`. Without it, own-keyword topics match only stories in the RSS feeds.
3. Nothing else: RSS feeds need no account. The worker already runs the scheduler.
4. **In the app:** Settings → Notifications and texts (turn on notifications and/or texts), then Settings → Daily news (topics, own keywords, own feeds, time, language) → Save.

## Built
- **Server:** `migrations/003_news.sql`, `src/news/` (catalog of 10 topics / 28 feeds, `safeFetch`, feed parser, sources + cache, ranking, Claude writer, message formats, scheduling, digest pipeline), `routes/news.ts`.
- **DoddyCore:** `NewsClient.swift`, errors `.unsafeURL` / `.notAFeed`, capability `.newsDigests`.
- **App:** Settings → Daily news.
  - On/off, time, language, notification/text choice, curated topics, own keyword topics.
  - Own feeds, checked by the server before they're added.
  - Save, "Send me one now", and recent digests with tappable links.
  - AI disclosure under the AI-written lines.

## Executed (Linux, Node 22.22.0, PostgreSQL 16.15, Swift 6.2.3)
| Check | Result |
|---|---|
| Server `npm test` | **34 tests, 0 failures** (12 new). Covers: RSS/Atom parsing, DST scheduling, private-address blocking, shortlist rules, AI-line validation, message limits, Claude request shape and refusal/garbage handling, settings validation, once-per-day guarantee, no repeats, fallback to headlines, missing channel recorded, feed check, send-now, account deletion |
| All 28 catalog feeds | Fetched live and parsed with Doddy's parser: every item has a date; Polish characters and entities are correct |
| End-to-end: Swift client → real server + Postgres (fake feeds and writer) | **11/11 PASS** |
| `swift test` (DoddyCore) | **49 tests, 0 failures** (3 new) |
| App Swift files | parse; guard PASS |

**Bugs the tests caught, both fixed:**
- Node's `BlockList` also checks plain IPv4 addresses against the IPv6 rule `::ffff:0:0/96`, which blocked every public IPv4 address. IPv4-mapped addresses are now unwrapped and checked as IPv4.
- The SDK's `parse()` throws before the refusal check on an empty reply. The writer now turns that into `writer_unparsed`, and the digest falls back to headlines.

## Not run
- **No real Claude or GNews call.** This container has no keys. The Claude request was checked against a local stand-in server: model `claude-haiku-5-5`, `output_config.effort: low`, `format: json_schema`, the system prompt, and no URLs or account data sent.
- **App not compiled in Xcode.** No real push or SMS was delivered.

## Privacy and cost
- **Sent to Anthropic or OpenAI (whichever key is set):** topic labels and public headlines and summaries. **Sent to GNews:** the user's own keywords. Never memories, phone numbers or account IDs. The privacy policy needs these two lines.
- **Cost:** about one small Haiku call per user per day. SMS costs per segment; Polish characters use the more expensive encoding, so a 640-character text is up to 10 segments. Push is free.
- **Content:** only headline, a one-line description and the publisher's link are sent, which is what RSS is meant for. A full-text republishing feature would need licences.

## Known limits
- **Breaking-news alerts:** not built (owner chose daily only).
- **Time zone:** taken from the phone when settings are saved. If you travel, saving again updates it.
- **Ranking:** keyword- and recency-based before the AI step; there is no learning from what the user taps.
