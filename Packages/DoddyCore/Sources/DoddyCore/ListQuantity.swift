import Foundation

// Quantities on list items (Shopping list+, ADR-631, stage 1). An item keeps the user's words
// (ADR-216); this only reads a quantity out of them, so a row can show "mleka" with "2 l" beside
// it. Reading is conservative: a number glued to a word ("7up", "WD-40"), a percentage
// ("mleko 3,2%") or a bare number at the end ("iPhone 15") is not a quantity. Nothing here changes
// matching or duplicates, and nothing is rewritten.
//
// Platforms: iPhone and iPad use it (list rows). Pure logic; tested on Linux.

/// A unit a shopping list item can be counted in.
public enum ListUnit: String, Codable, CaseIterable, Sendable {
    case gram, decagram, kilogram, millilitre, litre, piece, pack, bottle, can

    /// Quantities of the same kind can be added together; different kinds never are.
    public enum Kind: String, Sendable {
        case mass, volume, count, pack, bottle, can
    }

    public var kind: Kind {
        switch self {
        case .gram, .decagram, .kilogram: .mass
        case .millilitre, .litre: .volume
        case .piece: .count
        case .pack: .pack
        case .bottle: .bottle
        case .can: .can
        }
    }

    /// How many grams, millilitres or pieces one of this unit is.
    var base: Decimal {
        switch self {
        case .decagram: 10
        case .kilogram, .litre: 1000
        default: 1
        }
    }

    /// The short label shown next to an item.
    public func symbol(polish: Bool) -> String {
        switch self {
        case .gram: "g"
        case .decagram: "dag"
        case .kilogram: "kg"
        case .millilitre: "ml"
        case .litre: "l"
        case .piece: polish ? "szt." : "pcs"
        case .pack: polish ? "op." : "pack"
        case .bottle: polish ? "but." : "bottle"
        case .can: polish ? "pusz." : "can"
        }
    }

    /// Folded words (lower case, no accents) that name each unit; a trailing dot is ignored.
    static let aliases: [String: ListUnit] = {
        let words: [ListUnit: [String]] = [
            .gram: ["g", "gr", "gram", "gramy", "gramow", "grams"],
            .decagram: ["dag", "dkg", "deko"],
            .kilogram: ["kg", "kilo", "kilogram", "kilogramy", "kilogramow", "kilos", "kilograms"],
            .millilitre: ["ml", "mililitr", "mililitry", "mililitrow", "millilitre", "millilitres", "milliliter", "milliliters"],
            .litre: ["l", "litr", "litry", "litrow", "litre", "litres", "liter", "liters"],
            .piece: ["szt", "sztuka", "sztuki", "sztuk", "pcs", "pc", "piece", "pieces"],
            .pack: ["op", "opak", "opakowanie", "opakowania", "opakowan", "paczka", "paczki", "paczek",
                    "pack", "packs", "packet", "packets"],
            .bottle: ["but", "butelka", "butelki", "butelek", "bottle", "bottles"],
            .can: ["pusz", "puszka", "puszki", "puszek", "can", "cans"],
        ]
        var map: [String: ListUnit] = [:]
        for (unit, list) in words { for word in list { map[word] = unit } }
        return map
    }()

    /// The unit a word names ("kg", "litry", "szt."), or nil.
    static func named(_ word: String) -> ListUnit? {
        var folded = SearchFolding.fold(word)
        if folded.hasSuffix(".") { folded.removeLast() }
        return aliases[folded]
    }
}

/// How much of an item: an amount and, unless it is a bare count ("3 jajka", "mleko x2"), a unit.
public struct ListQuantity: Equatable, Hashable, Sendable {
    public static let maxAmount: Decimal = 9999
    /// A number with no unit at the start is a count only up to this ("3 jajka", not "1000 wysp").
    public static let maxBareCount: Decimal = 99

    public let amount: Decimal
    /// Nil for a bare count.
    public let unit: ListUnit?

    public init(amount: Decimal, unit: ListUnit?) {
        self.amount = amount
        self.unit = unit
    }

    /// A bare count adds up with pieces.
    public var kind: ListUnit.Kind { unit?.kind ?? .count }

    /// In grams, millilitres or pieces.
    public var baseAmount: Decimal { amount * (unit?.base ?? 1) }

