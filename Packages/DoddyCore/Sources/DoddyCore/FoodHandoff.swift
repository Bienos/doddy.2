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
    /// The restaurant's own page on that app, checked by `FoodApp.page`, or nil to open the app's front page.
    public let page: URL?

    /// What opens on the tap: the restaurant's page, or else the app's front page.
    public var openURL: URL { page ?? app.url }

    /// The longest search line the card shows.
    public static let searchMaxLength = 80

    public init(app: FoodApp, search: String?, page: URL? = nil) {
        self.app = app
        self.search = search
        self.page = page
    }

    public enum Refusal: Error, Equatable, Sendable {
        case missingApp
        case unknownApp(String)
        case searchTooLong
        case searchNotOneLine
        case pageNotOfApp(String)

        /// What the agent hears: short, with what it can do instead.
        public var reason: String {
            switch self {
            case .missingApp: "missing app; one of: \(FoodHandoff.appNames)"
            case .unknownApp(let name): "Doddy can't open \"\(name)\"; one of: \(FoodHandoff.appNames)"
            case .searchTooLong: "search is longer than \(FoodHandoff.searchMaxLength) characters; give a restaurant or dish name"
            case .searchNotOneLine: "search must be one line of text"
            case .pageNotOfApp(let name): "page isn't a restaurant page on \(name); use only an address a search result gave as an order page for \(name), or leave page out"
            }
        }
    }

    static var appNames: String { FoodApps.all.map(\.name).joined(separator: ", ") }

    /// The agent's arguments. An empty search is no search; one that isn't one short line is refused rather
    /// than cut, so the card never shows something the agent didn't say.
    public static func parse(app: String?, search: String?, page: String? = nil) -> Result<FoodHandoff, Refusal> {
        guard let app = app?.trimmingCharacters(in: .whitespacesAndNewlines), !app.isEmpty else { return .failure(.missingApp) }
        guard let found = FoodApps.named(app) else { return .failure(.unknownApp(String(app.prefix(40)))) }
        // A page that isn't on this app's own host is refused, not ignored: the card would say one app and open another.
        var pageURL: URL?
        if let page = page?.trimmingCharacters(in: .whitespacesAndNewlines), !page.isEmpty {
            guard let valid = found.page(from: page) else { return .failure(.pageNotOfApp(found.name)) }
            pageURL = valid
        }
        let words = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if words.isEmpty { return .success(FoodHandoff(app: found, search: nil, page: pageURL)) }
        guard !words.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return .failure(.searchNotOneLine)
        }
        guard words.count <= searchMaxLength else { return .failure(.searchTooLong) }
        return .success(FoodHandoff(app: found, search: words, page: pageURL))
    }

    /// The card before anything opens (ASK-01): which app, what to search for, and that the order is the
    /// person's own, in the app.
    public func card(polish: Bool) -> AskCard {
        let name = app.name
        var lines: [String] = []
        // The page that will open, as the address says it (host and path), so the person sees where they land.
        if let page {
            let where_ = (page.host ?? "") + page.path
            lines.append(polish ? "Otworzy się strona: \(where_)" : "Opens this page: \(where_)")
        }
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
        let base = "opened: \(app.name) opened\(page == nil ? "" : " on the restaurant's page"). Nothing was ordered: the user "
            + (page == nil ? "searches, chooses, pays and orders" : "chooses, pays and orders") + " there themselves."
        guard let search else { return base }
        let say = page == nil ? " In one short line, tell them to search there for the words below.\n"
                              : " In one short line, say what to look for on its menu: the words below.\n"
        return base + say
            + ToolData.block([VoiceToolReply.quoted("Search", search)])
    }

    /// What the agent hears when iOS didn't open it.
    public var notOpenedReply: String { VoiceToolReply.notOpened("\(app.name) didn't open.") + " Nothing was ordered." }
}
