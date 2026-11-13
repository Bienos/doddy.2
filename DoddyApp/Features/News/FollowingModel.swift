import DoddyCore
import Foundation
import Observation

// Following (ADR-656), "On my radar" since 10 Nov 2026: what the person follows and the stories behind it,
// right now. The follows live in this iPhone's defaults; each refresh sends them to Doddy's server, which
// fetches the publishers' feeds through its shared cache and keeps nothing about the person. Every card is a
// publisher's own headline, description, picture and link. Nothing on a card is written or chosen by an AI.
//
// The AI summary (owner, 13 Nov 2026): only when the person taps a story, its address and headline go to Doddy's
// server, which reads the article and has Claude Haiku summarise it (`POST /v1/news/summary`). A summary is shown
// only from the server's answer; otherwise the sheet says why there is none.
//
// Alerts (decision 2026-11-10-radar-alerts): "tell me when" words and how to be told are kept on this iPhone
// too. Only for a follow where the person turned on "Let Doddy's server check this for you" does the server
// get that follow (`PUT /v1/news/radar`, the whole list each time); what it found comes back as a list shown
// here, so nothing depends on a notification arriving.

/// What the screen needs from Doddy's server: `DoddyServerClient`.
protocol FollowingBackend: Sendable {
    func newsFeed(_ request: NewsFeedRequest) async throws -> NewsFeedPage
    func newsCatalog(language: String) async throws -> [NewsCatalogTopic]
    func checkFeed(_ url: String) async throws -> FeedCheck
    func radarState() async throws -> RadarServerState
    func saveRadar(_ request: RadarAlertsRequest) async throws -> RadarServerState
    func markRadarSeen(ids: [String]) async throws -> Int
    /// The AI summary of one story (13 Nov 2026): only its address, headline and the app's language are sent.
    func newsSummary(_ request: NewsSummaryRequest) async throws -> NewsSummaryOutcome
}

extension DoddyServerClient: FollowingBackend {}

@MainActor
@Observable
final class FollowingModel {
    static let shared = FollowingModel(backend: { ServerConfig.client() })
    static let storageKey = "news.follows"
    static let alertsKey = "radar.alerts"
    /// Set when the server's list may differ from this iPhone's (a change that didn't reach it); sent again on the next refresh.
    static let needsSyncKey = "radar.needsSync"

    private let backendProvider: @MainActor () -> (any FollowingBackend)?
    private var backend: (any FollowingBackend)? { backendProvider() }
    private let defaults: UserDefaults
    private let now: () -> Date
    private let timeZone: () -> String

    private(set) var follows: NewsFollowList
    private(set) var alerts: RadarAlertList
    private(set) var cards: [NewsCard] = []
    private(set) var reports: [NewsFollowReport] = []
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
    /// The follow whose stories alone are shown (a tap on its circle); nil shows them all.
    var selectedFollowID: String? {
        didSet { if selectedFollowID != oldValue { regroup() } }
    }
    /// What Doddy's server checks for this account and what it found; nil until asked.
    private(set) var radar: RadarServerState?

    /// Whether Doddy's server checks follows, from its own last answer only (decision 2026-11-13-radar-fixes): "Tell me…"
    /// and the server's ways of telling are offered only when it said yes.
    var alertsAvailability: RadarAlertsAvailability { RadarAlertsAvailability(radar) }

