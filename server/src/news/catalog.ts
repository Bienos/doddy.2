// Curated topics. Each is a set of publisher RSS feeds (checked reachable on 2026-10-10).
// Doddy only sends a headline, a one-line description and the link to the publisher.

export interface CatalogTopic {
  id: string;
  label: { en: string; pl: string };
  feeds: string[];
}

export const CATALOG: CatalogTopic[] = [
  { id: "world", label: { en: "World", pl: "Świat" }, feeds: [
    "https://feeds.bbci.co.uk/news/world/rss.xml", "https://www.theguardian.com/world/rss", "https://feeds.npr.org/1004/rss.xml"] },
  { id: "poland", label: { en: "Poland", pl: "Polska" }, feeds: [
    "https://tvn24.pl/najnowsze.xml", "https://www.polsatnews.pl/rss/wszystkie.xml", "https://notesfrompoland.com/feed/", "https://www.rp.pl/rss_main"] },
  { id: "europe", label: { en: "Europe", pl: "Europa" }, feeds: ["https://www.theguardian.com/world/europe-news/rss"] },
  { id: "technology", label: { en: "Technology", pl: "Technologia" }, feeds: [
    "https://feeds.bbci.co.uk/news/technology/rss.xml", "https://techcrunch.com/feed/", "https://www.theverge.com/rss/index.xml",
    "https://feeds.arstechnica.com/arstechnica/index", "https://spidersweb.pl/feed"] },
  { id: "ai", label: { en: "AI", pl: "Sztuczna inteligencja" }, feeds: [
    "https://techcrunch.com/category/artificial-intelligence/feed/", "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml"] },
  { id: "business", label: { en: "Business & markets", pl: "Biznes i rynki" }, feeds: [
    "https://feeds.bbci.co.uk/news/business/rss.xml", "https://www.theguardian.com/business/rss",
    "https://www.bankier.pl/rss/wiadomosci.xml", "https://www.money.pl/rss/"] },
  { id: "science", label: { en: "Science", pl: "Nauka" }, feeds: [
    "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", "https://www.theguardian.com/science/rss",
    "https://www.sciencedaily.com/rss/top/science.xml"] },
  { id: "health", label: { en: "Health", pl: "Zdrowie" }, feeds: [
    "https://feeds.bbci.co.uk/news/health/rss.xml", "https://www.theguardian.com/society/health/rss"] },
  { id: "sport", label: { en: "Sport", pl: "Sport" }, feeds: [
    "https://feeds.bbci.co.uk/sport/rss.xml", "https://www.theguardian.com/sport/rss", "https://www.sport.pl/pub/rss/sport.xml"] },
  { id: "crypto", label: { en: "Crypto", pl: "Kryptowaluty" }, feeds: ["https://www.coindesk.com/arc/outboundfeeds/rss/"] },
];

export const catalogById = new Map(CATALOG.map((t) => [t.id, t]));
