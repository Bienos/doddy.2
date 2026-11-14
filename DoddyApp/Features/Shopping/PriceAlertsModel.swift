import DoddyCore
import Foundation
import Observation

// Price alerts (owner, 13 Nov 2026: "daj znać, gdy masło będzie poniżej 5 zł"; decision 2026-11-14-price-alerts-screen).
// The app's side of the server's deal watches. The rules and every sentence live in DoddyCore (DealWatchesClient.swift,
// DealWatchWords.swift), where Linux tests hold them, and on the server, which checks everything again. Nothing here
// says an alert is saved, found or deleted unless the server's answer said so: the list is only what
// `GET /v1/deal-watches` returned, a make whose answer never came back is said to be unknown and looked up on the
// server instead of guessed, and what an alert found is read from the server's catalog when the screen opens. The
// feature is off on the server until the owner turns it on (`DEAL_WATCHES_ENABLED`): while it is off, the Shopping
// screen shows nothing about it (`availability`), and nothing is stored on this iPhone.

/// What the price-alert screens need from Doddy's server: `DoddyServerClient`.
protocol PriceAlertsBackend: Sendable {
    /// True once this iPhone has an account on the messaging server. Checking never creates one.
    func hasAccount() async -> Bool
    func dealWatches() async throws -> DealWatchList
    func createDealWatch(_ request: DealWatchRequest) async throws -> DealWatchCreated
    func dealWatchMatches(id: String) async throws -> DealWatchMatches
    func deleteDealWatch(id: String) async throws
}

extension DoddyServerClient: PriceAlertsBackend {}

@MainActor
@Observable
final class PriceAlertsModel {
    /// One model for the Shopping row, the list and the form, so they never disagree. The server is looked up each
    /// time, so a server address set after launch is used.
    static let shared = PriceAlertsModel(backend: { ServerConfig.client() })

    /// Whether the server keeps price alerts at all. Unknown until the list was read; `off` when the server said they
    /// are switched off. Only `available` shows anything on the Shopping screen.
    enum Availability: Equatable {
        case unknown, available, off
    }

    /// Where the add form is. Only `saved` says the server confirmed the alert.
    enum Phase: Equatable {
        case idle
        /// The request is on its way.
        case saving
        /// The server answered `201` and the answer was read: the alert, and what already matches (never pushed).
        case saved(DealWatchCreated)
    }

    /// What reading an alert's matches came to.
    enum MatchesOutcome: Equatable {
        case loaded(DealWatchMatches)
        case problem(String)
    }

    private let backendProvider: @MainActor () -> (any PriceAlertsBackend)?
    private let isPaused: @MainActor () -> Bool
    private var backend: (any PriceAlertsBackend)? { backendProvider() }
    private var language: NotificationLanguage { NotificationLanguage.current }

    private(set) var availability: Availability = .unknown
    /// Exactly what the server last listed, newest first.
    private(set) var watches: [DealWatch] = []
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    /// Why the list couldn't be read. A failed read never shows as "no alerts".
    private(set) var loadProblem: String?
    /// Alerts with a delete on its way, so a second tap doesn't send a second request.
    private(set) var busy: Set<String> = []
    /// What a delete couldn't do, in words.
    var message: String?

    private(set) var phase: Phase = .idle
    /// The last refusal on the form, in words. Cleared when the person tries again.
    private(set) var problem: String?

