# Daily news and On my radar read 78 publishers' feeds (Polish first), tell one story once with its other publishers named, and fetch each feed once, conditionally

- **Date:** 2026-11-13
- **Decided by:** owner, 13 Nov 2026 (in Polish): „ten Daily News, ten na radarze też weź tam popraw, zoptymalizuj, popraw co się da, żeby to dawało lepiej, więcej też sources … żeby to bardziej było takie dokładne” ("Daily News and On my radar: fix them, optimise, improve what you can so they give better results, more sources too … so it is more accurate"). The publishers chosen and the numbers below (thresholds, bonuses, windows) are this pull request's proposal within that instruction; the owner can change any of them.
- **Status:** applied in the pull request from branch `claude/news-more-sources`
- **Replaces:** nothing. Builds on ADR-174/175 (daily news), ADR-656 (Following, now On my radar), `2026-11-10-radar-alerts` and `2026-11-13-radar-fixes`. Leaves `2026-11-13-radar-fixes` part 4 (one list for Daily news and the radar) waiting for the owner.

## Why

Read from `main` at `4bfbc69b` on 13 Nov 2026:

- **Few publishers.** The catalog had 33 feeds. "Poland", the default follow, read four publishers, one of them Polsat News's everything feed (world and sport too). Health had two feeds, AI two, Europe two, all English except a handful (Spider's Web, Bankier.pl, money.pl, Sport.pl, Bitcoin.pl, and the Poland four).
- **The same story several times.** Stories were grouped only by the exact link (tracking parameters dropped) or the exact headline. "Orlen podnosi ceny paliw" from RMF24, Onet and Interia became three cards, and three of a digest's few lines; a radar alert "as it happens" could push it three times.
- **One publisher could fill the top.** Ranking was topic fit plus freshness with a hard cap per publisher (3 in a digest, 6 in the feed), so the freshest publisher took the first three places.
- **Fetching.** Each caller read the shared cache one feed and one query at a time; every stale feed was fetched at once, unconditionally, with no limit on how many at a time; the radar worker re-read every catalog feed for each alert in a pass (10 alerts × 33 rows); Daily news and the radar worker fetched the same feed separately when both found it stale at the same moment. The cache kept a feed's whole answer (up to 256 KB of JSON), old stories included (the WHO feed's 60 items were all over a month old).

## Decision

