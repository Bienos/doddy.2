// Product categories for matching (ADR-662; research docs/research/2026-10-28/research_deals_better.md §4 #7):
// a closed list, written for Polish leaflets, that tells the code what kind of thing a query or a product name
// is. Matching by words alone takes "masło shea do ciała" for "masło" and "mleko modyfikowane" for "mleko"; with
// a category on both sides the code can tell:
//   - the same category, or either side the family's general word ("kawa", "ser", "pieluchy"): the same thing;
//   - another category in the same family ("masło roślinne" for "masło", "kawa ziarnista" for "kawa mielona"): a
//     similar product, shown apart and labelled, never counted as the item;
//   - another family ("masło shea" for "masło"): not a match at all;
//   - no category on either side: matching by words, as before.
// Written here, by hand, from how the chains name products (not copied from a database). Words are in the code's
// normalised form (lower case, Polish letters folded: ł → l); a word matches a product word the way the matcher
// matches words (the same stem, a diminutive, or a long shared start), and a phrase matches word by word. When
// several match, the longest phrase wins: "masło do ciała" is cosmetics, "masło" alone is butter.
import { normalize, stem, wordSimilarity } from "./match.js";

export type CategoryGroup = "food" | "drink" | "household" | "cosmetics" | "baby" | "pet";

export interface Category {
  id: string;
  /** Categories in one family are alternatives to each other (substitutes); across families they never match. */
  family: string;
  group: CategoryGroup;
  /** The family's general word ("kawa"): it matches every category in the family. */
  general: boolean;
  /** Normalised words and phrases. */
  words: readonly string[];
}

// [id, family, group, words ("|"-separated), general?]
type Row = [string, string, CategoryGroup, string, true?];

