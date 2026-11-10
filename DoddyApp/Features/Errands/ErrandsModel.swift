import DoddyCore
import Foundation
import Observation
import UserNotifications

// Tasks the user hands Doddy (ADR-570, docs/implementation/ERRANDS.md). The rules live in DoddyCore
// and on the server, which checks everything again. Nothing here says a task started, finished or
// was deleted unless the server or the store said so: a hand-over whose answer never came back is
// "unknown", and a result is acknowledged (so the server deletes its copy) only after it was saved
// on this iPhone and read back.

/// What the task screens and the voice controller need from Doddy's server: `DoddyServerClient`.
protocol ErrandsBackend: Sendable {
    /// True once this iPhone has an account on the messaging server. Checking never creates one.
    func hasAccount() async -> Bool
    func createErrand(_ draft: ErrandDraft) async throws -> ErrandPreview
    func approveErrand(_ id: UUID, digest: String) async throws -> ErrandApproval
    func errands() async throws -> [ErrandSummary]
    func errand(_ id: UUID) async throws -> ErrandSnapshot
    func cancelErrand(_ id: UUID) async throws
    func acknowledgeErrand(_ id: UUID, resultDigest: String) async throws -> [ErrandDeletion]
    func deleteErrand(_ id: UUID) async throws
}

extension DoddyServerClient: ErrandsBackend {}

@MainActor
@Observable
final class ErrandsModel {
    /// One model for the voice controller, Home and the Tasks screen, so they never disagree.
    /// The server is looked up each time, so a server address set after launch is used.
    static let shared = ErrandsModel(backend: { ServerConfig.client() }, repository: AppEnvironment.shared.errandRepository)

    private let backendProvider: @MainActor () -> (any ErrandsBackend)?
    private var backend: (any ErrandsBackend)? { backendProvider() }
    private let repository: any ErrandRepository
    private let defaults: UserDefaults

    private(set) var errands: [StoredErrand] = []
    /// Why the tasks kept on this iPhone couldn't be read. A failed read never shows as "no tasks".
    private(set) var loadProblem: String?
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    var message: String?

    /// Finished since the user last looked (Home's card). Ids only, in UserDefaults.
    private(set) var unseenFinished: [UUID] = []
    private static let unseenKey = "errands.unseenFinished"

