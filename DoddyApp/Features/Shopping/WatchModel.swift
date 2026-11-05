import DoddyCore
import Foundation
import Observation

// Price watch (docs/implementation/SHOPPING_WATCH.md, ADR-614): "Pilnuj ceny" on a pick. The rules and
// every sentence live in DoddyCore (Watch.swift, WatchesClient.swift), where Linux tests hold them, and
// on the server, which checks everything again. Nothing here says a price is watched, stopped or deleted
// unless the server said so: the list is only what `GET /v1/watches` returned, an approval whose answer
// never came back is looked up on the server instead of guessed, and "dropped" is only said by
// `WatchWords` with the price the server confirmed. Nothing is bought, and no model is involved.

/// What the watch screens need from Doddy's server: `DoddyServerClient`.
protocol WatchesBackend: Sendable {
    /// True once this iPhone has an account on the messaging server. Checking never creates one.
    func hasAccount() async -> Bool
    func createWatch(_ draft: PriceWatchDraft) async throws -> WatchPreview
    func approveWatch(_ id: UUID, digest: String) async throws -> WatchApproval
    func watches() async throws -> [WatchSummary]
    func watch(_ id: UUID) async throws -> WatchSummary
    func stopWatch(_ id: UUID) async throws
    func deleteWatch(_ id: UUID) async throws
}

extension DoddyServerClient: WatchesBackend {}

@MainActor
@Observable
final class WatchModel {
    /// One model for the card under a pick and the list on the Tasks screen, so they never disagree. The
    /// server is looked up each time, so a server address set after launch is used.
    static let shared = WatchModel(backend: { ServerConfig.client() }, registerForPush: { await WatchPush.register() })

    /// Where the card is. Only `started` says the server confirmed the watch is active.
    enum Phase: Equatable {
        case idle
        /// The server is reading the shop's page to make a draft.
        case reading
        /// The server's draft is on the card, waiting for the user's yes. Nothing is watched.
        case preview(PriceWatchDraft, WatchPreview)
        /// The yes was sent; waiting for the server's answer.
        case starting(PriceWatchDraft, WatchPreview)
        /// The server said the watch is active.
        case started(PriceWatchDraft)
        /// The yes was sent and the server's answer never came back (and a look-up couldn't settle it).
        /// The card says so; it isn't sent again by itself.
        case unsure

        var isInFlight: Bool {
            switch self {
            case .reading, .starting: true
            default: false
            }
        }
    }

    private let backendProvider: @MainActor () -> (any WatchesBackend)?
    private let isPaused: @MainActor () -> Bool
    private let registerForPush: @MainActor () async -> Void
    private var backend: (any WatchesBackend)? { backendProvider() }
    private var language: NotificationLanguage { NotificationLanguage.current }

    private(set) var phase: Phase = .idle
    /// The last refusal on the card, in words. Cleared when the user tries again.
    private(set) var problem: String?

    /// Exactly what the server last listed, newest first.
    private(set) var watches: [WatchSummary] = []
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    /// Why the list couldn't be read. A failed read never shows as "no watches".
    private(set) var loadProblem: String?
    /// Watches with a stop or a delete on its way, so a second tap doesn't send a second request.
    private(set) var busy: Set<UUID> = []
    /// What a stop or a delete couldn't do, in words.
    var message: String?

