import DoddyCore
import Foundation
import Observation

/// One card on the voice screen after a conversation: the stored row (still `proposed`) and
/// what happened to it. "Saved" appears only after the repository read the row back.
struct LearningCard: Identifiable, Equatable {
    enum State: Equatable {
        case offered, saving, saved
        case failed(String)
        case dismissed
    }

    let item: LearningCardItem
    var state: State = .offered
    var id: UUID { item.id }
}

/// Main-actor view state over `LearningService` (ADR-440). Everything shown is what the
/// repositories returned; the proposers and the policy live in DoddyCore and are tested there.
/// Learning is off until the user turns it on (Settings → What Doddy knows → What I've learned);
/// counting corrections is not a profile of the user (kinds and tool names only, 90 days, never
/// sent anywhere), so it runs either way and gives the baseline the metric needs.
@MainActor
@Observable
final class LearningStore {
    private let service: LearningService?
    private(set) var facts: [LearnedFact] = []
    private(set) var procedures: [Procedure] = []
    private(set) var metrics: LearningMetrics = .empty
    private(set) var cards: [LearningCard] = []
    private(set) var exportText: String?
    private(set) var problem: String?
    private(set) var hasLoaded = false
    @ObservationIgnored private var inFlight: [Task<Void, Never>] = []

    init(service: LearningService?) {
        self.service = service
    }

    var isAvailable: Bool { service != nil }

    // MARK: Settings the service is told about

