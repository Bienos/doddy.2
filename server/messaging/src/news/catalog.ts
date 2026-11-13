// Curated topics. Each is a set of publisher RSS feeds (checked reachable on 2026-10-10; crypto and
// Europe re-checked and extended on 2026-11-10, decision 2026-11-10-radar-alerts; every topic extended
// with Polish publishers first, and more international ones, on 2026-11-13, decision
// 2026-11-13-news-more-sources). Doddy only sends a headline, a one-line description and the link to the
// publisher. Every feed added on 13 Nov 2026 was fetched from the build machine with the server's own
// user agent, parsed with parseFeed (dated stories within the last two days) and checked against the
// host's robots.txt; the decision lists the ones left out and why.

export interface CatalogFeed {
  url: string;
  /** The publisher's short name, shown on cards and as the follow's source ("CoinDesk", not the feed's long title). */
  name: string;
  /** The language the feed is written in. A reader's own language is preferred a little when stories are ranked. */
  lang: "pl" | "en";
}

export interface CatalogTopic {
  id: string;
  label: { en: string; pl: string };
  /** The shelf of the app's Sources list the topic sits on (13 Nov 2026), one of CATALOG_GROUPS. */
  group: CatalogGroupId;
  feeds: CatalogFeed[];
}

/** The shelves of the app's Sources list, in the order shown (owner, 13 Nov 2026: the person must see which
 * publishers Doddy can read before choosing). Display only: nothing is fetched or matched by group. */
export const CATALOG_GROUPS = {
  news: { en: "News", pl: "Wiadomości" },
  tech: { en: "Technology and AI", pl: "Technologia i AI" },
  money: { en: "Money", pl: "Pieniądze" },
  life: { en: "Science, health and sport", pl: "Nauka, zdrowie i sport" },
} as const;

export type CatalogGroupId = keyof typeof CATALOG_GROUPS;

const pl = (url: string, name: string): CatalogFeed => ({ url, name, lang: "pl" });
const en = (url: string, name: string): CatalogFeed => ({ url, name, lang: "en" });

