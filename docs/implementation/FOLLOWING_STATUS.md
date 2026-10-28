# Following: the stories behind what you follow, as a feed (ADR-656)

Owner, 28 Oct 2026 (in Polish): a news "plugin" where you follow what you want, shown like an Instagram feed, built on keywords, and by default "what's happening in Poland". Branch `claude/message-tracking-plugin-rd0cbn`. **Status of each part is at the end. Nothing here has been compiled with Xcode or seen on a device.**

## What it is

Home › ••• › **Following** (Polish: *Śledzone*). Across the top, a row of round badges, one per follow, like a row of stories, and a dashed **+** to add one. Under it, the stories as cards, newest first, with a day heading between Today, Yesterday and Earlier:

- the publisher's badge (its initial), its name and "2 h ago" from the story's own time;
- the publisher's picture, 4:3, when its feed carried one (an https address only), otherwise a quiet square with a newspaper;
- the headline and up to three lines of the publisher's summary;
- three quiet actions: open the full story, save it as a note on this iPhone (headline, summary, publisher and link), share the link.

A new person follows one thing: **"Co się dzieje w Polsce" / "What's happening in Poland"**, which is the server's `poland` topic (TVN24, Polsat News, Notes from Poland, Rzeczpospolita feeds; `server/messaging/src/news/catalog.ts`). **Follow** adds a topic from the server's catalog (the same ten as Daily news) or the person's own words: a name and comma-separated keywords. **Edit** reorders the row or stops following. At most ten follows.

What it is **not**: there is no AI anywhere in it. A card is the publisher's headline, summary, picture and link as the feed carried them; nothing is written, picked or summarised by Doddy. Nothing is pushed: it is a screen the person opens. Daily news (ADR-174, `N1_NEWS_STATUS.md`) is unchanged and separate.

## How it works

```
iPhone: NewsFollowList (UserDefaults "news.follows")
   │  POST /v1/news/feed { language, follows: [{catalogId} | {label, keywords}], limit }
   ▼
Server: gatherItems (shared news_cache, feeds 30 min, GNews 60 min) ─▶ buildFeed (shortlist: 48 h, dedupe by link and title,
        ≤6 per publisher, a keyword follow only where the words appear) ─▶ cards, newest first (≤40)
   ▼
iPhone: NewsFeedSections.group (Today / Yesterday / Earlier) ─▶ FollowingView
```

- **Follows stay on the iPhone.** They travel with each request and the server stores nothing of them (tested: `news_topics` and `news_settings` have no row for the account after a feed request). The feeds and searches behind them use the shared `news_cache`, which is not linked to any account (ADR-175).
- **Keyword follows** use GNews when the server has `GNEWS_API_KEY` (the person's words go to GNews, as for Daily news), otherwise only stories from the person's other follows that contain the words. The screen says which applies (`keywordSearch` in the answer).
- **Pictures** are read from RSS `enclosure`, `media:content`, `media:thumbnail` or the first `<img>` in the description, and from an Atom `enclosure` link; https only, read as strings, never followed by the server. The iPhone loads them straight from the publisher with `AsyncImage`.
- **Save** writes a note through `MemoryRepository.save` and says "Saved" only after the store returned the record.

## Files

| Where | What |
|---|---|
| `server/messaging/src/news/feed.ts` | `buildFeed`: the cards from the gathered items |
| `server/messaging/src/news/feeds.ts` | `imageUrl` on a `NewsItem`, `itemImage` |
| `server/messaging/src/news/rank.ts` | `shortlist` takes `{ limit, perSource, windowHours }` (digest defaults unchanged) |
| `server/messaging/src/news/digest.ts` | `gatherItems`, shared by the digest and the feed |
| `server/messaging/src/routes/news.ts` | `POST /v1/news/feed` (60 an hour per account) |
| `Packages/DoddyCore/Sources/DoddyCore/NewsFollowing.swift` | `NewsFollow`, `NewsFollowList`, `NewsFeedRequest`, `NewsCard`, `NewsFeedSections`, `DoddyServerClient.newsFeed` |
| `Packages/DoddyCore/Sources/DoddyCore/DataFlow.swift` | the messaging-server row names Following |
| `DoddyApp/Features/News/FollowingModel.swift`, `FollowingView.swift` | the screen, the add sheet, the edit sheet |
| `DoddyApp/Features/Home/HomeView.swift` | the menu entry and sheet |
| `l10n/pl.json`, `DoddyApp/Resources/Localizable.xcstrings` | 20 Polish lines |

## Executed (Linux, this session, 28 Oct 2026)

| Check | Result |
|---|---|
| Server `npm test` (TypeScript build + `node --test`, real PostgreSQL 16 started locally) | **403 tests, 0 failures** (3 new: pictures from feeds, `buildFeed` rules, the endpoint against Postgres) |
| `swift test` DoddyCore (Swift 6.2.3 downloaded into this session) | **2,175 tests, 0 failures** (9 new in `NewsFollowingTests`) |
| `scripts/typecheck_app_logic.sh` | PASS, 34 files (the new app files are SwiftUI and not among them) |
| `tools/build_strings_catalog.py --check` | PASS; Polish 2,477 of 2,559 strings |

## Not run

- **The SwiftUI (`FollowingView`, `FollowingModel`) and the Home change are NOT COMPILED.** No Xcode here. They need the hosted Mac build and a run on a device, in Polish and English, light and dark, at the largest text size (the ••• menu gained a row in its second section; the first section is unchanged, which the hosted UI tests check).
- **No live feed was fetched.** The server tests use fake feeds. Which publishers put pictures in their feeds (and how many cards therefore show one) is unknown until the server runs against the real catalog.
- **No real GNews call.**

## Privacy and the constitution

- Sent to Doddy's messaging server: the follows (topic ids, or the person's own name and words), the language, once per open or pull-to-refresh. Kept there: nothing of the person's (R-PRIV). The "What leaves this iPhone" page says so (`DataFlow.swift`).
- Sent to GNews: the person's own words, only when the server has a key, as for Daily news.
- Sent to publishers: a request for each picture shown, from the iPhone, as any browser would.
- Model output: none. Tool content (the feeds) is data and is shown as the publisher's, never as Doddy's words (R-TOOLS).
- "Saved" is said only after `MemoryRepository.save` returned (R-MEM).

## Decisions for the owner

1. ~~Is Home › ••• the right door?~~ **Decided, owner, 28 Oct 2026: "W menu".** Following stays in Home's ••• menu, the fourth row of its second section; no Home card, no tab.
2. Should a follow by voice exist ("śledź CPK")? Not built; it would be a small `follow_news` tool plus a card.
3. The privacy policy page (`site/`) needs one line about Following; not changed here.

## Next

The hosted Mac build (ADR-497) to compile the SwiftUI, then one run on a device with the real server to see how many publishers carry pictures.