    static var learningOn: Bool { UserDefaults.standard.bool(forKey: PreferenceKey.learningOn) }
    static var sharedWithVoice: Bool { UserDefaults.standard.bool(forKey: PreferenceKey.shareLearnedWithVoice) }
    static var connectionsPaused: Bool { UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) }
    static func connectionsOn() -> Set<VoiceConnection> {
        Set(VoiceConnection.allCases.filter { UserDefaults.standard.bool(forKey: $0.preferenceKey) })
    }

    // MARK: Views of the lists

    var confirmedFacts: [LearnedFact] { facts.filter { $0.status == .confirmed && !$0.needsReview(at: Date()) } }
    var factsToReview: [LearnedFact] { facts.filter { $0.needsReview(at: Date()) } }
    var retiredFacts: [LearnedFact] { facts.filter { $0.status == .retired } }
    var pendingFacts: [LearnedFact] { facts.filter { $0.status == .proposed } }
    var confirmedProcedures: [Procedure] { procedures.filter { $0.status == .confirmed } }
    var retiredProcedures: [Procedure] { procedures.filter { $0.status == .retired } }
    var pendingProcedures: [Procedure] { procedures.filter { $0.status == .proposed } }
    var hasAnything: Bool { !facts.isEmpty || !procedures.isEmpty }

    // MARK: Recording from "What Doddy did"

    /// The activity log tells this store about every entry it adds or replaces.
    func attach(to activity: ActivityLogStore) {
        activity.onChange = { [weak self] entry, previous, recent, sessionID in
            self?.recordActivity(entry, previous: previous, recent: recent, sessionID: sessionID)
        }
    }

    private func recordActivity(_ entry: ActivityEntry, previous: ActivityEntry?, recent: [ActivityEntry], sessionID: String?) {
        guard let service else { return }
        let task = Task { [weak self] in
            let failures = await service.recordActivity(entry, previous: previous, recent: recent, sessionID: sessionID)
            if !failures.isEmpty { self?.problem = "Couldn't keep a count of what you corrected." }
        }
        inFlight.append(task)
    }

    /// Waits for the counts written so far, so proposals read the whole conversation.
    private func drain() async {
        let tasks = inFlight
        inFlight = []
        for task in tasks { await task.value }
    }

    func recordGap(_ category: CapabilityGapCategory, requestID: String, sessionID: String?) async {
        guard let service else { return }
        do { try await service.recordGap(category, requestID: requestID, sessionID: sessionID) }
        catch { problem = "Couldn't write down what Doddy can't do yet." }
    }

    func recordChangedStep(tool: String, requestID: String, sessionID: String?) {
        guard let service else { return }
        let task = Task { [weak self] in
            do { try await service.recordChangedStep(tool: tool, requestID: requestID, sessionID: sessionID) }
            catch { self?.problem = "Couldn't keep a count of what you corrected." }
        }
        inFlight.append(task)
    }

    // MARK: Loading

    /// At launch and whenever the screen opens: drops stale proposals, retires procedures unused
    /// for 90 days, trims old counts, then reads everything back.
    func reload() async {
        guard let service else { hasLoaded = true; return }
        await drain()
        do {
            try await service.housekeeping()
            facts = try await service.facts.list(status: nil)
            procedures = try await service.procedures.list(status: nil)
            metrics = try await service.metrics()
            exportText = try await buildExport(service)
            problem = nil
        } catch {
            problem = UserFacingError.message(for: error)
        }
        hasLoaded = true
    }

    private func buildExport(_ service: LearningService) async throws -> String {
        func object(_ data: Data) throws -> Any { try JSONSerialization.jsonObject(with: data) }
        let wrapper: [String: Any] = [
            "schemaVersion": 1,
            "facts": try object(try await service.facts.export()),
            "procedures": try object(try await service.procedures.export()),
            "outcomeEvents": try object(try await service.outcomes.export()),
        ]
        let data = try JSONSerialization.data(withJSONObject: wrapper, options: [.sortedKeys, .prettyPrinted])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: After a conversation

    /// At most one card, and only when learning is on (the service checks).
    func proposeAfterConversation(leftover: [SaveSuggestion], isPrivate: Bool) async {
        guard let service else { return }
        await drain()
        let moment = LearningMoment(
            learningOn: Self.learningOn, connectionsPaused: Self.connectionsPaused, connectionsOn: Self.connectionsOn(),
            isPrivate: isPrivate, polish: NotificationLanguage.current == .polish)
        do {
            let items = try await service.proposeAfterConversation(leftoverSuggestions: leftover, moment: moment)
            cards = items.map { LearningCard(item: $0) }
            if !items.isEmpty { await reload() }
        } catch {
            problem = UserFacingError.message(for: error)
        }
    }

    func saveCard(_ id: UUID) async {
        guard let service, let index = cards.firstIndex(where: { $0.id == id }) else { return }
        switch cards[index].state {
        case .offered, .failed: break
        case .saving, .saved, .dismissed: return
        }
        cards[index].state = .saving
        do {
            _ = try await service.confirm(cards[index].item)
            if let again = cards.firstIndex(where: { $0.id == id }) { cards[again].state = .saved }
            await reload()
        } catch {
            if let again = cards.firstIndex(where: { $0.id == id }) { cards[again].state = .failed(UserFacingError.message(for: error)) }
        }
    }

    /// "Not now": the card goes; the proposal stays under Pending in Settings for seven days.
    func dismissCard(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), cards[index].state != .saving else { return }
        cards[index].state = .dismissed
    }

    /// "Never this": kept as a refused row, so the same evidence is never proposed again.
    func neverCard(_ id: UUID) async {
        guard let service, let index = cards.firstIndex(where: { $0.id == id }) else { return }
        switch cards[index].state {
        case .offered, .failed: break
        case .saving, .saved, .dismissed: return
        }
        do {
            try await service.reject(cards[index].item)
            if let again = cards.firstIndex(where: { $0.id == id }) { cards[again].state = .dismissed }
            await reload()
        } catch {
            if let again = cards.firstIndex(where: { $0.id == id }) { cards[again].state = .failed(UserFacingError.message(for: error)) }
        }
    }

    /// A new conversation starts with no cards from the last one. An unanswered proposal stays
    /// under Pending in Settings until it expires; a save in flight is left to finish.
    func clearAnsweredCards() {
        cards.removeAll { $0.state != .saving }
    }

    // MARK: Settings → What I've learned

    func confirmPending(fact: LearnedFact) async { await run { _ = try await $0.confirm(.fact(fact)) } }
    func confirmPending(procedure: Procedure) async { await run { _ = try await $0.confirm(.procedure(procedure)) } }
    func rejectPending(fact: LearnedFact) async { await run { try await $0.reject(.fact(fact)) } }
    func rejectPending(procedure: Procedure) async { await run { try await $0.reject(.procedure(procedure)) } }
    func thatsWrong(fact: LearnedFact) async { await run { try await $0.thatsWrong(fact: fact) } }
    func thatsWrong(procedure: Procedure) async { await run { try await $0.thatsWrong(procedure: procedure) } }
    func stillTrue(fact: LearnedFact) async { await run { _ = try await $0.facts.reconfirm(id: fact.id) } }
    func revise(fact: LearnedFact, to text: String) async { await run { _ = try await $0.facts.revise(id: fact.id, value: text) } }
    func rename(procedure: Procedure, to text: String) async {
        await run { _ = try await $0.procedures.update(id: procedure.id, triggerText: text, steps: procedure.steps) }
    }
    func delete(fact: LearnedFact) async { await run { try await $0.facts.delete(id: fact.id) } }
    func delete(procedure: Procedure) async { await run { try await $0.procedures.delete(id: procedure.id) } }
    func bringBack(procedure: Procedure) async { await run { _ = try await $0.procedures.revive(id: procedure.id) } }

    private func run(_ change: (LearningService) async throws -> Void) async {
        guard let service else { return }
        do {
            try await change(service)
            problem = nil
        } catch {
            problem = UserFacingError.message(for: error)
        }
        await reload()
    }

    /// "Delete everything learned": facts, procedures and counts, each read back as empty.
    func deleteAll() async throws {
        guard let service else { return }
        try await service.deleteAll()
        cards = []
        await reload()
    }

    // MARK: For the voice agent

    /// The text for `{{learned_context}}`. Without the user's switch, nothing is read.
    func voiceContext() async -> String {
        guard let service else { return LearningPrompt.notShared }
        do {
            return try await service.voiceContext(
                shared: Self.sharedWithVoice, connectionsOn: Self.connectionsOn(), connectionsPaused: Self.connectionsPaused)
        } catch {
            return LearningPrompt.notShared
        }
    }

    /// A plan card ran with these tools in this order: a saved procedure with that sequence
    /// counts as used.
    func planRan(tools: [String]) async {
        guard let service else { return }
        _ = try? await service.planRan(tools: tools)
    }
}
