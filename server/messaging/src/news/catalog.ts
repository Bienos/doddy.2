// Curated topics. Each is a set of publisher RSS feeds (checked reachable on 2026-10-10; crypto and
// Europe re-checked and extended on 2026-11-10, decision 2026-11-10-radar-alerts).
// Doddy only sends a headline, a one-line description and the link to the publisher.

export interface CatalogFeed {
  url: string;
  /** The publisher's short name, shown on cards and as the follow's source ("CoinDesk", not the feed's long title). */
  name: string;
}

export interface CatalogTopic {
  id: string;
  label: { en: string; pl: string };
  feeds: CatalogFeed[];
}

const feed = (url: string, name: string): CatalogFeed => ({ url, name });

export const CATALOG: CatalogTopic[] = [
  { id: "world", label: { en: "World", pl: "Świat" }, feeds: [
    feed("https://feeds.bbci.co.uk/news/world/rss.xml", "BBC News"), feed("https://www.theguardian.com/world/rss", "The Guardian"),
    feed("https://feeds.npr.org/1004/rss.xml", "NPR")] },
  { id: "poland", label: { en: "Poland", pl: "Polska" }, feeds: [
    feed("https://tvn24.pl/najnowsze.xml", "TVN24"), feed("https://www.polsatnews.pl/rss/wszystkie.xml", "Polsat News"),
    feed("https://notesfrompoland.com/feed/", "Notes from Poland"), feed("https://www.rp.pl/rss_main", "Rzeczpospolita")] },
  { id: "europe", label: { en: "Europe", pl: "Europa" }, feeds: [
    feed("https://www.theguardian.com/world/europe-news/rss", "The Guardian"),
    feed("https://feeds.bbci.co.uk/news/world/europe/rss.xml", "BBC News")] },
  { id: "technology", label: { en: "Technology", pl: "Technologia" }, feeds: [
    feed("https://feeds.bbci.co.uk/news/technology/rss.xml", "BBC News"), feed("https://techcrunch.com/feed/", "TechCrunch"),
    feed("https://www.theverge.com/rss/index.xml", "The Verge"), feed("https://feeds.arstechnica.com/arstechnica/index", "Ars Technica"),
    feed("https://spidersweb.pl/feed", "Spider's Web")] },
  { id: "ai", label: { en: "AI", pl: "Sztuczna inteligencja" }, feeds: [
    feed("https://techcrunch.com/category/artificial-intelligence/feed/", "TechCrunch"),
    feed("https://www.theverge.com/rss/ai-artificial-intelligence/index.xml", "The Verge")] },
  { id: "business", label: { en: "Business & markets", pl: "Biznes i rynki" }, feeds: [
    feed("https://feeds.bbci.co.uk/news/business/rss.xml", "BBC News"), feed("https://www.theguardian.com/business/rss", "The Guardian"),
    feed("https://www.bankier.pl/rss/wiadomosci.xml", "Bankier.pl"), feed("https://www.money.pl/rss/", "money.pl")] },
  { id: "science", label: { en: "Science", pl: "Nauka" }, feeds: [
    feed("https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", "BBC News"), feed("https://www.theguardian.com/science/rss", "The Guardian"),
    feed("https://www.sciencedaily.com/rss/top/science.xml", "ScienceDaily")] },
  { id: "health", label: { en: "Health", pl: "Zdrowie" }, feeds: [
    feed("https://feeds.bbci.co.uk/news/health/rss.xml", "BBC News"), feed("https://www.theguardian.com/society/health/rss", "The Guardian")] },
  { id: "sport", label: { en: "Sport", pl: "Sport" }, feeds: [
    feed("https://feeds.bbci.co.uk/sport/rss.xml", "BBC Sport"), feed("https://www.theguardian.com/sport/rss", "The Guardian"),
    feed("https://www.sport.pl/pub/rss/sport.xml", "Sport.pl")] },
  // Until 10 Nov 2026 only CoinDesk, at an address that answers with a redirect. Each feed below was fetched
  // and parsed on 10 Nov 2026 (20 to 38 dated stories, all within two days); Bitcoin.pl is in Polish.
  { id: "crypto", label: { en: "Crypto", pl: "Kryptowaluty" }, feeds: [
    feed("https://www.coindesk.com/arc/outboundfeeds/rss", "CoinDesk"), feed("https://cointelegraph.com/rss", "Cointelegraph"),
    feed("https://decrypt.co/feed", "Decrypt"), feed("https://www.theblock.co/rss.xml", "The Block"),
    feed("https://bitcoin.pl/feed/", "Bitcoin.pl")] },
];

export const catalogById = new Map(CATALOG.map((t) => [t.id, t]));

/** Every catalog feed once, for looking up a person's own words when the server has no news search. */
export const ALL_CATALOG_FEEDS: CatalogFeed[] = [...new Map(CATALOG.flatMap((t) => t.feeds).map((f) => [f.url, f])).values()];
