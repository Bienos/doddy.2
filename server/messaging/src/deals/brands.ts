// Brands and models, and the thing each one is (owner, 13 Nov 2026: "leaflet results — popraw je"; review
// docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md 1.4: "słuchawki Apple" found nothing because a leaflet prints
// "Apple AirPods 4" without the word "słuchawki"). A closed list, written by hand for the Polish market, read by the
// code only: no model decides what a brand is.
//
// What it is used for (service.ts, `makeJudge`):
//   - a query that names a brand or model ("AirPods", "pieluchy Pampers", "kawa Lavazza") matches a leaflet product
//     that names the same brand and is the same thing, even when the product's words leave the thing out ("Apple
//     AirPods 4" for "słuchawki Apple"): match "brand";
//   - the reverse: a query for the thing ("słuchawki", "pieluchy") matches a product named only by its brand or model
//     ("AirPods 4", "Pampers Active Baby 4"): match "brand";
//   - a product of the same thing but another brand ("Słuchawki JBL" for "AirPods") is only ever similar: it goes to
//     `similar`, labelled "podobne, ale nie to samo", never into the item's offers or the basket. A product is never
//     said to be a brand its own name doesn't name.
// Names are matched against the product's words after the matcher's normalising (lower case, ł → l, accents off,
// digits apart): the same word, or the same stem of a word at least as long as the name ("Pampersy", "Lavazzy",
// "Milki"), never a shorter word or a shared start ("milk" is not Milka, "legowisko" is not Lego). Inflections whose
// stem moves ("Żywiec" → "Żywca") are listed as names of their own.
import { CATEGORIES, categoryMatch, type Category } from "./categories.js";
import { normalize, stem } from "./match.js";

/** One brand or one model of a brand. `things` are category ids (categories.ts); empty when the brand makes many
 * kinds of thing and its name alone doesn't say which (Apple, Kinder, Philips). */
export interface Mark {
  id: string;
  /** The brand this mark belongs to: its own id for a brand, the maker's for a model (AirPods → apple). */
  brand: string;
  names: readonly string[];
  things: readonly string[];
}

// [id, brand ("" = the mark is the brand), names ("|"), things ("|", category ids; "" = several)]
type Row = [string, string, string, string];

