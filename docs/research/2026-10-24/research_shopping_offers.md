# Shopping mode: where product prices come from (24 Oct 2026)

Research for the shopping-mode proposal (`docs/strategy/TRYB_ZAKUPOW_2026-10.md`). All sources checked 2026-10-24 by a research agent in this session. Tags: **[V]** read on the source page, or observed from this session's container; **[S]** secondary source; **[I]** inference. Numbers in brackets point to the list at the end. Nothing here is built.

## Main finding

The errand stack as it is (Anthropic `web_search` + `web_fetch`) will cover Polish shops poorly on its own:

- **Bot walls.** From this container's datacenter IP, plain HTTP requests got 403 or a challenge page from Allegro (DataDome), x-kom (Cloudflare), Media Expert, RTV Euro AGD, Decathlon and Zalando; Ceneo returned an interstitial; Amazon.pl an empty 202 [V, observed]. Anthropic's fetcher may fare differently, but Anthropic says its bots "will not attempt to bypass CAPTCHAs" [V, 8].
- **robots.txt.** amazon.pl blocks `Claude-User` and `ClaudeBot`; Ceneo blocks `ClaudeBot` and `Claude-SearchBot` [V, observed].
- **web_fetch** does not render JavaScript and caches unless `use_cache:false` (needs `web_fetch_20260309` or later) [V, 2].

So v1 needs one structured offer source, with fetching the shop's page treated as a check that may fail, not as the only source.

## Sources

| Source | Access | Cost | Terms risk | Poland coverage |
|---|---|---|---|---|
| Allegro REST API | Offer search is gone from the public API (Allegro, 16 Sep 2026: "aktualnie zasobu GET /offers/listing nie ma w publicznym API") [V, 3]. The rules bar showing Allegro offers in competing services and bar scraping (art. 4.1c, 4.1e) [V, 4] | — | High | Largest marketplace, unreachable |
| Allegro Share (affiliate) | Links from a user account; pays about 1.67% as coupons [S, 5] | free | low | Allegro only |
| Ceneo | Partner API only for affiliates, terms unclear [S]; affiliate about 0.5–2.6% CPS or 0.20 zł per click-out; one network's terms forbid price-comparison traffic [S, 6]; scraping blocked | free | medium–high | Best Polish aggregator |
| Amazon.pl | PA-API 5 deprecated, replaced by the Creators API [V, 7]; needs an accepted Associate with qualifying sales [V] | free | medium | Good, but blocks Claude-User |
| Google Shopping through a SERP API | `gl`, `hl`, `google_domain`, price filters [V, 9]; Poland has the Shopping tab [V, 10]; price, seller, link and delivery per offer [V] | SerpApi $25 → $15 → $10 per 1k; SearchApi $4 → $3 per 1k; Serper $1 → $0.30 per 1k (shopping credit cost not stated); DataForSEO $1 per 1k (queued) [V]; Oxylabs about $0.5–1, Bright Data about $1.5 per 1k [S] | medium: Google's terms forbid scraping; Google's suit against SerpApi was dismissed on 20 Jul 2026 [V, 11] | Broad, Allegro included [I] |
| Anthropic web_search | in use | $10 per 1k searches plus tokens [V, 1] | low | index only |
| Anthropic web_fetch | in use | tokens only [V, 2] | low | patchy |
| Brave / Exa / Tavily / Perplexity search APIs | web search | $5 per 1k / $4–7 per 1k / $0.005–0.008 per credit / $1–5 per 1k [V, 12–15] | low | web only |
| Webepartners (Polish affiliate network) | XML product feed: name, price, availability, category, image, link; 3,000+ advertisers [V, 16] | free, CPS | low (licensed) | partial |
| Other programmes | Empik on Tradedoubler; x-kom on Admitad or its own; Media Expert its own; RTV Euro AGD and Zalando PL not found [S] | free | low | per shop |

Commissions: roughly 0.5–3% for electronics, up to about 5–10% for books, fashion and sport; networks keep 20–30% [S, 5, 6, 17].

## What the big assistants do (late 2026)

- **ChatGPT shopping research** (24 Nov 2025): clarifying questions (budget, who for, key features), then top picks with reasons, a side-by-side table and "More like this" [S, 18]. Instant Checkout (Sep 2025) was deprioritised in Mar 2026; merchants handle checkout [S, 19].
- **Google AI Mode:** the Shopping Graph (over 50B listings, about 2B refreshed every hour), price tracking, "buy for me" with Google Pay in the US only through UCP [S, 20].
- **Perplexity:** PayPal Instant Buy since 25 Nov 2025; the retailer stays merchant of record [S, 21].
- **Allegro AI Asystent:** in the app for all users since 7 May 2026; an Allegro app inside ChatGPT since 12 May 2026 [S, 22]. **Klarna** app in ChatGPT since 20 May 2026, sponsored results labelled [S].

