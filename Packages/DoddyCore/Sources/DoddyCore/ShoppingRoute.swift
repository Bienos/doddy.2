import Foundation

// One field for shopping (owner, 12–13 Nov 2026, docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md 1.5; decision
// 2026-11-13-shopping-one-field): the person types what they need once, and code decides where it is looked for.
//   - Everyday things (food, drinks, household and drugstore goods, nappies, pet food) are answered from this
//     week's leaflets at once (`find_deals`, `DealsModel`).
//   - A thing to compare in online shops (headphones, a dishwasher, a sofa) is "Find me this": a background
//     errand that still needs its own yes card (constitution DOD-07), exactly as before.
//   - Things in between (shoes, a kettle, a jacket, bedding: in the shoe, home and discount chains' leaflets and
//     worth comparing online) get both: the leaflets now, online shops offered as the next step.
//   - A product link goes to "Check this", which still asks for a tap before the page is read.
// The word lists are code, written by hand like the server's shop kinds (server/messaging/src/deals/specialty.ts)
// and categories (categories.ts), which they follow; no model decides. A word no list knows is looked up in the
// leaflets first (a quick, free look), and online shops are offered when the leaflets have nothing for it. Nothing
// here sends anything: the screen shows the decision, and the person can still pick the other place.
//
// Platforms: iPhone (Shopping). Pure logic; tested on Linux.

/// What kind of thing an item is, for where to look.
public enum ShoppingItemKind: String, Equatable, Sendable {
    /// Groceries and everyday goods: the leaflets answer.
    case everyday
    /// In the leaflets of shoe, home and discount chains, and worth comparing online: both.
    case both
    /// A thing to compare in online shops.
    case online
    /// No list knows it: the leaflets first, online shops when they have nothing.
    case unknown
}

/// Where one typed text is looked for.
public struct ShoppingRoute: Equatable, Sendable {
    public enum Place: String, Equatable, Sendable {
        case nothing, link, leaflets, online, both
    }

    /// The text as typed (trimmed), when it holds a product link: "Check this" takes it.
    public let link: String?
    /// The items for the leaflets, in the order typed, as the leaflet search reads them (a budget left out).
    public let leaflets: [String]
    /// The things for "Find me this", in the order typed, each with its own words.
    public let online: [String]

    public init(link: String? = nil, leaflets: [String] = [], online: [String] = []) {
        self.link = link
        self.leaflets = leaflets
        self.online = online
    }

    public var place: Place {
        if link != nil { return .link }
        switch (leaflets.isEmpty, online.isEmpty) {
        case (true, true): return .nothing
        case (false, true): return .leaflets
        case (true, false): return .online
        case (false, false): return .both
        }
    }

    // MARK: Deciding

