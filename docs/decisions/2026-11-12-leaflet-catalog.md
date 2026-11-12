# Leaflets are read once for everyone, in the background, and searches answer from what was kept

- **Date:** 2026-11-12
- **Decided by:** owner: "my powinniśmy robić takie dzienne skany, mi się wydaje, oszczędnie, w sensie jako Dodi, tych wszystkich gazetek i dawać to dostęp tych informacji użytkownikom, a nie za każdym razem skanować użytkownikowi przez te wszystkie te gazetki. […] my powinniśmy mieć bazę właśnie taką, i dawać użytkownikom właśnie dostęp" (12 Nov 2026). The details below (which chains, every 6 hours, the caps) are the implementation's proposal.
- **Status:** accepted; built on branch `claude/peaceful-allen-1mh9uq`, off on the server until `DEALS_CATALOG_ENABLED=1` (OWNER_QUEUE 45)
- **Replaces:** nothing. Narrows ADR-609's "every search reads the leaflets on request, nothing is stored" for the catalogued chains.

## Why

Every leaflet search read the chains again, live, within a 25-second budget. The live server's own log lines ("deals searched", read through Render's API on 12 Nov 2026; counts only, no words):

| When (UTC) | Chains | failed | Pages read | Input tokens | Time |
|---|---|---|---|---|---|
| 10 Nov 22:15 | 10 | 9 | 209 | 24,601 | 24.0 s |
| 11 Nov 08:13 | 10 | 7 | 173 | 113,230 | 23.4 s |
| 11 Nov 08:26 | 10 | 6 | 210 | 116,417 | 23.8 s |

So each search cost about as much as reading the leaflets, took the whole budget, and still answered for 1 to 4 chains out of 10. The 3-hour page cache of 11 Nov (`CachingFetcher`) saves the fetches, not the reads: the reader reads only what fits the person's items, so its reads can't be reused for the next person. At scale the cost grows with the number of searches; the leaflets themselves change about twice a week.

## Decision

- **A catalog of the chains' current leaflets** on the messaging server (`src/deals/catalog.ts`, migration `029_leaflet_catalog.sql`). The worker scans each of 11 chains (Biedronka, Lidl, Dino, Aldi, Żabka, Delikatesy Centrum, E.Leclerc, Komfort, Lewiatan, Natura, Action) every `DEALS_CATALOG_EVERY_HOURS` (6). A scan asks the chain's adapter for its leaflets with no items, then sends to the reader every page of image and text leaflets, and the pages that confirm Dino's data, that it hasn't read before, at most `DEALS_CATALOG_MAX_PAGES` (160) a chain a scan.
- **The catalog read** (`readCatalogPage`, `CATALOG_SYSTEM`) is the search reader's prompt with its two item sentences replaced: list every product with a readable price (up to 80) and every range promotion (up to 20). The code parses every price as before; nothing it couldn't parse is kept.
- **Kept:** per chain, the last good snapshot (its leaflets, the chain's own data products and the page reads), and per page its read, keyed by a hash of the leaflet's address and dates and the image's address. A page that fails twice is left until its leaflet changes. A failed or blocked scan keeps the last good snapshot. Page reads unused for 30 days are deleted.
- **A search** answers a catalogued chain from its snapshot when it is at most 8 days old and has a leaflet still running, through `chainOffers`, the same code that builds offers from a live read (refactored out of `runChain`, no behaviour change: the 271 existing leaflet tests pass). An offer whose last day has passed is left out. Rossmann, CCC, Deichmann, Maxi Zoo and zooplus search by the item, so they are read live as before; so is any chain without a usable snapshot, or every chain when the catalog can't be read.
- **Off by default:** `DEALS_CATALOG_ENABLED=0` keeps today's behaviour exactly.

## Consequences

- **Speed and coverage:** a search of the catalogued chains needs no fetch and no page read: the time is the database read (snapshots are held in memory and fetched again only when a scan changed them) and the optional model pick. A chain is complete once its scan has read all its pages, instead of whatever 25 s allowed.
- **Cost:** reads are paid once per page per leaflet, not per search. Estimate, not measured: about 600 pages a leaflet cycle, about 4,000 input and 1,500 output tokens a page on Claude Haiku 5.5 ($0.10 and $0.50 per million), about $0.70 a cycle, about $1.40 a week at two cycles, whatever the number of searches. The first real scan's "leaflet catalog scanned" lines give the real tokens.
- **Freshness:** a new leaflet shows up at the next scan, within about 6 hours. On Render's free plan the worker runs only while the web service is awake, so a scan starts when someone wakes it; until it finishes, searches read live as before.
- **Privacy:** better than before for the catalogued chains: their pages go to Anthropic with the chain's name only, read in the background for everyone; the person's items go only to the pick call. The catalog holds the shops' published leaflets and the reader's reads, nothing about any person and no item anyone asked for (constitution: no new personal data stored).
- **Constitution:** prices still come only from a chain's data or the reader's read of a page, parsed by code (DOD-02); a model proposes, code validates. The catalog changes where the read happens, not who may write a price.
- **Watch:** a page image address that a chain reuses for a different page within the same leaflet dates would serve the old read (the key includes the leaflet's dates, so a new leaflet is a new key). Whole-page reads produce more output tokens than item reads; if a dense page passes 80 products the rest are cut.

## Evidence

- Ran: `npm test` in `server/messaging` against a local disposable Postgres 16: 935/935 (the new `test/dealsCatalog.test.ts`, 17 tests, two of them on the database: a pass scans, keeps and serves a snapshot, a failed rescan keeps the last good one, page-read attempts count).
- Not run: a real scan (no Anthropic key here, and the live agents and services are not changed by agents); no real page has been read with `CATALOG_SYSTEM`, so its recall on a dense page is unmeasured. `scripts/leaflet-eval.mjs` can be pointed at it with a key.
