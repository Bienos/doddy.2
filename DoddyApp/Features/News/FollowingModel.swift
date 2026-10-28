import DoddyCore
import Foundation
import Observation

// Following (ADR-656): what the person follows and the stories behind it, right now. The follows
// live in this iPhone's defaults; each refresh sends them to Doddy's server, which fetches the
// publishers' feeds through its shared cache and keeps nothing about the person. Every card is a
// publisher's own headline, summary, picture and link. Nothing here is written or chosen by an AI.

/// What the screen needs from Doddy's server: `DoddyServerClient`.
protocol FollowingBackend: Sendable {
    func newsFeed(_ request: NewsFeedRequest) async throws -> NewsFeedPage
    func newsCatalog(language: String) async throws -> [NewsCatalogTopic]
}

extension DoddyServerClient: FollowingBackend {}

@MainActor
@Observable
final class FollowingModel {
    static let shared = FollowingModel(backend: { ServerConfig.client() })
    static let storageKey = "news.follows"

    private let backendProvider: @MainActor () -> (any FollowingBackend)?
    private var backend: (any FollowingBackend)? { backendProvider() }
    private let defaults: UserDefaults
    private let now: () -> Date

    private(set) var follows: NewsFollowList
    private(set) var cards: [NewsCard] = []
    private(set) var catalog: [NewsCatalogTopic] = []
    /// When the cards were fetched; nil until the first answer. Cards are never shown as newer than this.
    private(set) var fetchedAt: Date?
    private(set) var keywordSearch = false
    private(set) var isLoading = false
    /// Why the last refresh gave nothing. Shown next to whatever cards are still on screen.
    private(set) var problem: String?
    /// One-line confirmations ("Saved to your notes"), cleared on the next action.
    var message: String?
    /// Ids of stories saved to notes in this session, so the bookmark fills in.
    private(set) var savedStoryIDs: Set<String> = []

    nonisolated static var polish: Bool { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) == .polish }
    var language: String { Self.polish ? "pl" : "en" }

    init(backend: @escaping @MainActor () -> (any FollowingBackend)?, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.backendProvider = backend
        self.defaults = defaults
        self.now = now
        follows = NewsFollowList.decode(defaults.data(forKey: Self.storageKey), polish: Self.polish)
    }

    var isServerConfigured: Bool { backend != nil }

    var sections: [NewsFeedSection] { NewsFeedSections.group(cards, now: now()) }

    /// Catalog topics not followed yet, for the add sheet.
    var availableTopics: [NewsCatalogTopic] {
        catalog.filter { topic in !follows.follows.contains { $0.id == "topic:\(topic.id)" } }
    }

    // MARK: Follows

    func add(_ follow: NewsFollow) -> Bool {
        let added = follows.add(follow)
        if added { persist() }
        return added
    }

    func remove(id: String) {
        follows.remove(id: id)
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        follows.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        // A write that fails leaves the previous list in place; the next launch shows that one.
        if let data = try? follows.encoded() { defaults.set(data, forKey: Self.storageKey) }
    }

    // MARK: The feed

    func refresh() async {
        guard let backend else { return }
        guard let request = follows.request(language: language) else {
            cards = []
            problem = nil
            return
        }
        isLoading = true
        problem = nil
        defer { isLoading = false }
        do {
            let page = try await backend.newsFeed(request)
            cards = page.cards
            keywordSearch = page.keywordSearch
            fetchedAt = ServerDates.parse(page.fetchedAt) ?? now()
        } catch {
            problem = UpdatesModel.text(for: error)
        }
    }

    func loadCatalog() async {
        guard let backend, catalog.isEmpty else { return }
        catalog = (try? await backend.newsCatalog(language: language)) ?? []
    }

    // MARK: Keeping a story

    /// Saves the headline, publisher and link as a note on this iPhone. "Saved" only after the store
    /// returned the record; a failure says so and saves nothing.
    func save(_ card: NewsCard, repository: any MemoryRepository = AppEnvironment.shared.memoryRepository) async {
        message = nil
        do {
            let draft = try NewMemory(text: card.noteText, category: .other, source: .explicitText, capturedAt: now())
            _ = try await repository.save(draft)
            savedStoryIDs.insert(card.id)
            message = NSLocalizedString("Saved to your notes.", comment: "")
        } catch {
            message = NSLocalizedString("Couldn't save this story. Nothing was kept.", comment: "")
        }
    }
}