const ROWS: Row[] = [
  // ----- electronics -----
  ["apple", "", "apple", ""],
  ["airpods", "apple", "airpods|air pods", "headphones"],
  ["iphone", "apple", "iphone", "phones"],
  ["ipad", "apple", "ipad", "tablets"],
  ["macbook", "apple", "macbook", "laptops"],
  ["apple_watch", "apple", "apple watch", "smartwatches"],
  ["samsung", "", "samsung", ""],
  ["galaxy_buds", "samsung", "galaxy buds", "headphones"],
  ["galaxy_tab", "samsung", "galaxy tab", "tablets"],
  ["galaxy_watch", "samsung", "galaxy watch", "smartwatches"],
  ["galaxy", "samsung", "galaxy", "phones"],
  ["xiaomi", "", "xiaomi", ""],
  ["redmi_buds", "xiaomi", "redmi buds", "headphones"],
  ["redmi", "xiaomi", "redmi", "phones"],
  ["mi_band", "xiaomi", "mi band|smart band", "smartwatches"],
  ["jbl", "", "jbl", "headphones|speakers"],
  ["sony", "", "sony", ""],
  ["playstation", "sony", "playstation|ps 5|ps 4|dualsense", "consoles"],
  ["nintendo", "", "nintendo|nintendo switch", "consoles"],
  ["xbox", "", "xbox", "consoles"],
  ["huawei", "", "huawei", ""],
  ["motorola", "", "motorola", "phones"],
  ["philips", "", "philips", ""],
  ["sonicare", "philips", "sonicare", "toothbrush"],
  ["oneblade", "philips", "oneblade|one blade", "electric_shaver"],
  ["braun", "", "braun", ""],
  ["oral_b", "", "oral b", "toothbrush|toothpaste"],
  ["bosch", "", "bosch", ""],
  ["tefal", "", "tefal", ""],
  ["delonghi", "", "delonghi|de longhi", "coffee_machine"],
  ["krups", "", "krups", "coffee_machine"],
  ["makita", "", "makita", "tools"],
  ["black_decker", "", "black decker|black and decker", "tools"],
  ["parkside", "", "parkside", "tools"],
  // ----- toys -----
  ["lego", "", "lego", "blocks"],
  ["duplo", "lego", "duplo", "blocks"],
  ["cobi", "", "cobi", "blocks"],
  ["playmobil", "", "playmobil", "toys"],
  ["barbie", "", "barbie", "dolls"],
  ["hot_wheels", "", "hot wheels", "toy_cars"],
  ["matchbox", "", "matchbox", "toy_cars"],
  // ----- sweets and snacks -----
  ["kinder", "", "kinder", ""],
  ["kinder_bueno", "kinder", "kinder bueno|kinder country|kinder maxi|kinder delice", "bars"],
  ["kinder_surprise", "kinder", "kinder niespodzianka|kinder joy|kinder surprise", "sweets"],
  ["kinder_chocolate", "kinder", "kinder czekolada|kinder chocolate", "chocolate"],
  ["milka", "", "milka", "chocolate"],
  ["wedel", "", "wedel|e wedel", ""],
  ["ptasie_mleczko", "wedel", "ptasie mleczko", "sweets"],
  ["wawel", "", "wawel", ""],
  ["prince_polo", "", "prince polo", "bars"],
  ["grzeski", "", "grzeski", "bars"],
  ["princessa", "", "princessa", "bars"],
  ["snickers", "", "snickers", "bars"],
  ["mars", "", "mars", "bars"],
  ["twix", "", "twix", "bars"],
  ["bounty", "", "bounty", "bars"],
  ["kit_kat", "", "kit kat|kitkat", "bars"],
  ["nutella", "", "nutella", "spread_sweet"],
  ["haribo", "", "haribo", "sweets"],
  ["lays", "", "lays|lay s", "crisps"],
  ["pringles", "", "pringles", "crisps"],
  ["crunchips", "", "crunchips", "crisps"],
  // ----- drinks -----
  ["coca_cola", "", "coca cola|coca-cola", "soda"],
  ["pepsi", "", "pepsi", "soda"],
  ["fanta", "", "fanta", "soda"],
  ["sprite", "", "sprite", "soda"],
  ["tymbark", "", "tymbark", "juice"],
  ["kubus", "", "kubus", "juice"],
  ["cappy", "", "cappy", "juice"],
  ["hortex", "", "hortex", ""],
  ["red_bull", "", "red bull", "energy"],
  ["monster", "", "monster energy", "energy"],
  ["zywiec_zdroj", "", "zywiec zdroj|zywca zdroj", "water"],
  ["cisowianka", "", "cisowianka", "water"],
  ["naleczowianka", "", "naleczowianka", "water"],
  ["muszynianka", "", "muszynianka", "water"],
  ["kropla_beskidu", "", "kropla beskidu", "water"],
  ["zywiec", "", "zywiec|zywca|zywcem|zywcu", "beer"],
  ["tyskie", "", "tyskie", "beer"],
  ["lech", "", "lech", "beer"],
  ["okocim", "", "okocim", "beer"],
  ["warka", "", "warka", "beer"],
  ["heineken", "", "heineken", "beer"],
  ["carlsberg", "", "carlsberg", "beer"],
  ["lavazza", "", "lavazza", "coffee"],
  ["jacobs", "", "jacobs", "coffee"],
  ["tchibo", "", "tchibo", "coffee"],
  ["segafredo", "", "segafredo", "coffee"],
  ["dallmayr", "", "dallmayr", "coffee"],
  ["woseba", "", "woseba", "coffee"],
  ["nescafe", "", "nescafe", "coffee_instant"],
  ["dolce_gusto", "nescafe", "dolce gusto", "coffee_capsules"],
  ["nespresso", "", "nespresso", "coffee_capsules"],
  ["lipton", "", "lipton", "tea"],
  ["saga", "", "saga", "tea"],
  ["minutka", "", "minutka", "tea"],
  ["teekanne", "", "teekanne", "tea"],
  ["dilmah", "", "dilmah", "tea"],
  // ----- dairy and pantry -----
  ["laciate", "", "laciate", "butter|milk"],
  ["danio", "", "danio", "yoghurt_fruit"],
  ["activia", "", "activia", "yoghurt"],
  ["actimel", "", "actimel", "yoghurt_drink"],
  ["bakoma", "", "bakoma", "yoghurt"],
  ["hochland", "", "hochland", "cheese"],
  ["almette", "", "almette", "cheese_white"],
  ["heinz", "", "heinz", "sauces"],
  ["pudliszki", "", "pudliszki", "sauces"],
  ["kotlin", "", "kotlin", "sauces"],
  ["hellmanns", "", "hellmanns|hellmann s", "sauces"],
  ["winiary", "", "winiary", ""],
  ["knorr", "", "knorr", ""],
  ["kamis", "", "kamis", "spices"],
  ["prymat", "", "prymat", "spices"],
  ["lubella", "", "lubella", "pasta"],
  ["barilla", "", "barilla", "pasta"],
  ["cini_minis", "", "cini minis", "cereal"],
  ["kelloggs", "", "kelloggs|kellogg s", "cereal"],
  ["dr_oetker", "", "dr oetker", ""],
  ["guseppe", "dr_oetker", "guseppe", "pizza"],
  // ----- household -----
  ["fairy", "", "fairy", "dish_liquid"],
  ["ludwik", "", "ludwik", "dish_liquid"],
  ["finish", "", "finish", "dishwasher"],
  ["somat", "", "somat", "dishwasher"],
  ["persil", "", "persil", "laundry"],
  ["ariel", "", "ariel", "laundry"],
  ["vizir", "", "vizir", "laundry"],
  ["bryza", "", "bryza", "laundry"],
  ["dosia", "", "dosia", "laundry"],
  ["vanish", "", "vanish", "stain"],
  ["lenor", "", "lenor", "softener"],
  ["coccolino", "", "coccolino", "softener"],
  ["silan", "", "silan", "softener"],
  ["domestos", "", "domestos", "toilet"],
  ["bref", "", "bref", "toilet"],
  ["cif", "", "cif", "cleaner"],
  ["ajax", "", "ajax", "cleaner"],
  ["mr_muscle", "", "mr muscle", "cleaner"],
  ["velvet", "", "velvet", "toilet_paper"],
  ["regina", "", "regina", "toilet_paper|paper_towels"],
  ["foxy", "", "foxy", "toilet_paper|paper_towels"],
  ["duracell", "", "duracell", "batteries"],
  ["energizer", "", "energizer", "batteries"],
  ["varta", "", "varta", "batteries"],
  ["air_wick", "", "air wick", "air"],
  ["glade", "", "glade", "air"],
  // ----- cosmetics -----
  ["head_shoulders", "", "head shoulders|head and shoulders", "shampoo"],
  ["pantene", "", "pantene", "shampoo|conditioner"],
  ["elseve", "", "elseve|elvital", "shampoo|conditioner"],
  ["schauma", "", "schauma", "shampoo"],
  ["colgate", "", "colgate", "toothpaste|toothbrush"],
  ["sensodyne", "", "sensodyne", "toothpaste"],
  ["blend_a_med", "", "blend a med", "toothpaste"],
  ["aquafresh", "", "aquafresh", "toothpaste"],
  ["elmex", "", "elmex", "toothpaste"],
  ["listerine", "", "listerine", "mouthwash"],
  ["gillette", "", "gillette", "shaving"],
  ["wilkinson", "", "wilkinson", "shaving"],
  ["always", "", "always", "pads"],
  ["tampax", "", "tampax", "pads"],
  ["rexona", "", "rexona", "deodorant"],
  ["old_spice", "", "old spice", "deodorant"],
  ["palmolive", "", "palmolive", "soap|shower"],
  // ----- baby -----
  ["pampers", "", "pampers", "nappies"],
  ["huggies", "", "huggies", "nappies"],
  ["dada", "", "dada", "nappies"],
  ["lupilu", "", "lupilu", "nappies"],
  ["toujours", "", "toujours", "nappies"],
  ["bebiko", "", "bebiko", "baby_milk"],
  ["bebilon", "", "bebilon", "baby_milk"],
  ["nan_optipro", "", "nan optipro|nan expertpro", "baby_milk"],
  ["hipp", "", "hipp", "baby_food"],
  ["gerber", "", "gerber", "baby_food"],
  ["bobovita", "", "bobovita", "baby_food"],
  // ----- pets -----
  ["whiskas", "", "whiskas", "cat_food"],
  ["felix", "", "felix", "cat_food"],
  ["sheba", "", "sheba", "cat_food"],
  ["kitekat", "", "kitekat", "cat_food"],
  ["pedigree", "", "pedigree", "dog_food"],
  ["chappi", "", "chappi", "dog_food"],
  ["cesar", "", "cesar", "dog_food"],
  ["purina", "", "purina", "pet_food"],
  ["friskies", "", "friskies", "pet_food"],
];