export const CATALOG: CatalogTopic[] = [
  { id: "world", label: { en: "World", pl: "Świat" }, group: "news", feeds: [
    en("https://feeds.bbci.co.uk/news/world/rss.xml", "BBC News"), en("https://www.theguardian.com/world/rss", "The Guardian"),
    en("https://feeds.npr.org/1004/rss.xml", "NPR"),
    pl("https://www.rmf24.pl/fakty/swiat/feed", "RMF24"), pl("https://tvn24.pl/swiat.xml", "TVN24"),
    pl("https://www.polsatnews.pl/rss/swiat.xml", "Polsat News"),
    en("https://rss.dw.com/rdf/rss-en-world", "Deutsche Welle"), en("https://www.aljazeera.com/xml/rss/all.xml", "Al Jazeera"),
    en("https://www.france24.com/en/rss", "France 24")] },
  // Polsat News's Poland feed, not its everything feed (until 13 Nov 2026), so "Poland" carries fewer world stories.
  { id: "poland", label: { en: "Poland", pl: "Polska" }, group: "news", feeds: [
    pl("https://tvn24.pl/najnowsze.xml", "TVN24"), pl("https://www.polsatnews.pl/rss/polska.xml", "Polsat News"),
    en("https://notesfrompoland.com/feed/", "Notes from Poland"), pl("https://www.rp.pl/rss_main", "Rzeczpospolita"),
    pl("https://www.rmf24.pl/fakty/polska/feed", "RMF24"), pl("https://wiadomosci.onet.pl/.feed", "Onet"),
    pl("https://wydarzenia.interia.pl/feed", "Interia"), pl("https://wiadomosci.wp.pl/rss.xml", "Wirtualna Polska"),
    pl("https://rss.gazeta.pl/pub/rss/gazetawyborcza_kraj.xml", "Gazeta Wyborcza")] },
  { id: "europe", label: { en: "Europe", pl: "Europa" }, group: "news", feeds: [
    en("https://www.theguardian.com/world/europe-news/rss", "The Guardian"),
    en("https://feeds.bbci.co.uk/news/world/europe/rss.xml", "BBC News"),
    pl("https://rss.dw.com/rdf/rss-pol-all", "DW po polsku"), en("https://www.euronews.com/rss", "Euronews"),
    en("https://rss.dw.com/rdf/rss-en-eu", "Deutsche Welle"), en("https://www.france24.com/en/europe/rss", "France 24")] },
  { id: "technology", label: { en: "Technology", pl: "Technologia" }, group: "tech", feeds: [
    en("https://feeds.bbci.co.uk/news/technology/rss.xml", "BBC News"), en("https://techcrunch.com/feed/", "TechCrunch"),
    en("https://www.theverge.com/rss/index.xml", "The Verge"), en("https://feeds.arstechnica.com/arstechnica/index", "Ars Technica"),
    pl("https://spidersweb.pl/feed", "Spider's Web"),
    pl("https://antyweb.pl/feed", "Antyweb"), pl("https://www.chip.pl/feed", "CHIP"),
    pl("https://www.komputerswiat.pl/.feed", "Komputer Świat"), pl("https://www.benchmark.pl/rss/aktualnosci-pliki.xml", "Benchmark.pl"),
    pl("https://tech.wp.pl/rss/aktualnosci", "WP Tech"),
    en("https://www.theguardian.com/technology/rss", "The Guardian"), en("https://www.engadget.com/rss.xml", "Engadget")] },
  { id: "ai", label: { en: "AI", pl: "Sztuczna inteligencja" }, group: "tech", feeds: [
    en("https://techcrunch.com/category/artificial-intelligence/feed/", "TechCrunch"),
    en("https://www.theverge.com/rss/ai-artificial-intelligence/index.xml", "The Verge"),
    en("https://www.theguardian.com/technology/artificialintelligenceai/rss", "The Guardian"),
    en("https://arstechnica.com/ai/feed/", "Ars Technica"),
    en("https://www.technologyreview.com/topic/artificial-intelligence/feed", "MIT Technology Review")] },
  { id: "business", label: { en: "Business & markets", pl: "Biznes i rynki" }, group: "money", feeds: [
    en("https://feeds.bbci.co.uk/news/business/rss.xml", "BBC News"), en("https://www.theguardian.com/business/rss", "The Guardian"),
    pl("https://www.bankier.pl/rss/wiadomosci.xml", "Bankier.pl"), pl("https://www.money.pl/rss/", "money.pl"),
    pl("https://businessinsider.com.pl/.feed", "Business Insider Polska"), pl("https://www.pb.pl/rss/najnowsze.xml", "Puls Biznesu"),
    pl("https://www.parkiet.com/rss_main", "Parkiet"), pl("https://biznes.interia.pl/feed", "Interia"),
    pl("https://tvn24.pl/biznes/najnowsze.xml", "TVN24"), pl("https://www.rmf24.pl/ekonomia/feed", "RMF24"),
    en("https://rss.dw.com/rdf/rss-en-bus", "Deutsche Welle")] },
  { id: "science", label: { en: "Science", pl: "Nauka" }, group: "life", feeds: [
    en("https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", "BBC News"), en("https://www.theguardian.com/science/rss", "The Guardian"),
    en("https://www.sciencedaily.com/rss/top/science.xml", "ScienceDaily"),
    pl("https://naukawpolsce.pl/rss.xml", "Nauka w Polsce"), pl("https://www.rmf24.pl/nauka/feed", "RMF24"),
    en("https://www.nasa.gov/news-release/feed/", "NASA")] },
  { id: "health", label: { en: "Health", pl: "Zdrowie" }, group: "life", feeds: [
    en("https://feeds.bbci.co.uk/news/health/rss.xml", "BBC News"), en("https://www.theguardian.com/society/health/rss", "The Guardian"),
    pl("https://www.medonet.pl/.feed", "Medonet"), pl("https://www.rmf24.pl/zdrowie/feed", "RMF24"),
    en("https://www.euronews.com/rss?level=vertical&name=health", "Euronews"), en("https://feeds.npr.org/1128/rss.xml", "NPR"),
    en("https://www.statnews.com/feed/", "STAT")] },
  { id: "sport", label: { en: "Sport", pl: "Sport" }, group: "life", feeds: [
    en("https://feeds.bbci.co.uk/sport/rss.xml", "BBC Sport"), en("https://www.theguardian.com/sport/rss", "The Guardian"),
    pl("https://www.sport.pl/pub/rss/sport.xml", "Sport.pl"),
    pl("https://przegladsportowy.onet.pl/.feed", "Przegląd Sportowy"), pl("https://sportowefakty.wp.pl/rss.xml", "WP SportoweFakty"),
    pl("https://sport.interia.pl/feed", "Interia"), pl("https://www.polsatsport.pl/rss/wszystkie.xml", "Polsat Sport")] },
  // Until 10 Nov 2026 only CoinDesk, at an address that answers with a redirect. Each feed below was fetched
  // and parsed on 10 Nov 2026 (20 to 38 dated stories, all within two days); Bitcoin.pl is in Polish.
  { id: "crypto", label: { en: "Crypto", pl: "Kryptowaluty" }, group: "money", feeds: [
    en("https://www.coindesk.com/arc/outboundfeeds/rss", "CoinDesk"), en("https://cointelegraph.com/rss", "Cointelegraph"),
    en("https://decrypt.co/feed", "Decrypt"), en("https://www.theblock.co/rss.xml", "The Block"),
    pl("https://bitcoin.pl/feed/", "Bitcoin.pl"), en("https://cryptoslate.com/feed/", "CryptoSlate")] },
];

