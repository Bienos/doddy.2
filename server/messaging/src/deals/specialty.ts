// Which shops a leaflet search asks (ADR-667). Grocery chains are asked for everything. A shop that sells one kind
// of thing (pets, shoes, books, home) is asked only when an item is that kind of thing, so "masło" never sends a
// request to a shoe shop. E.Leclerc (about 45 hypermarkets) is asked only when the person picks it, because its
// image leaflets cost a screening on every search. All of this is code: no model decides which shop is asked.
import type { Chain } from "./types.js";

export type ShopKind = "pets" | "shoes" | "books" | "home";

/** The kind each specialty shop sells. */
export const SPECIALTY: Readonly<Partial<Record<Chain, ShopKind>>> = {
  maxizoo: "pets",
  ccc: "shoes",
  taniaksiazka: "books",
  komfort: "home",
};

/** Read only when asked for by name (or picked on the app's screen); never by default. */
export const ON_REQUEST: readonly Chain[] = ["leclerc"];

/** Lower case, Polish letters folded ("Łaciate" → "laciate"), so the word lists below can be plain ASCII. */
export function fold(text: string): string {
  return text.toLowerCase().replace(/ł/g, "l").normalize("NFD").replace(/\p{M}+/gu, "");
}

// Word starts, matched at the start of a word in the folded item. Kept short and concrete: a missed item only means
// the specialty shop isn't asked; a wrong hit only costs one request to a shop with no match.
const WORDS: Record<ShopKind, RegExp> = {
  pets: /\b(karm(a|y|e|ie|ami)?\b|przysmak|zwirek|zwirk|kuwet|smycz|obroz|legowisk|drapak|akwari|terrari|klatk[aie] dla|dla (psa|psow|szczeniat|kota|kotow|kociat|chomik|krolik|swink|papug|ptak|rybek|gryzoni)|pies\b|psa\b|kot\b|kota\b|chomik|papug)/,
  shoes: /\b(but\b|buty|butow|obuwi|sneakers|trampk|tenisowk|kozak|kozaki|botk|sandal|klapk|japonk|kapc|polbut|czolenk|szpilk|mokasyn|balerin|sniegow|kalosz|glan|workery|espadryl|adidasy)/,
  books: /\b(ksiazk|ksiazek|powiesc|powiesci|kryminal|thriller|komiks|mang[aiy]\b|poradnik|lektur|bajk|kolorowank|audiobook|ebook|slownik|atlas|reportaz|biografi|fantasy|romans)/,
  home: /\b(panel|podlog|wykladzin|dywan|chodnik|drzwi|plytk|kafelk|tapet|firan|zaslon|rolet|karnisz|listw|wycieraczk|laminat|wylozyn|klamk|oscieznic)/,
};

/** The kinds of the person's items ("karma dla kota" → pets). */
export function itemKinds(items: readonly string[]): Set<ShopKind> {
  const kinds = new Set<ShopKind>();
  for (const item of items) {
    const f = fold(item);
    for (const [kind, re] of Object.entries(WORDS) as [ShopKind, RegExp][]) if (re.test(f)) kinds.add(kind);
  }
  return kinds;
}

/** The chains asked when the person named none: every chain Doddy reads but the on-request ones, plus the
 * link-only chains' rows are left to the caller (as before). */
export function defaultChains(readChains: readonly Chain[]): Chain[] {
  return readChains.filter((c) => !ON_REQUEST.includes(c));
}

/**
 * The chains to read for these items, from those asked: a specialty shop is kept when an item is its kind, or when
 * every read chain asked is a specialty shop (the person asked that shop on purpose). The rest of the order is kept.
 */
export function chainsToRead(asked: readonly Chain[], items: readonly string[], isRead: (c: Chain) => boolean): Chain[] {
  const kinds = itemKinds(items);
  const read = asked.filter(isRead);
  const onlySpecialty = read.length > 0 && read.every((c) => SPECIALTY[c] !== undefined);
  return asked.filter((c) => {
    const kind = SPECIALTY[c];
    return kind === undefined || onlySpecialty || kinds.has(kind);
  });
}