1. **More publishers, Polish first.** 78 feeds from 49 publishers (36 feeds in Polish), every one fetched from the build machine on 13 Nov 2026 through its egress proxy with the server's own user agent (`DoddyNewsBot/0.1`) and Accept header, parsed with `parseFeed`, and checked against its host's robots.txt (`urllib.robotparser`, for `DoddyNewsBot` and `*`). Added (each answered with dated stories, most within the last two days):
   - **Poland:** RMF24 (Polska), Onet (Wiadomości), Interia (Wydarzenia), Wirtualna Polska, Gazeta Wyborcza (Kraj); Polsat News's Poland feed replaces its everything feed.
   - **World:** RMF24 (Świat), TVN24 (Świat), Polsat News (Świat), Deutsche Welle, Al Jazeera, France 24.
   - **Europe:** DW po polsku, Euronews, Deutsche Welle (Europe), France 24 (Europe).
   - **Technology:** Antyweb, CHIP, Komputer Świat, Benchmark.pl, WP Tech, The Guardian, Engadget.
   - **AI:** The Guardian, Ars Technica (AI), MIT Technology Review (AI).
   - **Business & markets:** Business Insider Polska, Puls Biznesu, Parkiet, Interia (Biznes), TVN24 (Biznes), RMF24 (Ekonomia), Deutsche Welle (Business).
   - **Science:** Nauka w Polsce (PAP's science service), RMF24 (Nauka), NASA.
   - **Health:** Medonet, RMF24 (Zdrowie), Euronews (Health), NPR (Health), STAT.
   - **Sport:** Przegląd Sportowy, WP SportoweFakty, Interia (Sport), Polsat Sport.
   - **Crypto:** CryptoSlate.
   Each catalog feed now says its language (`lang`). Several Polish publishers are partly paywalled (Rzeczpospolita, Parkiet, Puls Biznesu, Gazeta Wyborcza); a card's link opens the publisher's own page, as before.

   **Left out**, never added unverified: **PAP** (every feed address answered an Incapsula page or 404), **Radio ZET** (no feed found: 404), **Bankier.pl**'s other feeds and **Politico Europe**, **AP**, **CNBC** (Cloudflare "Just a moment" bot check), **Reuters** (no public feed found: `feeds.reuters.com` couldn't be reached, the proxy's tunnel answered 502; the agency site's `/feed/` is 404), **New Scientist** (robots.txt disallows `/feed/`), **VentureBeat** and **Phys.org** (429), **Euractiv** (redirects to another site), **Bitcoin Magazine** (redirects to plain http), **TVN24**'s Poland and business-only feeds at `/polska.xml` and `/biznes.xml` (empty), **DW**'s science feed (empty), a Polish AI-only feed (none answered with recent stories: ITwiz's AI tag was a week old; Chip, Antyweb, Spider's Web, Komputer Świat, Benchmark and Telepolis had none), Wired (mostly promo-code posts), the New York Times (paywall, and enough world coverage without it). **AI** therefore has no Polish publisher; Polish AI stories still reach a word follow ("sztuczna inteligencja") through the Polish technology feeds.

   **Kept though they failed from here:** Bankier.pl's news feed (Cloudflare bot check, 403) and The Guardian's Europe and health feeds (each answered an HTML page instead of the feed in one of two runs). They were in the catalog before; Render's address may get the feed. The screen already names a publisher that doesn't answer ("Not answering right now: …"), and the radar and feed logs now count failed feeds (`feeds_failed`).

2. **Matching a follow (unchanged rules, now tested on Polish headlines).** A follow's words are matched in the headline and the summary (headline counts 3, summary 1), allowing for Polish and English endings (`match.ts`, shared fixture with DoddyCore); a multi-word follow needs all its words, in order ("Robert Lewandowski" finds "Roberta Lewandowskiego", not "Robert Kubica i Lewandowski"). Windows stay: 36 hours for a digest, 48 for the feed and the radar, at most an hour in the future; a story without a readable date never counts.