    init(backend: @escaping @MainActor () -> (any WatchesBackend)?,
         isPaused: @escaping @MainActor () -> Bool = { UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) },
         registerForPush: @escaping @MainActor () async -> Void = {}) {
        self.backendProvider = backend
        self.isPaused = isPaused
        self.registerForPush = registerForPush
    }

    var isServerConfigured: Bool { backend != nil }

    // MARK: The card: draft, preview, approval

    /// A card opens: whatever an earlier card left behind is cleared, unless a request of it is still on its way.
    func beginCard() {
        guard !phase.isInFlight else { return }
        phase = .idle
        problem = nil
    }

    /// The card closes. A draft that was never approved is removed from the server, so it doesn't keep the
    /// title and the page address for the ten minutes it would live; if that can't be done it lapses by itself.
    func cardClosed() async {
        guard case .preview(_, let preview) = phase else { return }
        phase = .idle
        problem = nil
        try? await backend?.deleteWatch(preview.id)
    }

    /// Step one: the server reads the page once and holds a draft of exactly these words. Nothing is watched,
    /// and nothing is sent while Connections are paused. The draft is shown only when the server's copy is
    /// for exactly what the user typed (`createWatch` checks the echo and the digest).
    func start(_ draft: PriceWatchDraft) async {
        guard case .idle = phase else { return }
        problem = nil
        guard !isPaused() else {
            problem = WatchWords.paused(language)
            return
        }
        guard let backend else {
            problem = WatchWords.noServer(language)
            return
        }
        phase = .reading
        do {
            let preview = try await backend.createWatch(draft)
            phase = .preview(draft, preview)
        } catch {
            phase = .idle
            problem = WatchWords.problem(error, currency: draft.currency, language)
        }
    }

    /// Step two, on the user's tap: approves the draft with the digest of the words the card showed. The
    /// card says "watching" only when the server said so; no answer is looked up, never guessed, and the
    /// approval is never sent a second time by itself.
    func approve() async {
        guard case .preview(let draft, let preview) = phase else { return }
        // The yes is bound to these words: the digest the server holds must be the draft's own.
        guard preview.matches(draft) else {
            phase = .idle
            problem = WatchWords.problem(WatchError.previewMismatch, language)
            return
        }
        guard let backend else {
            problem = WatchWords.noServer(language)
            return
        }
        phase = .starting(draft, preview)
        let approval: WatchApproval
        do {
            approval = try await backend.approveWatch(preview.id, digest: draft.digest)
        } catch {
            // Nothing was started: the server refused, or the request never left this iPhone.
            phase = .idle
            problem = WatchWords.problem(error, currency: draft.currency, language)
            return
        }
        if approval.isConfirmed {
            phase = .started(draft)
            problem = nil
            await refresh()
            await registerForPush()
        } else {
            await settle(preview, draft: draft, backend: backend)
        }
    }

    /// The user said no on the preview: nothing was approved, and the draft is removed from the server.
    func decline() async {
        await cardClosed()
    }

    /// The approval had no answer we can trust. A read-only look-up of that one watch says what the server
    /// holds: active is watching; a draft still waiting means the yes never arrived; anything else is said
    /// as "not sure" and the list shows the server's word.
    private func settle(_ preview: WatchPreview, draft: PriceWatchDraft, backend: any WatchesBackend) async {
        let held = try? await backend.watch(preview.id)
        if held?.state == .active {
            phase = .started(draft)
            problem = nil
            await refresh()
            await registerForPush()
        } else if held?.state == .draft {
            // The server never got the yes. The draft is still there, so the user can say yes again.
            phase = .preview(draft, preview)
            problem = WatchWords.notStartedYet(language)
        } else {
            phase = .unsure
            problem = nil
            await refresh()
        }
    }

    // MARK: The list

    /// Asks the server for the watches. Opening the list never makes a server account: with none, there is
    /// nothing to ask about.
    func refresh() async {
        guard let backend, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard await backend.hasAccount() else {
            watches = []
            loadProblem = nil
            hasLoaded = true
            return
        }
        do {
            watches = try await backend.watches()
            loadProblem = nil
        } catch {
            // The list stays as it was; the screen says it couldn't be refreshed.
            loadProblem = WatchWords.problem(error, language)
        }
        hasLoaded = true
    }

    /// Stops an active watch. The row says "stopped" only after the server's `204`; a refusal is said in
    /// words and the list is read again, so it shows what the server holds.
    func stop(_ id: UUID) async {
        guard let backend else {
            message = WatchWords.noServer(language)
            return
        }
        guard !busy.contains(id) else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        message = nil
        do {
            try await backend.stopWatch(id)
        } catch {
            message = WatchWords.problem(error, language)
            await refresh()
            return
        }
        if let index = watches.firstIndex(where: { $0.id == id }) { watches[index] = watches[index].stopped() }
        await refresh()
    }

    /// Deletes a watch in any state. It leaves the list only after the server's `204` (or its word that it has
    /// no such watch); a refusal is said in words and nothing is removed.
    func delete(_ id: UUID) async {
        guard let backend else {
            message = WatchWords.noServer(language)
            return
        }
        guard !busy.contains(id) else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        message = nil
        do {
            try await backend.deleteWatch(id)
        } catch {
            message = WatchWords.problem(error, language)
            return
        }
        watches.removeAll { $0.id == id }
    }
}