    /// "2 l", "1,5 kg", "500 g", "×3" (a bare count); a decimal comma in Polish.
    public func display(polish: Bool) -> String {
        let number = Self.format(amount, polish: polish)
        guard let unit else { return "×\(number)" }
        return "\(number) \(unit.symbol(polish: polish))"
    }

    static func format(_ value: Decimal, polish: Bool) -> String {
        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, 3, .plain)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        return polish ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    /// Adds quantities of the same kind: grams with kilograms, millilitres with litres, pieces with
    /// bare counts. Kinds stay apart, in the order first seen. Mass of 1,000 g or more is shown in
    /// kilograms and volume of 1,000 ml or more in litres; packs, bottles and cans stay as they are.
    public static func total(_ quantities: [ListQuantity]) -> [ListQuantity] {
        var order: [ListUnit.Kind] = []
        var sums: [ListUnit.Kind: Decimal] = [:]
        for quantity in quantities {
            if sums[quantity.kind] == nil { order.append(quantity.kind) }
            sums[quantity.kind, default: 0] += quantity.baseAmount
        }
        return order.map { kind in
            let sum = sums[kind] ?? 0
            switch kind {
            case .mass: return sum >= 1000 ? ListQuantity(amount: sum / 1000, unit: .kilogram) : ListQuantity(amount: sum, unit: .gram)
            case .volume: return sum >= 1000 ? ListQuantity(amount: sum / 1000, unit: .litre) : ListQuantity(amount: sum, unit: .millilitre)
            case .count: return ListQuantity(amount: sum, unit: .piece)
            case .pack: return ListQuantity(amount: sum, unit: .pack)
            case .bottle: return ListQuantity(amount: sum, unit: .bottle)
            case .can: return ListQuantity(amount: sum, unit: .can)
            }
        }
    }
}

/// An item's words split into the product and a quantity read from them. `product` is the user's
/// words with the quantity taken out, unchanged otherwise; with no quantity it is the whole text.
public struct ListItemWords: Equatable, Sendable {
    public let product: String
    public let quantity: ListQuantity?

    public init(product: String, quantity: ListQuantity?) {
        self.product = product
        self.quantity = quantity
    }

    /// Reads "2 l mleka", "500g mąki", "dwa mleka", "mleko 2 l", "jajka 10 szt.", "mleko x2".
    public static func read(_ text: String) -> ListItemWords {
        let whole = ListItemWords(product: text, quantity: nil)
        guard let cleaned = ListText.cleaned(text) else { return whole }
        let tokens = cleaned.split(separator: " ").map(String.init)
        guard tokens.count >= 2 else { return ListItemWords(product: cleaned, quantity: nil) }
        if let found = leading(tokens) ?? trailing(tokens) { return found }
        return ListItemWords(product: cleaned, quantity: nil)
    }

    // MARK: Reading

    private static let multipliers: Set<String> = ["x", "×"]

    /// Folded number words; "pół"/"half" and "półtora" are fractions.
    private static let numberWords: [String: Decimal] = [
        "jeden": 1, "jedna": 1, "jedno": 1, "dwa": 2, "dwie": 2, "trzy": 3, "cztery": 4, "piec": 5,
        "szesc": 6, "siedem": 7, "osiem": 8, "dziewiec": 9, "dziesiec": 10, "pol": 0.5,
        "poltora": 1.5, "poltorej": 1.5,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "half": 0.5, "½": 0.5,
    ]

    /// A number at the start: "2", "1,5", "500g", "2x", "dwa", "pół".
    private static func leading(_ tokens: [String]) -> ListItemWords? {
        var index = 0
        let first = tokens[0]
        var amount: Decimal
        var unit: ListUnit?
        var bare = true
        if let (number, suffix) = numberWithSuffix(first) {
            amount = number
            if suffix.isEmpty {
                // nothing glued on
            } else if multipliers.contains(suffix) {
                bare = false
            } else if let named = ListUnit.named(suffix) {
                unit = named
                bare = false
            } else {
                return nil // "7up", "3D"
            }
        } else if let word = numberWords[SearchFolding.fold(first)] {
            amount = word
        } else {
            return nil
        }
        index = 1
        if unit == nil, bare, index < tokens.count {
            if let named = ListUnit.named(tokens[index]) {
                unit = named
                index += 1
            } else if multipliers.contains(tokens[index].lowercased()) {
                index += 1
            }
        }
        // A bare count is a whole number up to 99 ("3 jajka"); "pół sera" needs a unit, and
        // "1000 wysp" is a name, not a count.
        if unit == nil, !amount.isWhole || amount > ListQuantity.maxBareCount { return nil }
        let rest = Array(tokens[index...])
        guard let product = productWords(rest) else { return nil }
        return ListItemWords(product: product, quantity: ListQuantity(amount: amount, unit: unit))
    }