    /// Where `text` goes. Items are split at commas, semicolons and new lines; a part that only qualifies the one
    /// before it ("do 500 zł", "z ANC", "bez laktozy", "45 cm") stays with it. A link anywhere goes to "Check this".
    /// `place` is the person's own pick over the code's: `.leaflets` looks everything up in the leaflets, `.online`
    /// offers everything for "Find me this"; anything else (or nil) lets the code decide.
    public static func route(_ text: String, to place: Place? = nil) -> ShoppingRoute {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ShoppingRoute() }
        if SharedShopPage.parse(trimmed) != nil { return ShoppingRoute(link: trimmed) }
        let groups = groups(trimmed)
        switch place {
        case .leaflets?:
            return ShoppingRoute(leaflets: unique(groups.map(\.leaflet)))
        case .online?:
            return ShoppingRoute(online: groups.count == 1 ? [trimmed] : unique(groups.map(\.words)))
        default:
            break
        }
        var leaflets: [String] = []
        var online: [String] = []
        for group in groups {
            switch kind(of: group.words) {
            case .everyday, .unknown:
                leaflets.append(group.leaflet)
            case .both:
                leaflets.append(group.leaflet)
                online.append(group.words)
            case .online:
                online.append(group.words)
            }
        }
        // One thing for online shops: its words exactly as typed, which is what the yes card shows and sends.
        if groups.count == 1, !online.isEmpty { online = [trimmed] }
        return ShoppingRoute(leaflets: unique(leaflets), online: unique(online))
    }

    /// The kind of one item. The longest phrase any list knows decides ("tabletki do zmywarki" is everyday,
    /// "zmywarka" is online, "ekspres do kawy" is online although "kawa" is everyday). With no phrase known, a budget
    /// ("do 2000 zł"), a size to compare ("55 cali", "45 cm"), a model ("XM5", "S24") or a brand of electronics or
    /// appliances makes it online; otherwise it is unknown.
    public static func kind(of item: String) -> ShoppingItemKind {
        let words = SearchFolding.tokens(item)
        guard !words.isEmpty else { return .unknown }
        var best: (kind: ShoppingItemKind, words: Int, length: Int)?
        for (kind, phrases) in dictionaries {
            for phrase in phrases where phrase.count <= words.count {
                guard matches(phrase, in: words) else { continue }
                let length = phrase.reduce(0) { $0 + $1.text.count }
                if let held = best, (held.words, held.length) >= (phrase.count, length) { continue }
                best = (kind, phrase.count, length)
            }
        }
        if let best { return best.kind }
        if hasBudget(words) || hasSpec(words) || hasModel(words) || words.contains(where: { onlineBrands.contains($0) }) {
            return .online
        }
        return .unknown
    }

    /// After a leaflet answer: the things to offer for "Find me this" next, once each, in this order: `also` (the
    /// things the person's words already sent there), then each answered item that is in between or online, then
    /// each unknown item the leaflets had nothing for (no offer and no promotion). Everyday items are never offered:
    /// milk that isn't on offer this week is no task for online shops. Two texts with the same words, whatever the
    /// case, letters with marks or punctuation ("buty, rozmiar 42" and "buty rozmiar 42"), are one thing.
    public static func onlineNext(_ result: DealsResult, also: [String] = []) -> [String] {
        var next: [String] = []
        var seen = Set<[String]>()
        func add(_ thing: String) {
            let words = SearchFolding.tokens(thing)
            guard !words.isEmpty, seen.insert(words).inserted else { return }
            next.append(thing.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        also.forEach(add)
        // The leaflets read an item without its quantity or budget ("czajnik 1,7 l" → "czajnik"): when its words are
        // all in a thing already offered, it is that thing.
        let offered = next.map { Set(SearchFolding.tokens($0)) }
        for item in result.items {
            if offered.contains(where: { Set(SearchFolding.tokens(item.query)).isSubset(of: $0) }) { continue }
            switch kind(of: item.query) {
            case .both, .online:
                add(item.query)
            case .unknown where item.offers.isEmpty && item.promotions.isEmpty:
                add(item.query)
            default:
                break
            }
        }
        return next
    }

    // MARK: Splitting

    struct Group: Equatable {
        /// The parts as typed, joined with ", ": what "Find me this" sends.
        let words: String
        /// The item and what narrows it, without a budget or size: what the leaflet search reads.
        let leaflet: String
    }

    static func groups(_ text: String) -> [Group] {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var groups: [[String]] = []
        for part in parts {
            if !groups.isEmpty, qualifies(part) {
                groups[groups.count - 1].append(part)
            } else {
                groups.append([part])
            }
        }
        return groups.map { parts in
            let kept = [parts[0]] + parts.dropFirst().filter { !isBudgetOrSize(SearchFolding.tokens($0)) }
            return Group(words: parts.joined(separator: ", "), leaflet: kept.joined(separator: " "))
        }
    }

    /// A part that says something about the item before it rather than naming a new one.
    static func qualifies(_ part: String) -> Bool {
        let words = SearchFolding.tokens(part)
        guard let first = words.first else { return false }
        return qualifierStarts.contains(first) || isBudgetOrSize(words)
    }

    /// "do 500 zł", "under 2000", "2000 zł", "45 cm": a number with a budget word or only units around it.
    static func isBudgetOrSize(_ words: [String]) -> Bool {
        guard words.contains(where: { $0.contains(where: \.isNumber) }) else { return false }
        if let first = words.first, budgetStarts.contains(first) { return true }
        return words.allSatisfy { word in
            word.allSatisfy(\.isNumber) || units.contains(word) || specUnits.contains(word) || isNumberWithUnit(word)
        }
    }

    // MARK: Signals for a word no list knows

    static func hasBudget(_ words: [String]) -> Bool {
        for (index, word) in words.enumerated() where budgetStarts.contains(word) {
            if index + 1 < words.count, words[index + 1].first?.isNumber == true { return true }
        }
        return words.indices.contains { index in
            words[index].allSatisfy(\.isNumber) && index + 1 < words.count && ["zl", "pln", "zlotych", "euro", "eur"].contains(words[index + 1])
        }
    }

    /// A number with a unit people compare things by: "55 cali", "45 cm", "256 GB", "2000 W".
    static func hasSpec(_ words: [String]) -> Bool {
        for (index, word) in words.enumerated() {
            if word.allSatisfy(\.isNumber), index + 1 < words.count, specUnits.contains(words[index + 1]) { return true }
            if let unit = unitSuffix(word), specUnits.contains(unit) { return true }
        }
        return false
    }

    /// A model name: letters and digits in one word ("xm5", "s24", "rtx4070"), but not a pack size ("500g", "4x120g").
    static func hasModel(_ words: [String]) -> Bool {
        words.contains { word in
            word.count >= 2 && word.contains(where: \.isLetter) && word.contains(where: \.isNumber) && !isNumberWithUnit(word)
                && !packPattern(word)
        }
    }

    /// "500g", "1,5l" (as one token "1"), "45cm": digits then a known unit.
    static func isNumberWithUnit(_ word: String) -> Bool {
        unitSuffix(word).map { units.contains($0) || specUnits.contains($0) } ?? false
    }

    static func unitSuffix(_ word: String) -> String? {
        guard let first = word.first, first.isNumber else { return nil }
        let unit = word.drop(while: \.isNumber)
        return unit.isEmpty || unit.contains(where: \.isNumber) ? nil : String(unit)
    }

    /// "4x120g", "6x1l": a multipack.
    static func packPattern(_ word: String) -> Bool {
        let parts = word.split(separator: "x", maxSplits: 1)
        guard parts.count == 2, parts[0].allSatisfy(\.isNumber) else { return false }
        let rest = String(parts[1])
        return rest.allSatisfy(\.isNumber) || isNumberWithUnit(rest)
    }

    // MARK: Matching

    struct Part: Equatable {
        let text: String
        /// The whole word must be this ("tv$"); otherwise a word starting with it matches ("sluchawk").
        let whole: Bool
    }

    static func matches(_ phrase: [Part], in words: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= words.count else { return false }
        for start in 0...(words.count - phrase.count) {
            if phrase.indices.allSatisfy({ i in
                let word = words[start + i]
                return phrase[i].whole ? word == phrase[i].text : word.hasPrefix(phrase[i].text)
            }) { return true }
        }
        return false
    }

    static func compile(_ list: String) -> [[Part]] {
        list.split(separator: "|").map { phrase in
            phrase.split(separator: " ").map { part in
                part.hasSuffix("$") ? Part(text: String(part.dropLast()), whole: true) : Part(text: String(part), whole: false)
            }
        }
    }

    static func unique(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert(SearchFolding.fold($0)).inserted }
    }

    // MARK: The lists
    //
    // Folded (lower case, Polish letters plain: ł → l), Polish and English. A part is a word start unless it ends in
    // "$" (the whole word). A phrase matches its words in a row. Kept concrete: a missed word only means the leaflets
    // are asked first; a wrong one is shown on the screen before anything is sent, and the person can switch.

    /// Following categories.ts (food, drink, household, cosmetics, baby, pet) at the level the route needs.
    static let everyday = compile([
        // dairy, eggs, fats
        "mlek|mleczn|masl|maselk|margaryn|smalec|smietan|jogurt|kefir|maslank|skyr|ser$|sera$|sery$|serek|serk|twarog|mozzarell|feta$",
        "gouda|edam|camembert|parmezan|jaj|jajk",
        // meat and fish
        "kurczak|kurczec|indyk|schab|karkowk|wieprzow|wolow|mieso|miesa$|mielon|szynk|kielbas|kabanos|parowk|boczek|boczk|bekon|pasztet",
        "wedlin|parowek|salami|losos|dorsz|mintaj|sledz|makrel|tunczyk|krewetk|ryba$|ryby$",
        // bread, grains, baking, spices
        "chleb|bulk|bulecz|bagietk|rogal|rogalik|tortill|ryz$|ryzu$|makaron|spaghetti|kasz|kaszy|maka$|maki$|cukier|cukru$|drozdz",
        "sol$|soli$|pieprz|przypraw|kostk rosol|bulion|olej|oliw|platki|musli|granol|owsiank",
        // hot drinks, sweets, snacks, spreads
        "kaw|kawy$|herbat|kakao|czekolad|baton|ciastk|ciastecz|herbatnik|wafel|wafl|cukierk|zelk|lizak|lody$|lodow$|chips|chrupk|paluszk",
        "orzech|orzeszk|migdal|rodzynk|dzem|konfitur|miod|nutell|krem czekoladow",
        // fruit and vegetables
        "jablk|jablek|banan|pomarancz|mandaryn|cytryn|limonk|winogron|truskawk|borowk|malin|gruszk|ananas|mango$|kiwi$|awokado|arbuz|melon",
        "owoc|ziemniak|pomidor|ogork|ogorek|marchew|marchw|burak|cebul|czosn|papryk|salat|kapust|brokul|kalafior|pieczark|warzyw",
        "groszek|kukurydz|fasol|ciecierzyc|soczewic|ketchup|majonez|musztard|sos$|sosu$|sosy$|pesto|zup|zupk|pizz|pierog|frytk|mrozonk",
        // drinks
        "woda$|wody$|wode$|woda mineraln|sok$|soki$|soku$|nektar|napoj|cola$|pepsi|piwo|piwa$|wino$|wina$|prosecco|wodk|energetyk",
        // household
        "prani|proszek do prani|plyn do|plyn$|plynu$|kapsulk do prani|plukani|zmiekczacz|odplamiacz|naczyn|tabletk do zmywark",
        "kapsulk do zmywark|sol do zmywark|nablyszczacz|domestos|papier toaletow|papieru toaletow|recznik papierow|reczniki papierow",
        "recznik kuchenn|reczniki kuchenn|chusteczk|worki na smieci|worki$|work na smieci|folia$|folii$|bateri|zarowk|odswiezacz",
        "srodek czyszcz|mleczko do czyszcz|gabk|scierk|zapalk",
        // cosmetics
        "szampon|odzywk|zel pod prysznic|mydl|balsam|krem$|kremu$|dezodorant|antyperspirant|pasta do zebow|pasty do zebow|szczoteczk",
        "podpask|tampon|wkladk|plyn micelarn|tusz do rzes|pomadk|lakier do paznokc|maszynk do goleni|pianka do goleni|zel do goleni",
        "platki kosmetyczn|patyczki",
        // baby and pets
        "pieluch|pieluszk|pieluchomajtk|pampers|kaszk|sloiczk|chusteczki nawilzan|karm|zwirek|zwirk|przysmak|saszetk",
        // English
        "milk$|butter$|egg$|eggs$|bread$|rolls$|cheese$|ham$|bacon$|sausage|chicken|beef$|pork$|mince$|fish$|salmon$|tuna$|rice$",
        "pasta$|flour$|sugar$|salt$|oil$|coffee$|tea$|teabags$|cocoa$|chocolate|biscuit|cookie|crisps$|nuts$|jam$|honey$|apples$",
        "banana|orange$|oranges$|lemon|grape|strawberr|potato|tomato|cucumber|carrot|onion|garlic|lettuce|cabbage|mushroom|beans$|soup$",
        "pizza$|juice$|water$|cola$|beer$|wine$|yoghurt|yogurt|cream$|cereal$|oats$|detergent|washing powder|washing liquid|softener",
        "dish soap|washing up liquid|dishwasher tablets|dishwasher tablet|toilet paper|toilet roll|kitchen roll|paper towel|tissues$",
        "bin bags|shampoo|conditioner$|shower gel|soap$|toothpaste|deodorant|nappies$|nappy$|diapers$|wipes$|baby food|formula$",
        "cat food|dog food|pet food|cat litter|litter$",
    ].joined(separator: "|"))

    /// In the leaflets of shoe, home, pet and discount chains, and worth comparing online.
    static let both = compile([
        // shoes and home: the server's specialty kinds (specialty.ts)
        "but$|buty$|butow$|obuwi|sneakers|trampk|tenisowk|kozak|botk|sandal|klapk|japonk|kapc|polbut|czolenk|szpilk|mokasyn|balerin",
        "sniegow|kalosz|glan|workery|espadryl|adidasy",
        "panel|podlog|wykladzin|dywan|chodnik|drzwi|plytk|kafelk|tapet|firan|zaslon|rolet|karnisz|listw|wycieraczk|laminat|klamk|oscieznic",
        "smycz|obroz|legowisk|drapak|kuwet|akwari|terrari|klatk",
        // clothes
        "kurtk|plaszcz|spodni|jeans|dzins|bluz|sweter|swetr|koszul|sukienk|spodnic|pizam|bielizn|skarpet|rajstop|czapk|szalik|rekawiczk",
        // kitchen and home goods
        "patelni|garnek|garnk|rondel|noz$|noze$|nozy$|sztucc|talerz|kubek|kubk|szklank|pojemnik|termos|deska do krojeni|posciel|poduszk",
        "koldr|koc$|koce$|kocyk|recznik|reczniki|lampk|lampa$|lampe$|swiec|wazon|ramk|wieszak|suszark do prani|deska do prasowani",
        // small appliances
        "czajnik|toster|blender|mikser|sokowirowk|wyciskark|frytkownic|zelazk|parownic|golark|trymer|maszynk do strzyzeni|suszark do wlosow",
        "prostownic|lokowk|waga$|wage$|wagi$|termometr|wentylator|grzejnik|farelk|nawilzacz|opiekacz|gofrownic|mlynek|spieniacz",
        "radio$|powerbank|ladowark|kabel|kable$|karta pamieci|karty pamieci|pendrive",
        // tools, garden, toys, sport, bags
        "wiertark|wkretark|szlifierk|pila$|pily$|mlotek|srubokret|klucz|narzedzi|drabin|taczk|waz ogrodow|donic|nasion|zabawk|klocki|lego$",
        "lalk|puzzl|gra planszow|pilk|hantl|mata do jog|kask|plecak|walizk|torb|parasol|perfum|wod toaletow|woda perfumowan",
        // English
        "shoes$|shoe$|boots$|trainers$|sneakers$|sandals$|slippers$|carpet|rug$|curtains$|blinds$|wallpaper$|tiles$|flooring$",
        "jacket$|coat$|trousers$|jeans$|hoodie$|sweater$|jumper$|shirt$|dress$|pyjamas$|socks$|gloves$|scarf$|kettle$|toaster$|blender$",
        "mixer$|air fryer|iron$|hair dryer|hairdryer|straightener|shaver$|trimmer$|fan$|heater$|scales$|frying pan|pan$|pans$|saucepan",
        "knife$|knives$|plates$|mugs$|towel$|towels$|bedding$|duvet$|pillow$|blanket$|lamp$|drill$|screwdriver|saw$|ladder$|toy$",
        "toys$|puzzle$|ball$|backpack$|suitcase$|umbrella$|perfume$|charger$|power bank|powerbank$|cable$",
    ].joined(separator: "|"))

    /// Things to compare in online shops: electronics, appliances, furniture, bikes, prams.
    static let online = compile([
        "sluchawk|airpods|glosnik|soundbar|telewizor|tv$|monitor|laptop|komputer|tablet$|tabletu$|tablety$|ipad|smartfon|telefon|komork",
        "iphone|macbook|smartwatch|smartband|zegarek|zegarka$|aparat|kamer|konsol|playstation|ps5$|ps4$|xbox|nintendo|drukark|router",
        "dysk$|dysku$|karta graficzn|procesor|klawiatur|mysz$|myszk komputerow|projektor|czytnik|kindle|dron$|drona$|mikrofon",
        "pralk|lodowk|zmywark|piekarnik|plyta indukcyjn|plyt indukcyjn|plyta gazow|okap|zamrazark|klimatyzator|klimatyzacj",
        "suszark do ubran|suszark bebnow|kuchenk mikrofal|mikrofalowk|ekspres|ekspres do kaw|odkurzacz|robot sprzatajac|robot kuchenn",
        "oczyszczacz powietrz|bojler|szczoteczk elektryczn|szczoteczk soniczn|elektryczn szczoteczk|apple watch|airtag",
        "sofa$|sofy$|kanapa$|kanape$|narozn|lozk|materac|szafa$|szafy$|szafe$|szafk|komod|biurk|fotel|regal|stol$|stolu$|stolik",
        "rower|hulajnog|deskorolk|rolki$|narty$|snowboard|biezni|orbitrek|wozek|wozk|fotelik|opon|felg|okular|bizuteri|pierscion",
        // English
        "headphones$|headphone$|earbuds$|earphones$|airpods$|speaker$|speakers$|soundbar$|tv$|television$|monitor$|laptop$|computer$",
        "pc$|tablet$|ipad$|phone$|smartphone$|iphone$|macbook$|smartwatch$|watch$|camera$|console$|playstation$|xbox$|nintendo$",
        "printer$|router$|ssd$|hard drive|graphics card|keyboard$|mouse$|projector$|e reader|ereader$|kindle$|drone$|microphone$",
        "washing machine|fridge$|refrigerator$|freezer$|dishwasher$|oven$|hob$|microwave$|cooker$|cooker hood|air conditioner",
        "vacuum$|hoover$|coffee machine|espresso machine|robot vacuum|air purifier|sofa$|couch$|mattress$|bed$|wardrobe$|desk$|armchair$",
        "bookcase$|bike$|bicycle$|scooter$|skateboard$|treadmill$|pram$|stroller$|pushchair$|car seat|tyres$|tires$|glasses$|jewellery$",
    ].joined(separator: "|"))

    /// The lists, in the order a tie goes to the earlier one.
    static let dictionaries: [(ShoppingItemKind, [[Part]])] = [(.everyday, everyday), (.both, both), (.online, online)]

    /// Brands of electronics, appliances and tools: an item with no known word and one of these is online.
    static let onlineBrands: Set<String> = [
        "apple", "samsung", "sony", "xiaomi", "huawei", "lenovo", "asus", "acer", "dell", "hp", "lg", "jbl", "bose", "sennheiser",
        "garmin", "fitbit", "nintendo", "dji", "gopro", "canon", "nikon", "fujifilm", "logitech", "razer", "dyson", "bosch", "siemens",
        "electrolux", "whirlpool", "beko", "miele", "amica", "delonghi", "philips", "braun", "tefal", "pixel", "oneplus", "motorola",
        "nokia", "realme", "oppo", "msi", "corsair", "steelseries", "hyperx", "anker", "ugreen", "netgear", "ikea", "makita", "dewalt",
        "karcher", "stihl", "husqvarna", "roborock", "ecovacs", "irobot", "marshall", "sonos", "kobo", "pocketbook",
    ]

    /// A part that starts with one of these qualifies the item before it.
    static let qualifierStarts: Set<String> = [
        "z", "ze", "bez", "tylko", "dla", "do", "pod", "ponizej", "max", "maks", "maksymalnie", "najwyzej", "najlepiej", "budzet",
        "cena", "okolo", "kolor", "rozmiar", "with", "without", "only", "for", "under", "below", "up", "budget", "price", "around",
        "about", "ideally", "preferably", "colour", "color", "size",
    ]

    static let budgetStarts: Set<String> = [
        "do", "pod", "ponizej", "max", "maks", "maksymalnie", "najwyzej", "budzet", "cena", "okolo", "under", "below", "up", "budget",
        "price", "around", "about",
    ]

    /// Pack sizes and money: a number with only these is a size or a budget, not a new item.
    static let units: Set<String> = [
        "zl", "pln", "zlotych", "eur", "euro", "g", "kg", "dag", "ml", "l", "szt", "sztuk", "sztuki",
    ]

    /// Units people compare things by.
    static let specUnits: Set<String> = [
        "cm", "mm", "cali", "cal", "inch", "inches", "gb", "tb", "mah", "hz", "w", "kw", "mpx", "mp",
    ]
}