    init(backend: @escaping @MainActor () -> (any PriceAlertsBackend)?,
         isPaused: @escaping @MainActor () -> Bool = { UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) }) {
        self.backendProvider = backend
        self.isPaused = isPaused
    }

    var isServerConfigured: Bool { backend != nil }

    // MARK: The list

    /// Asks the server for the alerts. Opening the list never makes a server account: with none, there is nothing to
    /// ask about. Nothing is sent while Connections are paused.
    func refresh() async {
        guard let backend, !isRefreshing else { return }
        guard !isPaused() else {
            loadProblem = DealWatchWords.paused(language)
            hasLoaded = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        guard await backend.hasAccount() else {
            watches = []
            loadProblem = nil
            hasLoaded = true
            return
        }
        do {
            watches = try await backend.dealWatches().watches
            availability = .available
            loadProblem = nil
        } catch DealWatchesError.disabled {
            watches = []
            availability = .off
            loadProblem = nil
        } catch {
            // The list stays as it was; the screen says it couldn't be refreshed.
            loadProblem = DealWatchWords.refusal(Self.watchesError(error), language)
        }
        hasLoaded = true
    }

    // MARK: The form

    /// The form opens: whatever an earlier try left behind is cleared, unless a request of it is still on its way.
    func beginForm() {
        guard phase != .saving else { return }
        phase = .idle
        problem = nil
    }

    /// Makes an alert from what the person typed. `priceText` empty means any price; text that isn't a price is said
    /// and nothing is sent. `chains` empty means every shop with leaflets.
    func add(item: String, priceText: String, chains: [DealsChain]) async {
        guard phase == .idle else { return }
        problem = nil
        var maxPriceMinor: Int?
        let trimmedPrice = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrice.isEmpty {
            guard let minor = PriceWatchDraft.parseThresholdMinor(trimmedPrice) else {
                problem = DealWatchWords.priceProblem(language)
                return
            }
            maxPriceMinor = minor
        }
        let request = DealWatchRequest(item: item, maxPriceMinor: maxPriceMinor, chains: chains.isEmpty ? nil : chains,
                                       language: language == .polish ? "pl" : "en")
        guard request.isValid else {
            problem = DealWatchWords.refusal(.invalid(fields: request.validationIssues().map(\.field)), language)
            return
        }
        guard !isPaused() else {
            problem = DealWatchWords.paused(language)
            return
        }
        guard let backend else {
            problem = DealWatchWords.noServer(language)
            return
        }
        phase = .saving
        do {
            let created = try await backend.createDealWatch(request)
            availability = .available
            watches.removeAll { $0.id == created.watch.id }
            watches.insert(created.watch, at: 0)
            phase = .saved(created)
        } catch {
            phase = .idle
            let refused = Self.watchesError(error)
            problem = DealWatchWords.refusal(refused, language)
            switch refused {
            case .disabled:
                availability = .off
            case .outcomeUnknown:
                // It may exist: the list is read again, so the person sees what the server holds.
                await refresh()
            default:
                break
            }
        }
    }

    // MARK: One alert

    /// Deletes an alert. The row goes only after the server's answer (`204`, or "already gone"); a refusal is said in
    /// words and the list is read again, so it shows what the server holds.
    func delete(_ watch: DealWatch) async {
        guard let backend else {
            message = DealWatchWords.noServer(language)
            return
        }
        guard !isPaused() else {
            message = DealWatchWords.paused(language)
            return
        }
        guard !busy.contains(watch.id) else { return }
        busy.insert(watch.id)
        defer { busy.remove(watch.id) }
        message = nil
        do {
            try await backend.deleteDealWatch(id: watch.id)
            watches.removeAll { $0.id == watch.id }
        } catch {
            message = DealWatchWords.refusal(Self.watchesError(error), language)
            await refresh()
        }
    }

    /// What the alert's item matches in the catalog now, read from the server each time the screen opens.
    func matches(for watch: DealWatch) async -> MatchesOutcome {
        guard let backend else { return .problem(DealWatchWords.noServer(language)) }
        guard !isPaused() else { return .problem(DealWatchWords.paused(language)) }
        do {
            return .loaded(try await backend.dealWatchMatches(id: watch.id))
        } catch {
            return .problem(DealWatchWords.refusal(Self.watchesError(error), language))
        }
    }

    private static func watchesError(_ error: any Error) -> DealWatchesError {
        error as? DealWatchesError ?? .server(.offline)
    }
}
