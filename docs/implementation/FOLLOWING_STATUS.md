# Following: the stories behind what you follow, as a feed (ADR-656)

Owner, 28 Oct 2026 (in Polish): a news "plugin" where you follow what you want, shown like an Instagram feed, built on keywords, and by default "what's happening in Poland". Branch `claude/message-tracking-plugin-rd0cbn`. **On the default branch since 7 Nov 2026 (#195, through `claude/magical-cray-4299gg`); compiled and tested in #195's hosted Mac job (run 42004675828, 5 Nov); not seen on a device. `doddy-messaging` serves `POST /v1/news/feed` since its 7 Nov deploy of `174ba21`.** Status of each part is at the end; the "Not run" list there is from 28 Oct.

## More publishers, one story once, fewer fetches (13 Nov 2026, branch `claude/news-more-sources`)

Owner, 13 Nov 2026 (in Polish): Daily news and On my radar should give better, more accurate results from more sources, and be optimised. Decision `docs/decisions/2026-11-13-news-more-sources.md` (every feed added and left out, with the reason). Daily news and the radar stay two lists; follows stay on the iPhone.

| Part | Where | State |
|---|---|---|
| 78 catalog feeds from 49 publishers (was 33), 36 in Polish; Poland reads TVN24, Polsat News (its Poland feed now), RMF24, Onet, Interia, Wirtualna Polska, Gazeta Wyborcza, Rzeczpospolita, Notes from Poland; every topic but AI has Polish publishers; each feed has a language | `server/messaging/src/news/catalog.ts` | Every new feed fetched (the server's user agent, through the build machine's proxy), parsed and checked against robots.txt on 13 Nov; not from Render |
| One card per story: the same link (canonicalised) or a near-same headline from another publisher; the card names up to three others ("Też: Onet i TVN24") | `news/dedupe.ts`, `rank.ts`, `feed.ts` (`alsoFrom`); DoddyCore `NewsCard.alsoFromLine`; `FollowingView.swift` (`StoryCard`) | Server and DoddyCore tested; the view line **not compiled** |
| Publishers alternate; the reader's language a little first; a story several publishers carry ranks a little higher | `rank.ts` (`DIVERSITY_PENALTY`, `LANGUAGE_BONUS`, `CORROBORATION_BONUS`) | Tested |
| Radar alerts: the same story from another publisher within 72 hours is not a new hit (no second push); alert words also looked for in the other publishers' headlines | `news/radar.ts` (`collect`, `matchingStories`) | Tested against PostgreSQL 16; alerts still **off** on the server |
| Each feed read once per request or pass, fetched once in the process at a time (shared by Daily news and the radar worker), 8 at once at most, asked "changed since?" (ETag / Last-Modified, migration `036_news_cache_validators.sql`); the cache keeps 72 hours of stories; logs with counts and times only | `news/reader.ts`, `safeFetch.ts`, `sources.ts` | Tested; 40 of the 78 feeds answered 304 to their own validators from here |

## Fixes from the owner's review (13 Nov 2026, branch `claude/radar-fixes`)

Owner's review of 12 Nov 2026 (`docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md` section 6), decision `docs/decisions/2026-11-13-radar-fixes.md`.

| Part | Where | State |
|---|---|---|
| "Tell me…" and its line under a follow, and the Add sheet's "tell me when", only once `GET /v1/news/radar` said `available: true`; a follow with flag words or a server check can still be changed; a check is never said to run once the server says it checks nothing | DoddyCore `RadarAlertsAvailability`, `RadarTellMe` (`RadarOffer.swift`); `FollowDetail`, `RadarAlertFields`, `RadarAddSheet`, `RadarAlertSheet`; `FollowingModel.alertsAvailability`, `loadRadar` (asks the server after a refused re-send) | Rules tested (`RadarOfferTests`); model type-checked; views **not compiled** |
| The voice reply names "the On my radar screen (in Polish "Na radarze"…)" and offers looking there as the next step, never claiming it opened it; the "What Doddy did" row is "Add to radar" / „Dodaj do radaru” | `VoiceToolReply.newsFollow`, `RadarScreen`, `ActivityLog`, `ActivityText` | Tested (`NewsFollowVoiceTests`); `voice-agent/tools.json` unchanged |
| A radar push carries `{"doddy":{"kind":"radar"}}` (kind only) and its tap goes to `ShortcutRouter.radarOpened()` | `server/messaging/src/outbox.ts` `pushData`; DoddyCore `ServerPushKind.radar`; `NoteReminderNotifications.swift` (`TimerBanners`) | Server and DoddyCore tested; handler **not compiled**. **Home doesn't open the sheet yet:** the `.onChange(of: router.isRadarRequested)` in `HomeView.swift` is written out in the decision (that file is held by other pull requests) |
| Settings › Daily news says its topics are only for the daily message and On my radar is a separate list | `NewsSettingsView.swift` | **Not compiled**; the merge itself is a proposal in the decision |

## On my radar: fixes, Add sheet, own feeds and alerts (10 Nov 2026, branch `claude/radar-alerts`)

Owner, 10 Nov 2026 (in Polish): "I added a cryptocurrency section and it doesn't work. Adding needs to be nicer … say when Doddy should tell them about an event, by keywords." Decision `docs/decisions/2026-11-10-radar-alerts.md`. The screen is being renamed "On my radar" / "Na radarze" in #315; this branch keeps `main`'s title.

**Why crypto showed nothing** (read 10 Nov): the live server has no `GNEWS_API_KEY` (`newsSearch: false` in its start log), so a follow of the person's own words was looked for only in their other follows' stories (Poland's four feeds), with a plain substring test that missed Polish endings ("kryptowaluty" vs "kryptowalut"); the crypto topic had one publisher (CoinDesk, behind a redirect); and tapping a follow did nothing, so its few cards were lost among Poland's.

| Part | Where | State |
|---|---|---|
| Matching that allows for Polish and English endings, case and diacritics; phrases in order | `server/messaging/src/news/match.ts`, DoddyCore `RadarMatch`, fixture `schemas/fixtures/radar_match_v1.json` | Tested on both sides (31 shared cases) |
| Words looked for in every catalog feed (33; 78 since 13 Nov 2026) and the person's own feeds, not only their other follows | `gatherItems(…, { keywordPool: "catalog" })`, feed route | Tested |
| Crypto: CoinDesk (canonical address), Cointelegraph, Decrypt, The Block, Bitcoin.pl; Europe + BBC News; a short publisher name per catalog feed | `news/catalog.ts` | Feeds fetched and parsed here on 10 Nov; not from Render |
| Per follow: its publishers and whether each answered, or how many feeds were searched; every follow gets its best 4 stories in the 40 | `POST /v1/news/feed` → `follows[]`; `buildFeed` | Tested |
| Tap a follow: only its stories, its sources, its "tell me" line, "Nothing from the last two days for …" | `FollowingView.swift`, `RadarViews.swift` (`FollowDetail`) | **Not compiled** (no Xcode) |
| **Add to radar** sheet: type anything; topic suggestion ("bitcoin" → Kryptowaluty, with its publishers), the words, or an own RSS/Atom feed (checked first, https only) | `RadarViews.swift` (`RadarAddSheet`), DoddyCore `RadarSuggest`, `NewsFollow.feed` | Rules tested; view **not compiled** |
| "Tell me when" words (a flag on matching cards) and how: Here only / As it happens / Once a day; the last two only with "Let Doddy's server check this for you" | `RadarAlertFields`, `RadarAlertSheet`, DoddyCore `RadarAlert`, `RadarAlertList` | Rules tested; views **not compiled** |
| Server alerts: `PUT/GET /v1/news/radar`, `POST /v1/news/radar/seen`; worker `radarLoop`; tables `radar_alerts`, `radar_hits` | `news/radar.ts`, `routes/radar.ts`, `026_radar_alerts.sql` | Tested against PostgreSQL 16; **off** (`RADAR_ALERTS_ENABLED=0`) |
| "Doddy spotted": what the server found, shown whether or not a notification went out; a dot on the follow until seen | `SpottedList` | View **not compiled** |

How alerts behave: an alert counts only stories published after it was turned on; each story is recorded once per account (that is the dedupe); "as it happens" sends at most one notification per alert per check (`On your radar · Tesla: “<headline>” (Reuters)`, `+N more in Doddy`), waits in quiet hours, lists a story found more than 6 hours late in the app only, and stops at 8 a day; "once a day" sends a count and up to three lines at the chosen time (AI lines from the existing news writer only through `validateLines`, labelled; otherwise headlines), and is skipped if more than 2 hours late. No device token, no push sender or no encryption key: the stories are listed in the app only. Until APNs works in production (OWNER_QUEUE 8) that is where they are. The worker runs inside the free web service, which sleeps when idle; OWNER_QUEUE 34 has the steps.

Voice: `follow_news` is unchanged. The proposed extension (alert words and how, kept "Here only" until the person turns the server switch on on screen) is in the decision and needs `voice-agent/tools.json` and `VoiceSessionController.swift`.

## What it is

Home › ••• › **Following** (Polish: *Śledzone*). Across the top, a row of round badges, one per follow, like a row of stories, and a dashed **+** to add one. Under it, the stories as cards, newest first, with a day heading between Today, Yesterday and Earlier:

- the publisher's badge (its initial), its name and "2 h ago" from the story's own time;
- the publisher's picture, 4:3, when its feed carried one (an https address only), otherwise a quiet square with a newspaper;
- the headline and up to three lines of the publisher's summary;
- three quiet actions: open the full story, save it as a note on this iPhone (headline, summary, publisher and link), share the link.

A new person follows one thing: **"Co się dzieje w Polsce" / "What's happening in Poland"**, which is the server's `poland` topic (TVN24, Polsat News, Notes from Poland, Rzeczpospolita feeds; since 13 Nov 2026 also RMF24, Onet, Interia, Wirtualna Polska and Gazeta Wyborcza; `server/messaging/src/news/catalog.ts`). **Follow** adds a topic from the server's catalog (the same ten as Daily news) or the person's own words: a name and comma-separated keywords. **Edit** reorders the row or stops following. At most ten follows.

What it is **not**: there is no AI anywhere in it. A card is the publisher's headline, summary, picture and link as the feed carried them; nothing is written, picked or summarised by Doddy. Nothing is pushed: it is a screen the person opens. (Since 10 Nov 2026, above: an alert the person turns on can push, and a daily summary may have AI lines, labelled.) Daily news (ADR-174, `N1_NEWS_STATUS.md`) is unchanged and separate.

## How it works

```
iPhone: NewsFollowList (UserDefaults "news.follows")
   │  POST /v1/news/feed { language, follows: [{catalogId} | {label, keywords}], limit }
   ▼
Server: gatherItems (FeedReader over the shared news_cache: feeds 30 min, conditional refresh; GNews 60 min) ─▶ buildFeed
        (shortlist: 48 h, one card per story across publishers with the others named, publishers alternating, ≤6 per publisher,
        a keyword follow only where the words appear) ─▶ cards, newest first (≤40)
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
| `server/messaging/src/news/rank.ts` | `shortlist` takes `{ limit, perSource, windowHours, language, sentTitles }` (digest defaults unchanged); one entry per story since 13 Nov 2026 |
| `server/messaging/src/news/dedupe.ts`, `reader.ts` | The same story across publishers; reading feeds once, a few at a time, conditionally (13 Nov 2026) |
| `server/messaging/src/news/digest.ts` | `gatherItems`, shared by the digest and the feed |
| `server/messaging/src/routes/news.ts` | `POST /v1/news/feed` (60 an hour per account) |
| `Packages/DoddyCore/Sources/DoddyCore/NewsFollowing.swift` | `NewsFollow`, `NewsFollowList`, `NewsFeedRequest`, `NewsCard`, `NewsFeedSections`, `DoddyServerClient.newsFeed` |
| `Packages/DoddyCore/Sources/DoddyCore/DataFlow.swift` | the messaging-server row names Following |
| `DoddyApp/Features/News/FollowingModel.swift`, `FollowingView.swift` | the screen, the add sheet, the edit sheet |
| `DoddyApp/Features/Home/HomeView.swift` | the menu entry and sheet |
| `l10n/pl.json`, `DoddyApp/Resources/Localizable.xcstrings` | 20 Polish lines |
| `Packages/DoddyCore/Sources/DoddyCore/NewsFollowVoice.swift` (+ `VoiceTools`, `ToolCatalog`, `AskFirst`, `CarProfile`, `ConnectionPause`, `ActivityLog`, `ActivityText`) | `follow_news` (ADR-657) |
| `voice-agent/tools.json`, `voice-agent/instructions.md` | the tool and one line; `not_synced` |
| `DoddyApp/Features/Voice/VoiceSessionController.swift`, `FollowingModel.follow` | runs it after the tap, with read-back |
| `backend/src/web/logbook.ts`, `web/src/logbook/catalog.ts`, `web/src/i18n/logbookMessages.ts` | Doddy Web's logbook |

## Executed (Linux, this session, 28 Oct 2026)

| Check | Result |
|---|---|
| Server `npm test` (TypeScript build + `node --test`, real PostgreSQL 16 started locally) | **403 tests, 0 failures** (3 new: pictures from feeds, `buildFeed` rules, the endpoint against Postgres) |
| `swift test` DoddyCore (Swift 6.2.3 downloaded into this session) | **2,175 tests, 0 failures** (9 new in `NewsFollowingTests`) |
| `scripts/typecheck_app_logic.sh` | PASS, 34 files (the new app files are SwiftUI and not among them) |
| `tools/build_strings_catalog.py --check` | PASS; Polish 2,477 of 2,559 strings |
| `scripts/ci.sh --core-only` after ADR-657 (28 Oct) | 35 of 37 steps PASS on the first run, iOS app NOT RUN (no Xcode). The two failures were this session's environment, both run again and passed: the messaging server's tests found its local Postgres stopped (restarted: **403 of 403 pass**), and the web end-to-end run looked for a Chromium build this container doesn't have (with `PLAYWRIGHT_CHROMIUM=/opt/pw-browsers/chromium`: **16 passed, 4 skipped**, the Logbook tests included) |
| Voice agent spec check | PASS, 101 tools (`follow_news` `not_synced`) |
| Backend `npm test`, web `npm test` and type-check | 435 of 435; 101 of 101; PASS |

## Not run

- **The SwiftUI (`FollowingView`, `FollowingModel`) and the Home change were not compiled here** (no Xcode); they compiled later in #195's hosted Mac job (7 Nov note above). They still need a run on a device, in Polish and English, light and dark, at the largest text size (the ••• menu gained a row in its second section; the first section is unchanged, which the hosted UI tests check).
- **No live feed was fetched.** The server tests use fake feeds. Which publishers put pictures in their feeds (and how many cards therefore show one) is unknown until the server runs against the real catalog.
- **No real GNews call.**

## Privacy and the constitution

- Sent to Doddy's messaging server: the follows (topic ids, or the person's own name and words), the language, once per open or pull-to-refresh. Kept there: nothing of the person's (R-PRIV). The "What leaves this iPhone" page says so (`DataFlow.swift`).
- Sent to GNews: the person's own words, only when the server has a key, as for Daily news.
- Sent to publishers: a request for each picture shown, from the iPhone, as any browser would.
- Model output: none. Tool content (the feeds) is data and is shown as the publisher's, never as Doddy's words (R-TOOLS).
- "Saved" is said only after `MemoryRepository.save` returned (R-MEM).

## Preview (28 Oct 2026)

An HTML mock-up of the three screens (Following, the "śledź CPK" card, the Follow sheet), built from the SwiftUI layout and the colour tokens, with the cards made by `buildFeed` from the four live Poland feeds that day. **A mock-up, not a screenshot of the app.** What the live feeds showed:

- 24 cards, all of them with a picture (the four feeds carry one on every item).
- The publisher's name is the feed's own title ("Najnowsze wiadomości - TVN24", "Polsat News - Wiadomości", "www.rp.pl"), so it is long and gets cut. A fixed short name per catalog feed would fix it; not done yet.
- "Poland" carries world stories too (TVN24's "najnowsze" feed has everything).

## Decisions for the owner

1. ~~Is Home › ••• the right door?~~ **Decided, owner, 28 Oct 2026: "W menu".** Following stays in Home's ••• menu, the fourth row of its second section; no Home card, no tab.
2. ~~Should a follow by voice exist?~~ **Decided, owner, 28 Oct 2026: "Ma umieć tak".** Built as `follow_news` (ADR-657, below).
3. The privacy policy page (`site/`) needs one line about Following; not changed here.

## Following by voice (ADR-657)

"Śledź CPK", "chcę śledzić wiadomości o Orlenie", "follow sport". One voice tool, `follow_news`:

1. Doddy says one line ("Stuknij Śledź na ekranie, jeśli mam to śledzić.") and calls the tool with either `topic` (one of the ten catalog ids) or `name` and, only if different, `words`. "Śledź CPK" is `name: "CPK"`; the name is then the word looked for.
2. DoddyCore checks the arguments the way the server would (`NewsFollowAsk.parse`): an unknown topic, a missing name, a one-letter word or a name over 60 characters is `invalid`, and no card shows.
3. The app shows a card: **Follow this?** with "“CPK”", "Stories with: CPK", "Shown in Following, in Home's menu", and a **Follow** button (ASK-01: a change, so a tap).
4. On the tap, `FollowingModel.follow` adds it, writes the list to this iPhone's defaults and reads it back. Only then is the reply `added`. Already followed (Poland, asked again, is the default follow, not a second one), ten followed, or a write that didn't read back is `failed`, and nothing changes.
5. The tool returns no stories. Doddy says where they are (Home's menu, Following); for news now it still uses `news_search`.

Also: What Doddy did gets a row ("Follow in Following" / "Śledź w Śledzonych", app "Following" / "Śledzone"; since 13 Nov 2026 "Add to radar" / „Dodaj do radaru”, app "On my radar" / „Na radarze”); it stays outside Pause all, like the stopwatch; in the car it is refused (it needs a tap); Doddy Web's logbook knows the tool.

**On the live ElevenLabs agent since 28 Oct 2026** (owner: "Dodaj"): `tool_5201m626991zfjgrw2b4mhsyqzcb`, saved as `agtvrsn_7301m626bt8mfm1bw7qav8gtqyzx`, rollback `agtvrsn_4401m5y51ygzfbdbapvpnfb6vfnh`; the record is in `voice-agent/README.md`. The prompt was not changed. **Until an app built from the default branch after 7 Nov (#195) is on the iPhone, the voice may offer it and the app answers that it isn't supported.**

The ask card is in English only, like every other ask card (the cards' words are not in the string catalogs yet).

## Next

The hosted Mac build (ADR-497) to compile the SwiftUI, then one run on a device with the real server to see how many publishers carry pictures. Then say "śledź CPK" to the live agent with that build.