    nonisolated static var polish: Bool { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) == .polish }
    var language: String { Self.polish ? "pl" : "en" }

    init(backend: @escaping @MainActor () -> (any FollowingBackend)?, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init, timeZone: @escaping () -> String = { TimeZone.current.identifier }) {
        self.backendProvider = backend
        self.defaults = defaults
        self.now = now
        self.timeZone = timeZone
        let follows = NewsFollowList.decode(defaults.data(forKey: Self.storageKey), polish: Self.polish)
        self.follows = follows
        alerts = RadarAlertList.decode(defaults.data(forKey: Self.alertsKey)).keeping(follows)
    }

    var isServerConfigured: Bool { backend != nil }

    var selectedFollow: NewsFollow? {
        selectedFollowID.flatMap { id in follows.follows.first { $0.id == id } }
    }

    /// The cards on screen: all of them, or only the selected follow's, by the label the server gave it (11 Nov 2026).
    var visibleCards: [NewsCard] {
        guard let follow = selectedFollow else { return cards }
        return NewsFeedLabels.cards(of: follow, in: cards, labels: serverLabels)
    }

    /// Worked out once per change of what is shown, not on every redraw: the grouping parses every card's date.
    private(set) var sections: [NewsFeedSection] = []

    private func regroup() {
        sections = NewsFeedSections.group(visibleCards, now: now())
    }

    /// Follow id → the label the server used for it in the last answer (`NewsFeedLabels`).
    private var serverLabels: [String: String] = [:]
    /// Each refresh gets a number; only the newest one's answer is kept (a pull, the screen opening and a sheet
    /// closing could each start one, and an older answer finishing last used to replace a newer one).
    private var refreshNumber = 0

    /// Catalog topics not followed yet, for the add sheet.
    var availableTopics: [NewsCatalogTopic] {
        catalog.filter { topic in !follows.follows.contains { $0.id == "topic:\(topic.id)" } }
    }

    func report(for follow: NewsFollow) -> NewsFollowReport? {
        let label = serverLabels[follow.id] ?? follow.label
        return reports.first { $0.label == label }
    }

    /// Where a follow's stories come from, from the last refresh or, before one, the catalog.
    func sourcesLine(for follow: NewsFollow) -> String? {
        if let report = report(for: follow) { return report.sourcesLine(polish: Self.polish) }
        if case .topic(let id, _) = follow, let sources = catalog.first(where: { $0.id == id })?.sources, !sources.isEmpty {
            return (Self.polish ? "Źródła: " : "From ") + RadarText.list(sources, polish: Self.polish)
        }
        if let url = follow.feedURL { return URL(string: url)?.host }
        return nil
    }

    func alert(for follow: NewsFollow) -> RadarAlert {
        alerts.alert(for: follow) ?? RadarAlert(followID: follow.id)
    }

    /// The person's "tell me when" words a card mentions, for the small flag on it.
    func flaggedWords(on card: NewsCard) -> [String] {
        let words = follows.follows.filter { card.follows.contains(serverLabels[$0.id] ?? $0.label) }.flatMap { alert(for: $0).words }
        guard !words.isEmpty else { return [] }
        return RadarMatch.matched("\(card.title)\n\(card.summary)", keywords: Array(Set(words)).sorted())
    }

    /// Stories the server's checks found, for one follow or all, newest first.
    func spotted(for follow: NewsFollow?) -> [RadarServerState.Hit] {
        let hits = radar?.hits ?? []
        guard let follow else { return hits }
        return hits.filter { $0.followKey == follow.id }
    }

    func unseenCount(for follow: NewsFollow) -> Int {
        spotted(for: follow).filter { !$0.seen }.count
    }

    // MARK: Follows

    func add(_ follow: NewsFollow) -> Bool {
        let added = follows.add(follow)
        if added { persist() }
        return added
    }

    func remove(id: String) {
        let wasChecked = alerts.alerts[id]?.serverChecks == true
        follows.remove(id: id)
        alerts.remove(followID: id)
        if selectedFollowID == id { selectedFollowID = nil }
        persist()
        persistAlerts()
        if wasChecked { Task { await syncRadar() } }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        follows.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    @discardableResult
    private func persist() -> Bool {
        // A write that fails leaves the previous list in place; the next launch shows that one.
        guard let data = try? follows.encoded() else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return defaults.data(forKey: Self.storageKey) == data
    }

    @discardableResult
    private func persistAlerts() -> Bool {
        guard let data = try? alerts.encoded() else { return false }
        defaults.set(data, forKey: Self.alertsKey)
        return defaults.data(forKey: Self.alertsKey) == data
    }

    /// A follow asked for by voice (ADR-657), after the person tapped Follow on the card. Said as
    /// added only when the list kept on this iPhone reads it back; otherwise nothing changes.
    func follow(_ ask: NewsFollowAsk) -> NewsFollowOutcome {
        var list = follows
        let outcome = NewsFollowOutcome.apply(ask.follow(polish: Self.polish), to: &list)
        guard case .added(let follow) = outcome else { return outcome }
        let before = follows
        follows = list
        guard persist(),
              NewsFollowList.decode(defaults.data(forKey: Self.storageKey), polish: Self.polish).follows.contains(where: { $0.id == follow.id })
        else {
            follows = before
            persist()
            return .notKept
        }
        return outcome
    }

    // MARK: Adding and alerts

    enum AddOutcome: Equatable {
        /// On the radar, as asked.
        case added
        /// On the radar, but the server couldn't take the check: it shows here only, and the reason says why.
        case addedHereOnly(String)
        case notAdded(String)
    }

    /// Adds a follow with its alert. A follow the server should check is sent there first; if the server can't
    /// take it the follow is still added, shown here only, and the person is told why. Never says "checked" unless
    /// the server's answer lists it.
    func addToRadar(_ follow: NewsFollow, alert: RadarAlert) async -> AddOutcome {
        message = nil
        guard add(follow) else {
            return .notAdded(NSLocalizedString("You already follow that, or you follow ten things already.", comment: ""))
        }
        selectedFollowID = follow.id
        return await apply(alert, to: follow) ? .added : .addedHereOnly(radarProblem ?? "")
    }

    /// Why the last change to the server's checks didn't go through.
    private(set) var radarProblem: String?

    /// Keeps a follow's alert. A server check is said to be on only when the server's answer lists it; otherwise
    /// the alert is kept as "here only" and `radarProblem` says why.
    @discardableResult
    func apply(_ alert: RadarAlert, to follow: NewsFollow) async -> Bool {
        let before = alerts.alert(for: follow)
        alerts.set(RadarAlert(followID: follow.id, words: alert.words, how: alert.how, dailyTime: alert.dailyTime))
        persistAlerts()
        guard alert.serverChecks || before?.serverChecks == true else {
            radarProblem = nil
            return true
        }
        let synced = await syncRadar()
        if alert.serverChecks, !(radar?.alerts.contains { $0.followKey == follow.id } ?? false) {
            // Not taken: kept here only, never shown as checked.
            alerts.set(RadarAlert(followID: follow.id, words: alert.words, how: .app, dailyTime: alert.dailyTime))
            persistAlerts()
            if synced, radarProblem == nil {
                radarProblem = NSLocalizedString("Doddy's server didn't keep this check, so it shows here only.", comment: "")
            }
            return false
        }
        return synced
    }

    /// Sends exactly the follows the person let the server check (an empty list turns every check off there).
    @discardableResult
    func syncRadar() async -> Bool {
        guard let backend else {
            radarProblem = NSLocalizedString("On my radar needs a Doddy messaging server.", comment: "")
            return false
        }
        let request = alerts.keeping(follows).request(follows, language: language, timeZone: timeZone())
        do {
            radar = try await backend.saveRadar(request)
            radarProblem = nil
            defaults.set(false, forKey: Self.needsSyncKey)
            return true
        } catch {
            radarProblem = Self.radarText(for: error)
            defaults.set(true, forKey: Self.needsSyncKey)
            return false
        }
    }

    static func radarText(for error: any Error) -> String {
        if case .notConfigured("radar_disabled")? = error as? ServerError {
            return NSLocalizedString("Doddy's server doesn't check follows for anyone yet, so this one shows here only.", comment: "")
        }
        return UpdatesModel.text(for: error)
    }

    /// Asks the server what it checks and what it found. A change that didn't reach it earlier is sent first; if the
    /// server refused it (for example because it checks nothing yet), it is still asked what it holds, so the screen
    /// knows whether to offer alerts at all (13 Nov 2026: before, a refused send left that unknown).
    func loadRadar() async {
        guard let backend else { return }
        if defaults.bool(forKey: Self.needsSyncKey), await syncRadar() { return }
        if let state = try? await backend.radarState() { radar = state }
    }

    /// The person has seen these stories: the "new" dot goes.
    func markSeen(_ hits: [RadarServerState.Hit]) async {
        let ids = hits.filter { !$0.seen }.map(\.id)
        guard let backend, !ids.isEmpty else { return }
        if (try? await backend.markRadarSeen(ids: ids)) != nil, let state = try? await backend.radarState() { radar = state }
    }

    /// Checks an own feed before it is added: the server fetches it once, safely, and says what it is.
    func checkFeed(_ url: String) async -> FeedCheckOutcome {
        guard let backend else { return .failed(NSLocalizedString("On my radar needs a Doddy messaging server.", comment: "")) }
        do {
            return .ok(try await backend.checkFeed(url))
        } catch {
            return .failed(UpdatesModel.text(for: error))
        }
    }

    enum FeedCheckOutcome {
        case ok(FeedCheck)
        /// Why, in words for the person.
        case failed(String)
    }

    // MARK: The feed

    func refresh() async {
        guard let backend else { return }
        refreshNumber += 1
        let mine = refreshNumber
        guard let request = follows.request(language: language) else {
            cards = []
            reports = []
            serverLabels = [:]
            problem = nil
            regroup()
            return
        }
        let requested = follows.follows
        isLoading = true
        problem = nil
        do {
            let page = try await backend.newsFeed(request)
            guard mine == refreshNumber else { return }
            cards = page.cards
            reports = page.follows ?? []
            serverLabels = NewsFeedLabels.byFollow(requested: requested, reports: reports)
            keywordSearch = page.keywordSearch
            fetchedAt = ServerDates.parse(page.fetchedAt) ?? now()
        } catch {
            guard mine == refreshNumber else { return }
            problem = UpdatesModel.text(for: error)
        }
        regroup()
        isLoading = false
        await loadRadar()
    }

    /// The last try to load Doddy's list failed, so the Sources list says so instead of loading forever.
    private(set) var catalogFailed = false

    func loadCatalog() async {
        guard let backend, catalog.isEmpty else { return }
        catalogFailed = false
        do {
            catalog = try await backend.newsCatalog(language: language)
        } catch {
            catalogFailed = true
        }
    }

    /// The catalog topic a topic follow stands for, once the catalog is loaded.
    func catalogTopic(for follow: NewsFollow) -> NewsCatalogTopic? {
        guard let id = follow.catalogID else { return nil }
        return catalog.first { $0.id == id }
    }

    func isFollowing(topicID: String) -> Bool {
        follows.follows.contains { $0.id == "topic:\(topicID)" }
    }

    // MARK: The AI summary of a story

    enum SummaryState: Equatable {
        case loading
        /// Written by the server's model; shown with its label.
        case ready(NewsSummary)
        /// There is no summary, and asking again won't change that soon; the words say why.
        case unavailable(String)
        /// Something went wrong on the way; asking again may work.
        case failed(String)
    }

    /// Summaries the server wrote in this session, by card id, so opening a story again doesn't ask again.
    private(set) var summaries: [String: NewsSummary] = [:]

    /// Asks Doddy's server for the story's summary. Only its address, its headline and the app's language are sent.
    func summary(for card: NewsCard) async -> SummaryState {
        if let kept = summaries[card.id] { return .ready(kept) }
        guard card.link != nil else {
            return .unavailable(NSLocalizedString("This story has no web address, so there's nothing for Doddy's server to read.", comment: ""))
        }
        guard let backend else {
            return .unavailable(NSLocalizedString("Summaries need a Doddy messaging server, and none is connected in this build yet.", comment: ""))
        }
        do {
            switch try await backend.newsSummary(NewsSummaryRequest(card: card, language: language)) {
            case .summary(let summary):
                summaries[card.id] = summary
                return .ready(summary)
            case .unreadable(let reason):
                return .unavailable(Self.unreadableText(reason))
            case .limitReached(let serverWide):
                return .unavailable(serverWide
                    ? NSLocalizedString("Doddy's server has written all the summaries it can today. The full article still opens below.", comment: "")
                    : NSLocalizedString("You've used today's summaries. They're back tomorrow; the full article still opens below.", comment: ""))
            case .notConfigured:
                return .unavailable(NSLocalizedString("Summaries aren't set up on Doddy's server yet, so none was written. The full article still opens below.", comment: ""))
            }
        } catch ServerError.unsafeURL {
            return .unavailable(NSLocalizedString("Doddy's server only reads secure public web addresses (https), and this story's isn't one.", comment: ""))
        } catch {
            return .failed(Self.summaryErrorText(error))
        }
    }

    static func unreadableText(_ reason: NewsSummaryUnreadable?) -> String {
        switch reason {
        case .paywall?:
            return NSLocalizedString("This article is behind the publisher's paywall, so Doddy didn't summarise it.", comment: "")
        case .blocked?:
            return NSLocalizedString("The publisher's site didn't let Doddy's server in (a sign-in or a bot check), so there's no summary.", comment: "")
        case .notAllowed?:
            return NSLocalizedString("The publisher asks automated readers and AI not to use this page, so Doddy didn't.", comment: "")
        case .unreachable?:
            return NSLocalizedString("Doddy's server couldn't load this article right now. Try again later, or read it on the publisher's site.", comment: "")
        case .notArticle?, .tooShort?:
            return NSLocalizedString("There isn't enough article text on that page to summarise. It may be a video, a live page or a teaser.", comment: "")
        case nil:
            return NSLocalizedString("Doddy's server couldn't read this article, so there's no summary.", comment: "")
        }
    }

    static func summaryErrorText(_ error: any Error) -> String {
        if case .providerUnavailable? = error as? ServerError {
            return NSLocalizedString("The summary couldn't be written this time. Try again in a moment.", comment: "")
        }
        return UpdatesModel.text(for: error)
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
