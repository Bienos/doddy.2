import Foundation

// One clarifying question, only when it matters (ADR-661; research docs/research/2026-10-28/
// research_deals_better.md §5 #8): "kawa" matches ground, beans, instant and capsules, which aren't
// the same buy. When an item's words name none of a known group's kinds and its offers span two or
// more, the answer can say so: the screen offers the kinds as a filter, and the voice tool's answer
// tells the agent it may ask once. Worked out by code from the offers' names; a kind is never guessed
// for an offer whose name doesn't say it.
//
// Platforms: iPhone (the deals screen, the voice tool's answer). Pure logic; tested on Linux.

public struct DealsVariant: Equatable, Sendable {
    /// The kind in Polish, as a shop shelf says it ("mielona").
    public let label: String
    /// The offers of this kind, by their place in the item's `offers`.
    public let offerIndices: [Int]
}

public enum DealsVariants {
    struct Group {
        /// The item's words: a query word starting with one of these is this group's item.
        let item: [String]
        /// Each kind: its label and the word starts that name it in a product name.
        let kinds: [(label: String, stems: [String])]
    }

    /// Folded word starts, matched at the start of a word ("niegazowana" doesn't start with "gazowan").
    static let groups: [Group] = [
        Group(item: ["kaw"], kinds: [("mielona", ["mielon"]), ("ziarnista", ["ziarn"]), ("rozpuszczalna", ["rozpuszczaln"]), ("kapsułki", ["kapsul"])]),
        Group(item: ["herbat"], kinds: [("czarna", ["czarn"]), ("zielona", ["zielon"]), ("owocowa", ["owocow"]), ("ziołowa", ["ziolow"])]),
        Group(item: ["mleko", "mleka"], kinds: [("UHT", ["uht"]), ("świeże", ["swieze", "pasteryzowan"]), ("bez laktozy", ["laktoz"])]),
        Group(item: ["woda", "wody", "wode"], kinds: [("niegazowana", ["niegazowan"]), ("gazowana", ["gazowan"])]),
        Group(item: ["piwo", "piwa"], kinds: [("bezalkoholowe", ["bezalkohol"]), ("jasne", ["jasne", "lager", "pils"]), ("ciemne", ["ciemne", "porter", "stout"])]),
        Group(item: ["czekolad"], kinds: [("mleczna", ["mleczn"]), ("gorzka", ["gorzk", "deserow"]), ("biała", ["biala"])]),
        Group(item: ["jogurt"], kinds: [("naturalny", ["naturaln"]), ("grecki", ["greck"]), ("pitny", ["pitn"])]),
        Group(item: ["prani", "do prania"], kinds: [("proszek", ["proszek", "proszk"]), ("kapsułki", ["kapsul"]), ("żel", ["zel", "plyn"])]),
        Group(item: ["ryz"], kinds: [("biały", ["bial"]), ("brązowy", ["brazow"]), ("basmati", ["basmati"]), ("jaśminowy", ["jasminow"])]),
        Group(item: ["sok", "soki", "soku"], kinds: [("pomarańczowy", ["pomarancz"]), ("jabłkowy", ["jablk"]), ("multiwitamina", ["multiwitamin"])]),
    ]

    /// The kinds an item's offers span, when its words name none of them and there are two or more;
    /// nil otherwise.
    public static func split(_ item: DealsItemResult) -> [DealsVariant]? {
        let words = SearchFolding.tokens(item.query)
        guard !words.isEmpty else { return nil }
        let folded = SearchFolding.fold(item.query)
        guard let group = groups.first(where: { g in
            g.item.contains { stem in stem.contains(" ") ? folded.contains(stem) : words.contains { $0.hasPrefix(stem) } }
        }) else { return nil }
        // The item already names a kind ("kawa mielona"): nothing to ask.
        if group.kinds.contains(where: { names($0.stems, words) }) { return nil }
        let variants = group.kinds.compactMap { kind -> DealsVariant? in
            let indices = item.offers.indices.filter { names(kind.stems, SearchFolding.tokens(item.offers[$0].product)) }
            return indices.isEmpty ? nil : DealsVariant(label: kind.label, offerIndices: indices)
        }
        return variants.count >= 2 ? variants : nil
    }

    static func names(_ stems: [String], _ words: [String]) -> Bool {
        words.contains { word in stems.contains { word.hasPrefix($0) } }
    }
}