interface Token { raw: string; stem: string }
interface CompiledMark extends Mark { phrases: Token[][] }

const tokenize = (text: string): Token[] => normalize(text).split(" ").filter(Boolean).map((raw) => ({ raw, stem: stem(raw) }));

const byId = new Map(CATEGORIES.map((c) => [c.id, c]));

export const MARKS: readonly CompiledMark[] = ROWS.map(([id, brand, names, things]) => ({
  id, brand: brand || id, names: names.split("|"), things: things ? things.split("|") : [],
  phrases: names.split("|").map(tokenize).filter((p) => p.length > 0),
}));

/** A product word is a mark's word: the same word, or (letters only) the same stem in a word at least as long. */
function sameWord(name: Token, word: Token): boolean {
  if (name.raw === word.raw) return true;
  if (/\d/.test(name.raw) || /\d/.test(word.raw)) return false;
  return name.stem === word.stem && word.raw.length >= name.raw.length && name.raw.length >= 4;
}

/** Every name by the stem of its first word: a word can only start a name whose first word has its stem (the same word
 * has the same stem), so a product's words are looked up instead of every name tried at every place. */
const BY_FIRST_STEM = new Map<string, { mark: CompiledMark; phrase: Token[] }[]>();
for (const mark of MARKS) {
  for (const phrase of mark.phrases) {
    const key = phrase[0]!.stem;
    const list = BY_FIRST_STEM.get(key) ?? [];
    list.push({ mark, phrase });
    BY_FIRST_STEM.set(key, list);
  }
}