    /// A unit or a multiplier at the end: "mleko 2 l", "mleko 2l", "jajka 10 szt.", "mleko x2",
    /// "mleko x 2", "mleko 2x". A bare number at the end ("iPhone 15") is not a quantity.
    private static func trailing(_ tokens: [String]) -> ListItemWords? {
        let last = tokens[tokens.count - 1]
        let lowered = last.lowercased()
        // "x2", "×2"
        if let symbol = lowered.first, multipliers.contains(String(symbol)),
           let (number, suffix) = numberWithSuffix(String(lowered.dropFirst())), suffix.isEmpty, number.isWhole {
            return finish(tokens.dropLast(1), ListQuantity(amount: number, unit: nil))
        }
        if let (number, suffix) = numberWithSuffix(lowered) {
            if multipliers.contains(suffix), number.isWhole {
                return finish(tokens.dropLast(1), ListQuantity(amount: number, unit: nil)) // "2x"
            }
            if let unit = ListUnit.named(suffix), !suffix.isEmpty {
                return finish(tokens.dropLast(1), ListQuantity(amount: number, unit: unit)) // "2l", "500g"
            }
            // "x 2", "× 2"
            if suffix.isEmpty, tokens.count >= 3, multipliers.contains(tokens[tokens.count - 2].lowercased()),
               number.isWhole {
                return finish(tokens.dropLast(2), ListQuantity(amount: number, unit: nil))
            }
            return nil
        }
        // "2 l", "10 szt."
        if let unit = ListUnit.named(last), tokens.count >= 3,
           let (number, suffix) = numberWithSuffix(tokens[tokens.count - 2]), suffix.isEmpty {
            return finish(tokens.dropLast(2), ListQuantity(amount: number, unit: unit))
        }
        return nil
    }

    private static func finish(_ rest: ArraySlice<String>, _ quantity: ListQuantity) -> ListItemWords? {
        guard let product = productWords(Array(rest)) else { return nil }
        return ListItemWords(product: product, quantity: quantity)
    }

    /// The remaining words, if at least one has a letter; an English "of" after the unit is
    /// dropped ("2 packs of bananas" → "bananas").
    private static func productWords(_ tokens: [String]) -> String? {
        var words = tokens
        if words.count > 1, words[0].lowercased() == "of" { words.removeFirst() }
        guard !words.isEmpty, words.contains(where: { $0.contains(where: \.isLetter) }) else { return nil }
        return words.joined(separator: " ")
    }

    /// "2" → (2, ""), "1,5" → (1.5, ""), "500g" → (500, "g"), "2x" → (2, "x"). The number has at
    /// most four digits before and three after the point, is above zero and at most 9,999.
    private static func numberWithSuffix(_ token: String) -> (Decimal, String)? {
        let lowered = token.lowercased()
        var digits = ""
        var rest = Substring(lowered)
        var seenPoint = false
        var before = 0, after = 0
        while let character = rest.first {
            if character.isASCII, character.isNumber {
                if seenPoint { after += 1 } else { before += 1 }
                digits.append(character)
            } else if (character == "," || character == "."), !seenPoint, before > 0,
                      let next = rest.dropFirst().first, next.isASCII, next.isNumber {
                seenPoint = true
                digits.append(".")
            } else {
                break
            }
            rest = rest.dropFirst()
        }
        guard before > 0, before <= 4, after <= 3 else { return nil }
        guard let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")),
              value > 0, value <= ListQuantity.maxAmount else { return nil }
        let suffix = String(rest)
        // A suffix must be letters (a unit) or a multiplier, nothing else: "3,2%" and "40-" are not quantities.
        guard suffix.isEmpty || multipliers.contains(suffix) || suffix.allSatisfy({ $0.isLetter || $0 == "." }) else {
            return nil
        }
        return (value, suffix)
    }
}

private extension Decimal {
    var isWhole: Bool {
        var whole = Decimal()
        var input = self
        NSDecimalRound(&whole, &input, 0, .down)
        return whole == self
    }
}