const ROWS: Row[] = [
  // ----- dairy and eggs -----
  ["butter", "fats", "food", "maslo|maslo extra|maslo ekstra|maslo osełkowe|maselko"],
  ["ghee", "fats", "food", "maslo klarowane|ghee"],
  ["margarine", "fats", "food", "margaryna|maslo roslinne|tluszcz roslinny|miks tluszczowy|produkt seropodobny do smarowania|smalec roslinny"],
  ["lard", "fats", "food", "smalec"],
  ["milk", "milk", "food", "mleko|mleka|mleko uht|mleko swieze|mleko pasteryzowane|mleko bez laktozy"],
  ["plant_drink", "milk", "food", "napoj roslinny|napoj owsiany|napoj sojowy|napoj migdalowy|napoj ryzowy|mleko owsiane|mleko sojowe|mleko migdalowe"],
  ["condensed_milk", "milk", "food", "mleko zageszczone|mleko w proszku"],
  ["cream", "cream", "food", "smietana|smietanka|smietanka do kawy|smietana do ciast|creme fraiche"],
  ["yoghurt", "yoghurt", "food", "jogurt", true],
  ["yoghurt_natural", "yoghurt", "food", "jogurt naturalny"],
  ["yoghurt_greek", "yoghurt", "food", "jogurt grecki|jogurt typu greckiego|skyr"],
  ["yoghurt_drink", "yoghurt", "food", "jogurt pitny|kefir|maslanka|zsiadle mleko|jogurt do picia"],
  ["yoghurt_fruit", "yoghurt", "food", "jogurt owocowy|jogurt truskawkowy|deser mleczny|serek waniliowy|budyn"],
  ["cheese", "cheese", "food", "ser|sery", true],
  ["cheese_yellow", "cheese", "food", "ser zolty|gouda|edam|ser gouda|ser edamski|ser salami|ser morski|ser podlaski|ser tylzycki|cheddar|ementaler|ser w plastrach"],
  ["cheese_white", "cheese", "food", "twarog|ser bialy|ser twarogowy|serek wiejski|serek ziarnisty|serek homogenizowany|serek kanapkowy|serek smietankowy|ricotta|mascarpone"],
  ["cheese_soft", "cheese", "food", "mozzarella|feta|ser feta|ser sałatkowy|ser salatkowy|camembert|brie|ser plesniowy|gorgonzola|halloumi|ser topiony"],
  ["eggs", "eggs", "food", "jaja|jajka|jajko|jaja kurze"],
  // ----- meat and fish -----
  ["chicken", "meat", "food", "kurczak|filet z kurczaka|piers z kurczaka|udka z kurczaka|udko|podudzie|skrzydelka|cwiartka z kurczaka|tuszka"],
  ["turkey", "meat", "food", "indyk|filet z indyka|piers z indyka"],
  ["duck_goose", "meat", "food", "kaczka|ges|gesina|udko z kaczki|piers z kaczki|tuszka z kaczki"],
  ["pork", "meat", "food", "wieprzowina|schab|karkowka|lopatka wieprzowa|boczek swiezy|zeberka|zeberka wieprzowe|golonka|poledwiczka wieprzowa"],
  ["beef", "meat", "food", "wolowina|rostbef|antrykot|poledwica wolowa|gulasz wolowy"],
  ["minced", "meat", "food", "mieso mielone|mielone|mieso mielone wieprzowe|mieso mielone wolowe"],
  ["meat", "meat", "food", "mieso", true],
  ["ham", "coldcuts", "food", "szynka|szynka konserwowa|szynka gotowana|szynka wedzona|poledwica sopocka|poledwica|baleron"],
  ["sausage", "coldcuts", "food", "kielbasa|kielbaski|kabanosy|parowki|serdelki|kielbasa slaska|kielbasa krakowska|salami|chorizo|mortadela"],
  ["bacon", "coldcuts", "food", "boczek|boczek wedzony|bekon"],
  ["pate", "coldcuts", "food", "pasztet|pasztet drobiowy|smalec ze skwarkami"],
  ["coldcuts", "coldcuts", "food", "wedlina|wedliny", true],
  ["salmon", "fish", "food", "losos|filet z lososia|losos wedzony"],
  ["fish_white", "fish", "food", "dorsz|mintaj|morszczuk|tilapia|panga|filet rybny"],
  ["herring", "fish", "food", "sledz|sledzie|filety sledziowe|matjas"],
  ["mackerel", "fish", "food", "makrela|makrela wedzona|filety z makreli"],
  ["tuna", "fish", "food", "tunczyk|tunczyk w sosie wlasnym|tunczyk w oleju"],
  ["fish_fingers", "fish", "food", "paluszki rybne"],
  ["shrimp", "fish", "food", "krewetki"],
  ["fish", "fish", "food", "ryba|ryby", true],
  // ----- bread and grains -----
  ["bread", "bread", "food", "chleb|chlebek|chleb zytni|chleb pszenny|chleb tostowy|bochenek", true],
  ["rolls", "bread", "food", "bulka|bulki|bulka kajzerka|kajzerka|bagietka|rogal|rogale|croissant|chalka|drozdzowka"],
  ["wraps", "bread", "food", "tortilla|tortille|wrap|pita"],
  ["crispbread", "bread", "food", "pieczywo chrupkie|wafle ryzowe|sucharki"],
  ["cereal", "cereal", "food", "platki sniadaniowe|platki kukurydziane|musli|granola|platki owsiane|owsianka|platki", true],
  ["rice", "pasta_rice", "food", "ryz|ryz bialy|ryz basmati|ryz jasminowy|ryz brazowy|ryz parboiled"],
  ["pasta", "pasta_rice", "food", "makaron|spaghetti|penne|fusilli|tagliatelle|lasagne|kolanka|swiderki|nitki"],
  ["groats", "pasta_rice", "food", "kasza|kasza gryczana|kasza jaglana|kasza jeczmienna|kasza manna|kuskus|bulgur|komosa ryzowa"],
  ["flour", "baking", "food", "maka|maka pszenna|maka zytnia|maka tortowa"],
  ["sugar", "baking", "food", "cukier|cukier bialy|cukier trzcinowy|cukier puder|cukier wanilinowy"],
  ["baking", "baking", "food", "proszek do pieczenia|drozdze|budyn w proszku|galaretka|kisiel"],
  ["salt", "spices", "food", "sol|sol kuchenna|sol morska|sol himalajska"],
  ["spices", "spices", "food", "przyprawa|przyprawy|pieprz|papryka slodka|oregano|bazylia suszona|kostka rosolowa|bulion|vegeta"],
  ["oil", "oil", "food", "olej|olej rzepakowy|olej slonecznikowy|olej kokosowy"],
  ["olive_oil", "oil", "food", "oliwa|oliwa z oliwek|oliwa extra virgin"],
  // ----- hot drinks -----
  ["coffee", "coffee", "food", "kawa|kawy", true],
  ["coffee_ground", "coffee", "food", "kawa mielona"],
  ["coffee_beans", "coffee", "food", "kawa ziarnista|kawa w ziarnach"],
  ["coffee_instant", "coffee", "food", "kawa rozpuszczalna|kawa 3w1|kawa 3 w 1|cappuccino w saszetkach"],
  ["coffee_capsules", "coffee", "food", "kapsulki do kawy|kawa w kapsulkach|kapsulki nespresso|kapsulki dolce gusto"],
  ["tea", "tea", "food", "herbata|herbaty|herbatka", true],
  ["tea_black", "tea", "food", "herbata czarna|earl grey"],
  ["tea_green", "tea", "food", "herbata zielona|zielona herbata"],
  ["tea_fruit", "tea", "food", "herbata owocowa|herbatka owocowa"],
  ["tea_herbal", "tea", "food", "herbata ziolowa|herbatka ziolowa|mieta|rumianek|melisa"],
  ["cocoa", "tea", "food", "kakao|czekolada do picia"],
  // ----- sweets and snacks -----
  ["chocolate", "sweets", "food", "czekolada|czekolady|czekolada mleczna|czekolada gorzka|czekolada biala"],
  ["bars", "sweets", "food", "baton|batony|batonik|batoniki"],
  ["biscuits", "sweets", "food", "ciastka|ciasteczka|herbatniki|biszkopty|wafle|wafelki|pierniki|delicje"],
  ["sweets", "sweets", "food", "cukierki|zelki|lizaki|draze|pralinki|bombonierka|praliny", true],
  ["ice_cream", "ice_cream", "food", "lody|lody na patyku|lody w kubku|sorbet"],
  ["crisps", "snacks", "food", "chipsy|chrupki|nachos|popcorn|prazynki"],
  ["sticks", "snacks", "food", "paluszki|paluszki solone|krakersy|precelki"],
  ["nuts", "snacks", "food", "orzechy|orzeszki|orzeszki ziemne|migdaly|pistacje|bakalie|rodzynki|suszone owoce"],
  ["spread_sweet", "spreads_sweet", "food", "krem czekoladowy|krem orzechowy|maslo orzechowe|nutella|krem kakaowy"],
  ["jam", "spreads_sweet", "food", "dzem|dzemy|konfitura|powidla|marmolada"],
  ["honey", "spreads_sweet", "food", "miod|miod wielokwiatowy|miod lipowy|miod gryczany|miod akacjowy"],
  // ----- fruit and vegetables -----
  ["apples", "fruit", "food", "jablka|jablko"],
  ["bananas", "fruit", "food", "banany|banan"],
  ["citrus", "fruit", "food", "pomarancze|pomarancza|mandarynki|mandarynka|cytryny|cytryna|limonki|grejpfrut|klementynki"],
  ["grapes", "fruit", "food", "winogrona|winogrono"],
  ["berries", "fruit", "food", "truskawki|borowki|maliny|jagody|jezyny"],
  ["stone_fruit", "fruit", "food", "sliwki|brzoskwinie|nektarynki|morele|wisnie|czeresnie"],
  ["pears", "fruit", "food", "gruszki|gruszka"],
  ["exotic", "fruit", "food", "ananas|mango|kiwi|awokado|granat|melon|arbuz"],
  ["fruit", "fruit", "food", "owoce", true],
  ["potatoes", "veg", "food", "ziemniaki|ziemniak|ziemniaki mlode|bataty"],
  ["tomatoes", "veg", "food", "pomidory|pomidor|pomidorki|pomidory koktajlowe"],
  ["cucumbers", "veg", "food", "ogorki|ogorek|ogorki szklarniowe"],
  ["roots", "veg", "food", "marchew|marchewka|buraki|pietruszka|seler|rzodkiewka|chrzan"],
  ["onions", "veg", "food", "cebula|cebule|czosnek|por|szczypiorek|dymka"],
  ["peppers", "veg", "food", "papryka|papryka czerwona|papryka zolta|chili"],
  ["leafy", "veg", "food", "salata|salaty|rukola|szpinak|roszponka|mix salat"],
  ["brassica", "veg", "food", "kapusta|brokul|brokuly|kalafior|brukselka|kalarepa"],
  ["mushrooms", "veg", "food", "pieczarki|grzyby|boczniaki"],
  ["veg", "veg", "food", "warzywa", true],
  // ----- pantry -----
  ["tomato_preserves", "pantry", "food", "koncentrat pomidorowy|passata|pomidory w puszce|przecier pomidorowy|pomidory krojone"],
  ["sauces", "pantry", "food", "ketchup|majonez|musztarda|sos|sosy|sos sojowy|sos do spaghetti|pesto|chrzan tarty"],
  ["canned_veg", "pantry", "food", "groszek|kukurydza|fasola|ciecierzyca|soczewica|groszek konserwowy|ogorki konserwowe|kiszone ogorki|oliwki"],
  ["soups", "pantry", "food", "zupa|zupy|zupa w proszku|barszcz|zupka chinska|zupa instant"],
  ["ready_meals", "pantry", "food", "danie gotowe|konserwa|gulasz|fasolka po bretonsku|golabki"],
  ["coconut_milk", "pantry", "food", "mleko kokosowe|mleczko kokosowe"],
  // ----- frozen -----
  ["pizza", "frozen", "food", "pizza|pizze"],
  ["dumplings", "frozen", "food", "pierogi|uszka|kopytka|kluski|pyzy|krokiety"],
  ["fries", "frozen", "food", "frytki|placki ziemniaczane"],
  ["frozen_veg", "frozen", "food", "warzywa mrozone|mieszanka warzywna|warzywa na patelnie|mrozonki"],
  // ----- drinks -----
  ["water", "water", "drink", "woda|wody|woda mineralna|woda zrodlana", true],
  ["water_still", "water", "drink", "woda niegazowana"],
  ["water_sparkling", "water", "drink", "woda gazowana|woda lekko gazowana"],
  ["juice", "juice", "drink", "sok|soki|nektar|sok pomaranczowy|sok jablkowy|sok multiwitamina|smoothie", true],
  ["soda", "soda", "drink", "napoj gazowany|cola|coca cola|pepsi|lemoniada|oranzada|tonik|napoj"],
  ["energy", "soda", "drink", "napoj energetyczny|energetyk|isotonic|napoj izotoniczny"],
  ["iced_tea", "soda", "drink", "napoj herbaciany|ice tea|herbata mrozona|kawa mrozona"],
  ["beer", "beer", "drink", "piwo|piwa|piwo bezalkoholowe|radler"],
  ["wine", "wine", "drink", "wino|wina|prosecco|szampan"],
  // ----- household -----
  ["laundry", "laundry", "household", "do prania|pranie|prania", true],
  ["laundry_powder", "laundry", "household", "proszek do prania|proszek"],
  ["laundry_capsules", "laundry", "household", "kapsulki do prania|kapsulki piorace"],
  ["laundry_liquid", "laundry", "household", "zel do prania|plyn do prania|plyn piorący"],
  ["softener", "laundry", "household", "plyn do plukania|plyn zmiekczajacy|plyn do plukania tkanin"],
  ["stain", "laundry", "household", "odplamiacz|wybielacz"],
  ["dish_liquid", "dishes", "household", "plyn do naczyn|plyn do mycia naczyn"],
  ["dishwasher", "dishes", "household", "tabletki do zmywarki|kapsulki do zmywarki|sol do zmywarki|nablyszczacz|zmywarka"],
  ["cleaner", "cleaning", "household", "plyn do podlog|plyn uniwersalny|srodek czyszczacy|mleczko do czyszczenia|plyn do szyb|odtluszczacz|odkamieniacz"],
  ["toilet", "cleaning", "household", "plyn do wc|zel do wc|kostka do wc|zawieszka do wc|srodek do wc"],
  ["toilet_paper", "paper", "household", "papier toaletowy|papier toaletowy 3 warstwowy"],
  ["paper_towels", "paper", "household", "recznik papierowy|reczniki papierowe|recznik kuchenny|reczniki kuchenne"],
  ["tissues", "paper", "household", "chusteczki|chusteczki higieniczne|chusteczki nawilzane|chusteczki higieniczne w pudelku"],
  ["bin_bags", "bags", "household", "worki na smieci|worki|torebki sniadaniowe|folia aluminiowa|folia spozywcza"],
  ["batteries", "batteries", "household", "baterie|bateria|akumulatorki"],
  ["air", "cleaning", "household", "odswiezacz powietrza|odswiezacz|swieca zapachowa"],
  ["car", "car", "household", "olej silnikowy|plyn do spryskiwaczy|plyn do chlodnic|plyn do szyb samochodowych|odmrazacz"],
  // ----- cosmetics -----
  ["shampoo", "hair", "cosmetics", "szampon|szampony|szampon do wlosow"],
  ["conditioner", "hair", "cosmetics", "odzywka|odzywka do wlosow|maska do wlosow|balsam do wlosow"],
  ["hair_styling", "hair", "cosmetics", "lakier do wlosow|pianka do wlosow|zel do wlosow"],
  ["hair_dye", "hair", "cosmetics", "farba do wlosow|koloryzacja"],
  ["shower", "body", "cosmetics", "zel pod prysznic|plyn do kapieli|pianka do kapieli|zel do mycia"],
  ["soap", "body", "cosmetics", "mydlo|mydla|mydlo w plynie"],
  ["body_lotion", "body", "cosmetics", "balsam do ciala|mleczko do ciala|maslo do ciala|maslo shea|shea|olejek do ciala|krem do ciala|peeling do ciala|balsam"],
  ["hand_cream", "body", "cosmetics", "krem do rak|krem do stop"],
  ["deodorant", "deo", "cosmetics", "dezodorant|antyperspirant|deo"],
  ["toothpaste", "oral", "cosmetics", "pasta do zebow"],
  ["toothbrush", "oral", "cosmetics", "szczoteczka do zebow|szczoteczka|nici dentystyczne"],
  ["mouthwash", "oral", "cosmetics", "plyn do plukania jamy ustnej|plyn do plukania ust"],
  ["face", "face", "cosmetics", "krem do twarzy|krem na dzien|krem na noc|serum|plyn micelarny|woda micelarna|woda termalna|tonik do twarzy|maseczka|krem pod oczy|zel do mycia twarzy"],
  ["sun", "face", "cosmetics", "krem z filtrem|filtr spf|balsam po opalaniu"],
  ["shaving", "shaving", "cosmetics", "maszynka do golenia|maszynki|wklady do maszynki|pianka do golenia|zel do golenia|woda po goleniu"],
  ["pads", "hygiene", "cosmetics", "podpaski|tampony|wkladki higieniczne|wkladki"],
  ["cotton", "hygiene", "cosmetics", "platki kosmetyczne|patyczki higieniczne|waciki"],
  ["makeup", "makeup", "cosmetics", "tusz do rzes|pomadka|szminka|podklad|puder|cien do powiek|kredka do oczu|lakier do paznokci|zmywacz"],
  ["perfume", "makeup", "cosmetics", "perfumy|woda toaletowa|woda perfumowana"],
  // ----- baby -----
  ["nappies", "nappies", "baby", "pieluchy|pieluszki|pieluchy jednorazowe", true],
  ["nappy_pants", "nappies", "baby", "pieluchomajtki|pieluszki majtki|majtki do nauki"],
  ["baby_wipes", "paper", "baby", "chusteczki dla dzieci|chusteczki dla niemowlat|chusteczki pampers"],
  ["baby_milk", "baby_food", "baby", "mleko modyfikowane|mleko nastepne|mleko poczatkowe|mleko junior"],
  ["baby_food", "baby_food", "baby", "kaszka|kaszki|sloiczek|sloiczki|deserek dla dzieci|obiadek|mus owocowy dla dzieci"],
  // ----- pets -----
  ["dog_food", "pet_food", "pet", "karma dla psa|karma dla psow|karma mokra dla psa|karma sucha dla psa|przysmaki dla psa"],
  ["cat_food", "pet_food", "pet", "karma dla kota|karma dla kotow|karma mokra dla kota|karma sucha dla kota|saszetki dla kota|przysmaki dla kota"],
  ["pet_food", "pet_food", "pet", "karma", true],
  ["cat_litter", "pet_care", "pet", "zwirek|zwirek dla kota|podloze dla kota"],
];

