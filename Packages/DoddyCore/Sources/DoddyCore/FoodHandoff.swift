import Foundation

/// "Find me sushi and open Wolt" by voice (decision `2026-11-12-food-by-voice`): the agent names one app from
/// `FoodApps.all` and, if it found one, what to search for there. A card shows both; only the tap opens the
/// app (its universal link, or the website). Nothing is ordered, read or sent to the app: the person searches,
/// chooses, pays and orders there themselves. The search words are never put into the link, because the
/// providers don't publish search addresses (decision `2026-11-11-food-button`); they are shown and said.
public struct FoodHandoff: Equatable, Sendable {
    public let app: FoodApp
    /// What to look for in the app (a restaurant or a dish), as the agent wrote it, or nil.
    public let search: String?

    /// The longest search line the card shows.
    public static let searchMaxLength = 80

    public init(app: FoodApp, search: String?) {
        self.app = app
        self.search = search
    }

    public enum Refusal: Error, Equatable, Sendable {
        case missingApp
        case unknownApp(String)
        case searchTooLong
        case searchNotOneLine

        /// What the agent hears: short, with what it can do instead.
        public var reason: String {
            switch self {
            case .missingApp: "missing app; one of: \(FoodHandoff.appNames)"
            case .unknownApp(let name): "Doddy can't open \"\(name)\"; one of: \(FoodHandoff.appNames)"
            case .searchTooLong: "search is longer than \(FoodHandoff.searchMaxLength) characters; give a restaurant or dish name"
            case .searchNotOneLine: "search must be one line of text"
            }
        }
    }

    static var appNames: String { FoodApps.all.map(\.name).joined(separator: ", ") }

    /// The agent's arguments. An empty search is no search; one that isn't one short line is refused rather
    /// than cut, so the card never shows something the agent didn't say.
    public static func parse(app: String?, search: String?) -> Result<FoodHandoff, Refusal> {
        guard let app = app?.trimmingCharacters(in: .whitespacesAndNewlines), !app.isEmpty else { return .failure(.missingApp) }
        guard let found = FoodApps.named(app) else { return .failure(.unknownApp(String(app.prefix(40)))) }
        let words = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if words.isEmpty { return .success(FoodHandoff(app: found, search: nil)) }
        guard !words.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return .failure(.searchNotOneLine)
        }
        guard words.count <= searchMaxLength else { return .failure(.searchTooLong) }
        return .success(FoodHandoff(app: found, search: words))
    }

    /// The card before anything opens (ASK-01): which app, what to search for, and that the order is the
    /// person's own, in the app.
    public func card(polish: Bool) -> AskCard {
        let name = app.name
        var lines: [String] = []
        if let search {
            lines.append(polish ? "Wyszukaj tam: \(search)" : "Search there for: \(search)")
        }
        lines.append(polish
            ? "Wybierasz, płacisz i zamawiasz w \(name). Doddy nie widzi ani nie składa zamówienia."
            : "You choose, pay and order in \(name). Doddy doesn't see or place the order.")
        return AskCard(title: polish ? "Otworzyć \(name)?" : "Open \(name)?", lines: lines,
                       confirmLabel: polish ? "Otwórz \(name)" : "Open \(name)")
    }

    /// What the agent hears once the app opened. "Opened" never means ordered. The search words are the agent's
    /// own, but they go back inside a data block like every other tool's words.
    public var openedReply: String {
        let base = "opened: \(app.name) opened. Nothing was ordered: the user searches, chooses, pays and orders there themselves."
        guard let search else { return base }
        return base + " In one short line, tell them to search there for the words below.\n"
            + ToolData.block([VoiceToolReply.quoted("Search", search)])
    }

    /// What the agent hears when iOS didn't open it.
    public var notOpenedReply: String { VoiceToolReply.notOpened("\(app.name) didn't open.") + " Nothing was ordered." }
}