export const catalogById = new Map(CATALOG.map((t) => [t.id, t]));

/** Every catalog feed once, for looking up a person's own words when the server has no news search. */
export const ALL_CATALOG_FEEDS: CatalogFeed[] = [...new Map(CATALOG.flatMap((t) => t.feeds).map((f) => [f.url, f])).values()];

/** The address a feed is read from, as the app shows it: its host without a leading "www." ("feeds.bbci.co.uk"). */
export function feedDomain(url: string): string {
  return new URL(url).hostname.replace(/^www\./, "");
}

export interface CatalogTopicView {
  id: string;
  label: string;
  /** The publishers' names, once each (since 10 Nov 2026). */
  sources: string[];
  /** Its shelf in the app's Sources list and that shelf's name (13 Nov 2026). */
  group: CatalogGroupId;
  groupLabel: string;
  /** Each publisher once, with the host its feed is read from (13 Nov 2026). */
  publishers: { name: string; domain: string }[];
}

/**
 * `GET /v1/news/catalog`: every topic in the asked language with the publishers that feed it. `group`, `groupLabel`
 * and `publishers` were added on 13 Nov 2026 next to the older fields, which keep their meaning (older apps ignore
 * the new ones). Topics keep the catalog's order; the app shows the shelves in CATALOG_GROUPS order.
 */
export function catalogTopics(lang: "en" | "pl"): CatalogTopicView[] {
  return CATALOG.map((t) => {
    // A publisher with two feeds in one topic is named once, with its first feed's host.
    const publishers: { name: string; domain: string }[] = [];
    for (const f of t.feeds) {
      if (!publishers.some((p) => p.name === f.name)) publishers.push({ name: f.name, domain: feedDomain(f.url) });
    }
    return {
      id: t.id, label: t.label[lang], sources: publishers.map((p) => p.name),
      group: t.group, groupLabel: CATALOG_GROUPS[t.group][lang], publishers,
    };
  });
}