interface Compiled extends Category { phrases: { length: number; words: { raw: string; stem: string }[] }[] }

const compile = (rows: Row[]): Compiled[] => rows.map(([id, family, group, words, general]) => ({
  id, family, group, general: general === true,
  words: words.split("|"),
  phrases: words.split("|").map((w) => {
    const n = normalize(w);
    return { length: n.length, words: n.split(" ").filter(Boolean).map((raw) => ({ raw, stem: stem(raw) })) };
  }),
}));

export const CATEGORIES: readonly Compiled[] = compile(ROWS);

const SIMILAR = 0.6;

/** The category a query or a product name is in, or undefined. The closest match wins (the same word before a
 * diminutive before a shared start: "kasza" isn't "kaszka", "szampon" isn't "szampan"), then the longest phrase;
 * on a tie, the earlier in the list. */
export function categoryOf(text: string): Category | undefined {
  const words = normalize(text).split(" ").filter(Boolean).map((raw) => ({ raw, stem: stem(raw) }));
  if (!words.length) return undefined;
  let found: Category | undefined;
  let bestQuality = 0;
  let longest = 0;
  for (const c of CATEGORIES) {
    for (const p of c.phrases) {
      if (p.words.length === 0 || p.words.length > words.length) continue;
      for (let i = 0; i + p.words.length <= words.length; i++) {
        const quality = Math.min(...p.words.map((w, j) => wordSimilarity(w, words[i + j]!)));
        if (quality < SIMILAR) continue;
        if (quality > bestQuality || (quality === bestQuality && p.length > longest)) { found = c; bestQuality = quality; longest = p.length; }
      }
    }
  }
  return found;
}

/** How a product's category stands to a query's: the same thing, a similar one (a substitute), another kind of
 * thing altogether, or not known (a side without a category: matching by words decides). */
export type CategoryRelation = "same" | "similar" | "other" | "unknown";

export function relation(query: Category | undefined, product: Category | undefined): CategoryRelation {
  if (!query || !product) return "unknown";
  if (query.id === product.id) return "same";
  if (query.family !== product.family) return "other";
  return query.general || product.general ? "same" : "similar";
}