/** The marks a text names, the longest name first; a shorter name inside a longer one found at the same place is left
 * out ("Galaxy Buds" is not also "Galaxy"; "Żywiec Zdrój" is not also "Żywiec"). */
export function marksIn(text: string): Mark[] {
  const words = tokenize(text);
  const found: { mark: CompiledMark; start: number; end: number }[] = [];
  words.forEach((w, i) => {
    for (const { mark, phrase } of BY_FIRST_STEM.get(w.stem) ?? []) {
      if (i + phrase.length <= words.length && phrase.every((t, j) => sameWord(t, words[i + j]!))) {
        found.push({ mark, start: i, end: i + phrase.length });
      }
    }
  });
  if (found.length === 0) return [];
  found.sort((a, b) => (b.end - b.start) - (a.end - a.start) || a.start - b.start);
  const kept: typeof found = [];
  for (const f of found) {
    if (kept.some((k) => k.mark.id === f.mark.id)) continue;
    // A shorter name inside a longer one is the longer one's word, unless both are marks of the same brand (Apple
    // AirPods names Apple and AirPods: both are kept, they agree).
    if (kept.some((k) => f.start >= k.start && f.end <= k.end && k.mark.brand !== f.mark.id && k.mark.id !== f.mark.brand)) continue;
    kept.push(f);
  }
  return kept.map((k) => k.mark);
}

/** The brands a text names (a model names its maker too). */
export const brandsOf = (marks: readonly Mark[]): Set<string> => new Set(marks.map((m) => m.brand));

/** The one thing the marks agree a product is, when a mark of exactly one thing is named (AirPods: headphones). */
export function markThing(marks: readonly Mark[]): Category | undefined {
  const single = marks.filter((m) => m.things.length === 1);
  const ids = new Set(single.map((m) => m.things[0]!));
  return ids.size === 1 ? byId.get([...ids][0]!) : undefined;
}

/** Every thing the marks may be (Kinder: chocolate, bars, sweets): for "is it this kind of thing" only. */
export function markThings(marks: readonly Mark[]): Category[] {
  const out: Category[] = [];
  for (const id of new Set(marks.flatMap((m) => m.things))) { const c = byId.get(id); if (c) out.push(c); }
  return out;
}

/** Below this the words' own category is a guess (a diminutive or a shared start: "tabletki" for "tablet"). */
const STRONG = 0.9;

/**
 * What a product is: its own words when they say it clearly ("Słuchawki …", "Ciastka Milka"), else the one thing its
 * brand or model is ("AirPods 4": headphones; "Finish tabletki": dishwasher tablets), else a weak guess from its words.
 */
export function thingOf(text: string, marks: readonly Mark[] = marksIn(text), words = categoryMatch(text)):
  { thing?: Category; from?: "words" | "mark" } {
  if (words && words.quality >= STRONG) return { thing: words.category, from: "words" };
  const mark = markThing(marks);
  if (mark) return { thing: mark, from: "mark" };
  return words ? { thing: words.category, from: "words" } : {};
}

/** A query's brands and its thing: its words' category, else the thing its brand or model is ("AirPods"). */
export interface QueryMarks {
  brands: Set<string>;
  thing?: Category;
}

export function queryMarks(words: string): QueryMarks {
  const marks = marksIn(words);
  const own = categoryMatch(words);
  return { brands: brandsOf(marks), thing: own?.category ?? markThing(marks) };
}