3. **One story, told once** (`news/dedupe.ts`). Two stories are the same when their links are the same once canonicalised (https, no `www.`/`m.`, no tracking or AMP parameters, no `/amp`, no trailing slash) or their headlines are near-same: at least 4 shared words making up 60% of both (Dice), or 3 making up 80%; a word may change its ending (shared first four letters, or all but three); words of three letters or fewer, and numbers, only as themselves; headlines that both carry numbers with none in common are two stories; common Polish and English function words don't count. The rule leans towards keeping stories apart ("Orlen obniża ceny paliw" and "Orlen podnosi ceny paliw" stay two). Then:
   - the shortlist (`rank.ts`) keeps one entry per story: the copy that fits the follows best, then in the reader's language, then with a picture, then the first seen; its follows are merged;
   - **feed cards** name up to three other publishers with their own links (`alsoFrom`); the app shows "Też: Onet i TVN24" / "Also: Onet and TVN24" under the summary (DoddyCore `NewsCard.alsoFromLine`);
   - **Daily news**: a story sent before by any of its links is left out with all its copies, and so is one whose headline matches a headline of the account's digests of the last 3 days (read from `news_digest_items`, which already holds them);
   - **On my radar alerts**: a new story whose headline matches one found for the account in the last 72 hours (read from `radar_hits`) is not recorded again (`same_story` in the pass's counts), so "as it happens" never pushes the same news twice; alert words are also looked for in the other publishers' headlines.

4. **Picking.** Score = topic fit + freshness + 0.3 when the story is in the reader's language (Polish first for a Polish reader; less than one topic match is worth) + 0.15 per other publisher carrying it (up to two). Stories are picked best first, each next story from the same publisher costing 0.35, with the per-publisher caps kept (3 in a digest, 6 in the feed); a story several publishers carry is then told by one with nothing else in the list when one fits as well.

5. **Fetching once, conditionally, a few at a time** (`news/reader.ts`, `FeedReader`):
   - one query reads the cache rows of every feed a request or pass needs;
   - a feed is read once per request or worker pass (a scheduler pass shares one reader across its digests; a radar pass across its alerts) and fetched once in the process at a time, whoever asks, so Daily news and the radar worker share one fetch;
   - at most 8 fetches run at once in the process (each body at most 2 MB, `safeFetch`'s limits unchanged);
   - a stale feed is asked "changed since?" with the publisher's own ETag and Last-Modified (`If-None-Match`, `If-Modified-Since`; only visible ASCII, at most 200 characters, is ever sent back), kept in two new columns of the shared cache (migration `036_news_cache_validators.sql`); a 304 keeps the cached stories. 40 of the 78 feeds answered 304 to their own validators from here;
   - the cache keeps stories from the last 72 hours (and undated ones), still at most 256 KB a feed; the cache stays 30 minutes;
   - **logs carry counts and times only**: `news feed built` (follows, cards, feeds read, from cache, fetched, not modified, failed, shared, ms), `news digest gathered`, `news digests built`, and the radar pass's counts (`feeds`, `feeds_from_cache`, `feeds_fetched`, `feeds_not_modified`, `feeds_failed`, `feeds_shared`, `same_story`, `ms`). Never a word of a follow, a headline or an address.

6. **Not changed.** Daily news and On my radar stay two lists (`2026-11-13-radar-fixes` part 4 waits for the owner); follows stay on the iPhone (ADR-656); nothing the server stores about a person changes (`news_sent`, `news_digest_items`, `radar_hits` keep their columns; duplicates simply aren't written); the voice agent and `voice-agent/tools.json` are untouched; robots.txt handling, the polite fetcher's limits and the cache's sharing (not linked to any account, ADR-175) are as before; no article page is fetched.

## Consequences

- A word follow ("CPK", "Orlen") now looks through 78 feeds instead of 33. The first request after the cache expires fetches the stale ones, 8 at a time, so it can take longer when many publishers are slow (each fetch still stops at 10 seconds); later requests within 30 minutes read the cache in one query, and about half the publishers answer 304 to a refresh.
- The radar worker reads each feed once per pass however many alerts look at it; with alerts off (`RADAR_ALERTS_ENABLED=0`, the live setting) it does nothing, as before.
- Grouping by headline can, rarely, put two different stories together (a card would then name a publisher whose story differs a little) or keep one story apart (headlines worded differently). The thresholds lean towards keeping apart; tests pin the cases.
- Privacy: no new data about a person is sent or kept. Publishers see requests from Doddy's server for their public feeds, as before, from more publishers; the iPhone loads pictures straight from more publishers, as it did for the four before. The privacy policy's description ("public feeds of publishers") still holds; it lists no publishers.
- Cost: no AI change. The writer still sees at most 25 stories; they are now more varied.
- Ships with the next `doddy-messaging` deploy, which applies migration 036 on start (two nullable columns on the shared cache). The "Też: …" line on cards needs an app build; an older app ignores `alsoFrom`.

## Evidence

- Feeds: three fetch runs from the build machine on 13 Nov 2026 (curl through the egress proxy, the server's user agent and Accept header, 3 redirects, 2 MB, 15 s), parsed with the server's compiled `parseFeed`; robots.txt read for every host; a final run over all 78 catalog feeds: 75 parsed (1,631 stories from the last 48 hours), the three failures named above; a second, conditional request to each: 40 answered 304. **Not fetched from Render's network.**
- Messaging server: `npx tsc --noEmit -p .` and `npm test` against PostgreSQL 16 (see the pull request), including the new `test/newsSources.test.ts`.
- DoddyCore: `make test-core` (`NewsFollowingTests` gains a test for `alsoFrom`). `swiftc -parse` on `FollowingView.swift`; the SwiftUI view is **not compiled** here (no Xcode) and nothing was run on a device.