    init(backend: @escaping @MainActor () -> (any ErrandsBackend)?, repository: any ErrandRepository, defaults: UserDefaults = .standard) {
        self.backendProvider = backend
        self.repository = repository
        self.defaults = defaults
        unseenFinished = (defaults.stringArray(forKey: Self.unseenKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    var isServerConfigured: Bool { backend != nil }

    func errand(_ id: UUID) -> StoredErrand? { errands.first { $0.id == id } }

    #if DEBUG
    /// Test seam only (ADR-821, the screens run): tasks finished since the user last looked, in
    /// memory only, so Home shows its "Done" card.
    func seedUnseenForTesting(_ ids: [UUID]) {
        unseenFinished = ids
    }
    #endif

    /// The newest finished task the user hasn't opened yet, for Home.
    var newestUnseen: StoredErrand? {
        errands.first { unseenFinished.contains($0.id) && $0.state.isFinished }
    }

    func load() async {
        do {
            errands = try await repository.list()
            loadProblem = nil
        } catch {
            loadProblem = UserFacingError.message(for: error)
        }
        hasLoaded = true
    }

    // MARK: Hand-over (after the user's tap: the voice tool's card, or the Tasks screen's)

    /// What a hand-over came to. Only `started` means Doddy's server said it has the task.
    enum HandOverOutcome {
        case started
        /// The approval's answer never came back: it may be running. Never approved again by itself.
        case maybeStarted
        case notStarted(any Error)
        /// Refused here before anything was sent (a link, a missing or too long text).
        case invalid(ErrandDraftIssue)
        /// "Pause all connections" is on: nothing was sent (Tasks screen only; the voice tools are gated before this).
        case paused
        /// A hand-over from the Tasks screen is already on its way: nothing more was sent.
        case alreadySending
    }

    /// Set while the Tasks screen's hand-over is on its way, so a second tap sends nothing.
    private(set) var isHandingOver = false

    /// The voice tool: the same hand-over, as the tool result for the agent.
    func handOver(_ draft: ErrandDraft, now: Date = Date()) async -> String {
        switch await submit(draft, now: now) {
        case .started: VoiceToolReply.errandStarted(draft)
        case .maybeStarted: VoiceToolReply.errandMaybeStarted(draft)
        case .notStarted(let error): VoiceToolReply.errandNotStarted(error)
        case .invalid(let issue): VoiceToolReply.failed("The request was incomplete (\(issue.reason)).")
        case .paused: ConnectionPause.reply
        case .alreadySending: VoiceToolReply.failed("Another task is being handed over right now. Nothing was sent.")
        }
    }

    /// The Tasks screen: words the user typed and then said yes to on the card that showed the words,
    /// the note and the title (decision 2026-11-10-tasks-redesign). The same request and the same
    /// single approval as the voice tool. Nothing is sent while Connections are paused, and the
    /// 30-day log keeps that a task was handed over, not its words or title (as for the voice tool).
    func handOverTyped(_ draft: ErrandDraft, now: Date = Date(),
                       isPaused: Bool = UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey)) async -> HandOverOutcome {
        guard !isHandingOver else { return .alreadySending }
        guard !isPaused else { return .paused }
        isHandingOver = true
        defer { isHandingOver = false }
        let outcome = await submit(draft, now: now)
        let logged: ActivityOutcome? = switch outcome {
        case .started: .done
        case .maybeStarted: .notSure
        case .notStarted: .notDone
        case .invalid, .paused, .alreadySending: nil // Nothing left the iPhone.
        }
        if let logged {
            ActivityLogStore.shared.append(ActivityEntry(at: now, app: .web, title: "Hand over a task", detail: nil,
                                                         outcome: logged, attempted: true))
        }
        return outcome
    }

    /// Creates the task on the server and approves it with the digest of exactly these words. Never
    /// approves twice, never retries.
    private func submit(_ draft: ErrandDraft, now: Date) async -> HandOverOutcome {
        // ADR-716: whoever calls this, nothing with a link in it (or any other issue) is sent to the server.
        if let issue = draft.validationIssues().first { return .invalid(issue) }
        guard let backend else { return .notStarted(ErrandError.errandsDisabled) }
        let preview: ErrandPreview
        do {
            preview = try await backend.createErrand(draft)
        } catch {
            return .notStarted(error)
        }
        let approval: ErrandApproval
        do {
            approval = try await backend.approveErrand(preview.id, digest: preview.digest)
        } catch {
            return .notStarted(error)
        }
        let record = StoredErrand.handedOver(preview, draft: draft, approval: approval, at: now)
        // The server has it either way; a copy that couldn't be kept here is picked up again by
        // `refresh`, which adopts tasks the server knows and this iPhone doesn't.
        if let saved = try? await repository.save(record) {
            upsert(saved)
        } else {
            message = NSLocalizedString("Doddy is working on the task, but this iPhone couldn't keep a copy yet. It will show up in Tasks once Doddy checks again.", comment: "")
        }
        Task { await self.registerForNotifications() }
        return approval.isConfirmed ? .started : .maybeStarted
    }

    // MARK: Refresh

    /// Asks the server about every task that isn't finished here, saves what it says, saves a
    /// ready result here first and only then acknowledges it. Called when Doddy comes to the
    /// front, when Tasks opens and before the agent reads a result.
    func refresh(now: Date = Date()) async {
        guard let backend, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if !hasLoaded { await load() }
        guard loadProblem == nil else { return }
        let pending = errands.filter { !$0.state.isFinished || $0.needsAcknowledgement }
        // Nothing here to ask about and no account yet: no request at all, so coming to the front
        // never makes a server account for someone who has never handed over a task.
        let hasAccount = await backend.hasAccount()
        guard !pending.isEmpty || hasAccount else { return }
        if hasAccount { await adoptUnknown(from: backend, now: now) }
        for errand in pending {
            await update(errand, from: backend, now: now)
        }
    }

    private func update(_ errand: StoredErrand, from backend: any ErrandsBackend, now: Date) async {
        var current = errand
        if !errand.state.isFinished {
            let snapshot: ErrandSnapshot
            do {
                snapshot = try await backend.errand(errand.id)
            } catch ErrandError.notFound {
                // The server has no such task: an approval that never arrived (its draft expired) or
                // a task deleted elsewhere. It isn't running; it is never re-sent by itself.
                var gone = errand
                gone.state = .failed
                gone.failure = .unknown
                gone.updatedAt = now
                await keep(gone)
                return
            } catch {
                return // Offline or busy: asked again next time.
            }
            let next = errand.applying(snapshot, at: now)
            // Saved only when something the user can see changed (the state, the result, the reason).
            if next.state != errand.state || next.result != errand.result || next.failure != errand.failure {
                guard let saved = await keep(next) else { return }
                current = saved
                if saved.state.isFinished {
                    markUnseen(saved.id)
                    // Doddy's message in Messages with what he found (owner, 10 Nov 2026).
                    await ThreadInbox.deliver(errand: saved, now: now)
                }
            }
        }
        await acknowledgeIfNeeded(current, from: backend, now: now)
    }

    /// Only for a result already saved and read back here.
    private func acknowledgeIfNeeded(_ errand: StoredErrand, from backend: any ErrandsBackend, now: Date) async {
        guard errand.needsAcknowledgement, let digest = errand.resultDigest else { return }
        do {
            let deletions = try await backend.acknowledgeErrand(errand.id, resultDigest: digest)
            var acked = errand
            acked.acknowledgedAt = now
            acked.deletions = deletions
            acked.updatedAt = now
            await keep(acked)
        } catch {
            // Not acknowledged: the server keeps its copy (and deletes it after 30 days). Asked again later.
        }
    }

    /// Tasks the server has that this iPhone doesn't (a copy that couldn't be saved at hand-over).
    private func adoptUnknown(from backend: any ErrandsBackend, now: Date) async {
        guard let listed = try? await backend.errands() else { return }
        let known = Set(errands.map(\.id))
        for summary in listed where !known.contains(summary.id) {
            guard let snapshot = try? await backend.errand(summary.id),
                  let words = snapshot.words, let brief = snapshot.brief, let title = snapshot.title else { continue }
            // A shopping task keeps its kind and priorities (SHOPPING.md), so its card and report show them.
            let draft = ErrandDraft(words: words, brief: brief, title: title, language: snapshot.language ?? ErrandDraft.defaultLanguage,
                                    kind: snapshot.kind.flatMap(ErrandKind.init(rawValue:)), priorities: snapshot.priorities ?? [])
            let adopted = StoredErrand(id: snapshot.id, createdAt: snapshot.createdAt, state: .unknown, draft: draft).applying(snapshot, at: now)
            if let saved = await keep(adopted), saved.state.isFinished {
                markUnseen(saved.id)
                await ThreadInbox.deliver(errand: saved, now: now)
            }
        }
    }

    // MARK: The user's actions

    func cancel(_ id: UUID) async {
        guard let backend, let errand = errand(id) else { return }
        do {
            try await backend.cancelErrand(id)
        } catch {
            message = Self.describe(error)
            return
        }
        await update(errand, from: backend, now: Date())
    }

    /// Deletes the server's copy first (unless it was already deleted), then this iPhone's.
    /// If the server can't be reached, nothing is deleted, so nothing is said to be.
    func delete(_ id: UUID) async -> Bool {
        guard let errand = errand(id) else { return true }
        if errand.acknowledgedAt == nil {
            guard let backend else {
                message = NSLocalizedString("Doddy's server isn't set up in this build, so its copy of this task can't be deleted from here.", comment: "")
                return false
            }
            do {
                try await backend.deleteErrand(id)
            } catch {
                message = Self.describe(error)
                return false
            }
        }
        do {
            try await repository.delete(id)
        } catch {
            message = UserFacingError.message(for: error)
            return false
        }
        errands.removeAll { $0.id == id }
        markSeen(id)
        return true
    }

    func markSeen(_ id: UUID) {
        unseenFinished.removeAll { $0 == id }
        defaults.set(unseenFinished.map(\.uuidString), forKey: Self.unseenKey)
    }

    // MARK: For the voice agent

    /// `{{errands}}` at the start of a conversation.
    func cachedPromptText(now: Date = Date()) -> String {
        guard hasLoaded, loadProblem == nil else {
            return "(The task index is not ready. Use check_errands if the user asks about their tasks.)"
        }
        return ErrandsPrompt.render(errands, now: now)
    }

    /// On-demand readers may load; voice startup uses `cachedPromptText` instead.
    func promptText(now: Date = Date()) async -> String {
        if !hasLoaded { await load() }
        guard loadProblem == nil else { return "(the tasks kept on this iPhone couldn't be read)" }
        return ErrandsPrompt.render(errands, now: now)
    }

    /// The `check_errands` tool result: asks the server first, so a finished task reads as finished.
    func agentReply(about: String?) async -> String {
        await refresh()
        guard loadProblem == nil else {
            return VoiceToolReply.failed(NSLocalizedString("The tasks kept on this iPhone couldn't be read.", comment: ""))
        }
        return ErrandResultText.reply(errands, about: about)
    }

    // MARK: Plumbing

    @discardableResult
    private func keep(_ record: StoredErrand) async -> StoredErrand? {
        do {
            let saved = try await repository.save(record)
            upsert(saved)
            return saved
        } catch {
            message = UserFacingError.message(for: error)
            return nil
        }
    }

    private func upsert(_ record: StoredErrand) {
        errands.removeAll { $0.id == record.id }
        errands.append(record)
        errands.sort { $0.createdAt > $1.createdAt }
    }

    private func markUnseen(_ id: UUID) {
        guard !unseenFinished.contains(id) else { return }
        unseenFinished.append(id)
        defaults.set(unseenFinished.map(\.uuidString), forKey: Self.unseenKey)
    }

    /// The done notification needs this iPhone's push token on the server. Asked here, the first
    /// time, because this is when the user wants it; a refusal just leaves the result in Tasks.
    private func registerForNotifications() async {
        guard let client = backend as? DoddyServerClient else { return }
        let status = await PushRegistrar.shared.authorizationStatus()
        let token: Data?
        switch status {
        case .notDetermined: token = try? await PushRegistrar.shared.requestDeviceToken()
        case .authorized, .provisional, .ephemeral: token = try? await PushRegistrar.shared.currentDeviceToken()
        default: token = nil
        }
        guard let token else { return }
        try? await client.registerPushToken(token, environment: ServerConfig.pushEnvironment)
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case ErrandError.errandsDisabled:
            return NSLocalizedString("Doddy can't work on tasks in the background yet: it's switched off or not set up on Doddy's server.", comment: "")
        case ErrandError.server(let server):
            return UpdatesModel.text(for: server)
        case ErrandError.conflict, ErrandError.notApprovable:
            return NSLocalizedString("That couldn't be done: the task has already finished or changed. Pull down to check again.", comment: "")
        default:
            return UpdatesModel.text(for: error)
        }
    }
}
