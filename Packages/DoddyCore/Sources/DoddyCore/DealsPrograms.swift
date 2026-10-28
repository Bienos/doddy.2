import Foundation

// "Moje programy" (ADR-661; research docs/research/2026-10-28/research_deals_better.md §5 #2): the
// chains' loyalty apps and cards the user says they don't use. A leaflet price that needs one of them
// isn't a price this user can get, so the basket leaves it out and the screen says "with an app you
// don't use". Nothing is assumed: until the user turns a program off, every price counts, as before.
// The choice is the user's own setting on this phone (the app stores it and reads it back); it never
// goes to Doddy's server or to the chains.
//
// Platforms: iPhone (the deals screen, the basket, the voice tool's answer). Pure logic; tested on Linux.

/// A chain's loyalty app or card that leaflet prices can ask for.
public enum DealsProgram: String, Codable, CaseIterable, Sendable {
    case mojaBiedronka = "moja_biedronka"
    case lidlPlus = "lidl_plus"
    case rossmann
    case zappka

    public var chain: DealsChain {
        switch self {
        case .mojaBiedronka: .biedronka
        case .lidlPlus: .lidl
        case .rossmann: .rossmann
        case .zappka: .zabka
        }
    }

    /// The program's own name, as the chains print it.
    public var name: String {
        switch self {
        case .mojaBiedronka: "Moja Biedronka"
        case .lidlPlus: "Lidl Plus"
        case .rossmann: "Rossmann"
        case .zappka: "Żappka"
        }
    }

    /// The chain's program, when Doddy knows one.
    public static func of(_ chain: DealsChain) -> DealsProgram? {
        allCases.first { $0.chain == chain }
    }
}

/// The programs the user said they don't use. Empty (the default): every price counts.
public struct DealsPrograms: Equatable, Sendable {
    public let notUsed: Set<DealsProgram>

    public init(notUsed: Set<DealsProgram> = []) {
        self.notUsed = notUsed
    }

    public static let all = DealsPrograms()

    /// False only when the price needs the chain's app or card and the user said they don't use it.
    /// A chain whose program Doddy doesn't know keeps its price: nothing is ruled out on a guess.
    public func canGet(_ offer: DealOffer) -> Bool {
        guard offer.needsProgram, let program = DealsProgram.of(offer.chain) else { return true }
        return !notUsed.contains(program)
    }

    /// The program an offer needs that the user doesn't use, for the "with an app you don't use" line.
    public func missing(for offer: DealOffer) -> DealsProgram? {
        canGet(offer) ? nil : DealsProgram.of(offer.chain)
    }

    // MARK: Stored form

    /// The stored text: the programs not used, by identifier, comma-separated and sorted ("lidl_plus,zappka").
    public var stored: String {
        notUsed.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// From the stored text; an identifier this version doesn't know is ignored.
    public init(stored: String) {
        let names = stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        notUsed = Set(names.compactMap(DealsProgram.init(rawValue:)))
    }

    public func setting(_ program: DealsProgram, used: Bool) -> DealsPrograms {
        var set = notUsed
        if used { set.remove(program) } else { set.insert(program) }
        return DealsPrograms(notUsed: set)
    }
}