What went wrong elsewhere: Amazon "Buy for Me" listed 180+ independent brands without permission and took orders for out-of-stock items [S, 23]; a study of 220 shopping questions found 86% of answers conflicting or wrong, median price error $300 [S, 24]; chatbots gave a price 78.5% of the time even when the page showed none [S, 25].

## Lessons for Doddy

1. At most one to three questions, by voice, one at a time (budget, must-haves, size).
2. Three picks, each with one "why" line and one trade-off; the full table goes in the PDF.
3. Every price with shop, link, delivery cost and a time; never a price that was not seen on the page.
4. Match products by EAN/GTIN or model number (a search on x-kom for "zmywarka" returned an espresso machine [V]).
5. No checkout in v1; hand over the link; label affiliate links and any sponsored results.

## Price tracking and the Omnibus rule

No official Keepa-like tool for Allegro or Ceneo; what exists are scrapers that breach Allegro's rules [S, 26]. Build history from Doddy's own checked observations (URL, price, source, time) [I]. Under art. 4 ust. 2 of the Polish price-information act (since 1 Jan 2023), an advertised discount must show the lowest price of the previous 30 days [S, 27]; UOKiK fined Zalando 30.9M zł and Temu 5.9M zł (Jan 2026, not final) for showing it wrongly [S, 28].

## Recommendation for v1

1. **Find offers:** Google Shopping through one SERP vendor (SearchApi or SerpApi) with `gl=pl`, `hl=pl`, `google_domain=google.pl`.
2. **Check offers:** fetch the top ~10 offer pages (`use_cache:false`) and read schema.org Product/Offer data (price, currency, availability, GTIN) in code; mark each price "verified on the shop page" or "listed on Google Shopping at hh:mm".
3. **v1.1:** affiliate feeds (Webepartners, Tradedoubler, Admitad) for licensed data and revenue.
4. **Skip** the Allegro API, all scraping, and Amazon until there are qualifying sales.

**Decision needed:** today's errand rule drops any price without its page. Either a Google Shopping price may be shown as a lower-trust tier, or it must be dropped.

## Cost per "find me this" (Anthropic prices [V, 29]; token counts [I])

| Step | Cost |
|---|---|
| 5 web searches | $0.050 |
| about 80k tokens of results and pages read by Haiku 5.5 | about $0.010 |
| the pick with Sonnet 5.5 (10k in, 2k out) | about $0.04 (Opus 5.5: about $0.08) |

About **$0.10–0.15** per search, **$0.15–0.45** with retries; with a SERP vendor, 3 shopping calls cost about $0.012 (SearchApi) to $0.045 (SerpApi). At 1,000 searches a month: roughly $100–450. Check that Haiku 5.5 supports the web tools in the Models API before relying on it.

## Sources

1 platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool · 2 …/web-fetch-tool · 3 github.com/allegro/allegro-api/discussions/4584 · 4 developer.allegro.pl/rules · 5 tabletowo.pl/?p=850672 (2023) · 6 affi.io/m/ceneo · 7 affiliate-program.amazon.com/creatorsapi/docs/en-us/paapiv5-deprecation · 8 support.claude.com/en/articles/8896518 · 9 serpapi.com/google-shopping-api; serpapi.com/pricing; searchapi.io/pricing; serper.dev; dataforseo.com/pricing/serp/google-shopping-api · 10 support.google.com/merchants/answer/160637 · 11 serpapi.com/blog/google-v-serpapi-the-court-granted-our-motion-to-dismiss · 12 brave.com/search/api · 13 exa.ai/pricing · 14 docs.tavily.com/documentation/api-credits · 15 docs.perplexity.ai/getting-started/pricing · 16 webepartners.pl · 17 freenance.io (May 2026, low confidence) · 18 openai.com/index/chatgpt-shopping-research (via press coverage) · 19 storyboard18.com (25 Mar 2026) · 20 techcrunch.com/2025/11/13/google-expands-ai-shopping…; bigcommerce.com/articles/ecommerce/google-agentic-checkout · 21 newsroom.paypal-corp.com/2025-11-PayPal-Launches-Agentic-Shopping-with-Perplexity · 22 wiadomoscihandlowe.pl (7 and 12 May 2026) · 23 modernretail.co (6 Jan 2026) · 24 tech.co/news/ai-shopping-assistants-not-ready-holidays (Sep 2026) · 25 arynews.tv (14 Oct 2026) · 26 apify.com/klevio/allegro-ean-price-tracker; brightdata.com/products/insights/price-tracker/allegro · 27 bip.brpo.gov.pl (UOKiK reply, 2023) · 28 android.com.pl/tech/1008425 (Jan 2026) · 29 platform.claude.com/docs/en/about-claude/pricing
