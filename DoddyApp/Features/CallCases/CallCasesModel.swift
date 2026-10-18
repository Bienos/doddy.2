import DoddyCore
import Foundation
import Observation

// Calls Doddy places for the user (ADR-500..507, docs/decisions/calls.md). These two models hold
// the screens' state; the rules live in DoddyCore and on the server, which checks everything again.
// Nothing here says a call happened, ended or was saved unless the server or the store said so.

/// What the call screens need from Doddy's server: `DoddyServerClient` in the app.
protocol CallCasesBackend: Sendable {
    func callCaseAvailability() async throws -> CallCaseAvailability
    func createCallCase(_ draft: CallBriefDraft) async throws -> CallPreview
    func approveCallCase(_ caseId: UUID, digest: String, at: Date?) async throws -> CallApproval
    func callCaseLive(_ caseId: UUID, after cursor: String?) async throws -> CallLiveView
    func endCallCase(_ caseId: UUID) async throws
    func takeOverCallCase(_ caseId: UUID) async throws -> String
    func callCase(_ caseId: UUID) async throws -> CallCaseSnapshot
    func acknowledgeCallResult(_ caseId: UUID, attemptId: UUID, resultDigest: String) async throws -> [DeletionReceipt]
    func cancelCallCase(_ caseId: UUID) async throws
}

extension DoddyServerClient: CallCasesBackend {}

/// The call's Live Activity (ActivityKit, in the app). Phase and times only: no name, number or
/// words ever reach the Lock Screen (ADR-240).
@MainActor
protocol CallActivityPresenting: AnyObject {
    func show(caseId: UUID, phase: CallPhase, answeredAt: Date?)
    func end(caseId: UUID, phase: CallPhase, endedAt: Date?)
}

// MARK: - The list

@MainActor
@Observable
final class CallCasesModel {
    private let backend: (any CallCasesBackend)?
    let repository: any CallCaseRepository
    private let describe: @MainActor (any Error) -> String

    private(set) var availability: CallCaseAvailability?
    private(set) var cases: [StoredCallCase] = []
    /// Why the calls kept on this iPhone couldn't be read. A failed read never shows as "no calls".
    private(set) var loadProblem: String?
    private(set) var hasLoaded = false
    private(set) var isWorking = false
    var message: String?

    init(backend: (any CallCasesBackend)?, repository: any CallCaseRepository, describe: @escaping @MainActor (any Error) -> String) {
        self.backend = backend
        self.repository = repository
        self.describe = describe
    }

    var isServerConfigured: Bool { backend != nil }

    /// For the cost-per-outcome gate; unknown costs are counted apart, never as zero.
    var costSummary: CostPerOutcome { CostPerOutcome.summarize(cases) }

    /// Whether a new brief can be sent now, and why not.
    var blocker: String? {
        guard isServerConfigured else {
            return NSLocalizedString("Calls by Doddy need a Doddy messaging server, and none is connected in this build yet.", comment: "")
        }
        guard let availability else { return nil }
        if !availability.configured { return NSLocalizedString("Doddy's calling line isn't set up on the server yet.", comment: "") }
        if availability.killSwitch { return NSLocalizedString("Calls by Doddy are switched off on the server right now.", comment: "") }
        if !availability.agentProblems.isEmpty {
            return NSLocalizedString("Doddy's calling voice doesn't match its approved settings, so the server refuses to call until that's fixed.", comment: "")
        }
        if !availability.phoneVerified {
            return NSLocalizedString("Verify your phone number first, in Settings → Notifications and texts. Doddy rings it if you take over a call.", comment: "")
        }
        return nil
    }

    func load() async {
        do {
            cases = try await repository.list()
            loadProblem = nil
        } catch {
            loadProblem = describe(error)
        }
        hasLoaded = true
        guard let backend else { return }
        do {
            availability = try await backend.callCaseAvailability()
        } catch {
            message = CallCaseText.error(error, describe: describe)
        }
        await syncOpenCases()
    }

    /// Calls approved but without their answer here, or whose cost is still pending: the answer
    /// is saved on this iPhone (then the server deletes its copy) and the cost brought up to date,
    /// even if the call's own screen was never opened. The newest ten, to keep it light.
    private func syncOpenCases() async {
        let open = cases.filter { $0.state == "active" || $0.cost?.pending == true || $0.deletions.contains { !$0.isConfirmed } }
        for record in open.prefix(10) {
            await caseModel(for: record, activity: nil).syncOnce()
        }
    }

    /// Sends the brief (ticked facts only) and keeps the card the server made from it, with the
    /// whole brief, on this iPhone. `replacing` is the case being edited: a brief is never changed
    /// after its card exists, so editing makes a new case and the old one is cancelled.
    func prepare(_ draft: CallBriefDraft, replacing old: StoredCallCase? = nil) async -> StoredCallCase? {
        guard let backend else { return nil }
        if let problem = draft.problems.first {
            message = CallCaseText.problem(problem)
            return nil
        }
        isWorking = true
        message = nil
        defer { isWorking = false }
        let preview: CallPreview
        do {
            preview = try await backend.createCallCase(draft)
        } catch {
            message = CallCaseText.error(error, describe: describe)
            return nil
        }
        let saved: StoredCallCase
        do {
            saved = try await repository.save(StoredCallCase(id: preview.caseId, createdAt: Date(), state: "awaiting_approval",
                                                             brief: draft, preview: preview))
        } catch {
            // Without the copy on this iPhone the card can't be shown again, so it is withdrawn.
            try? await backend.cancelCallCase(preview.caseId)
            message = String(format: NSLocalizedString("The card couldn't be saved on this iPhone, so it was withdrawn. Nothing was dialled. %@", comment: ""),
                             describe(error))
            return nil
        }
        cases.removeAll { $0.id == saved.id }
        cases.insert(saved, at: 0)
        if let old { await withdraw(old) }
        return saved
    }

    /// Cancels a card on the server. One that never dialled is also removed here; one with a call
    /// behind it stays, since its answer, cost and receipts are the user's record.
    func withdraw(_ record: StoredCallCase) async {
        guard let backend else { return }
        do {
            try await backend.cancelCallCase(record.id)
        } catch {
            message = CallCaseText.error(error, describe: describe)
            return
        }
        do {
            if record.result == nil && record.state == "awaiting_approval" {
                try await repository.delete(record.id)
                cases.removeAll { $0.id == record.id }
            } else {
                var cancelled = record
                cancelled.state = "cancelled"
                cancelled.updatedAt = Date()
                let saved = try await repository.save(cancelled)
                replace(saved)
            }
        } catch {
            message = describe(error)
        }
    }

    /// Deletes a call from this iPhone only. The server's copy is deleted when the result is
    /// saved here (receipts on the card) or when it expires.
    func deleteLocal(_ id: UUID) async {
        do {
            try await repository.delete(id)
            cases.removeAll { $0.id == id }
        } catch {
            message = describe(error)
        }
    }

    /// Everything kept about calls, for the user's own export (JSON).
    func exportText() async -> String? {
        do {
            return String(decoding: try await repository.export(), as: UTF8.self)
        } catch {
            message = describe(error)
            return nil
        }
    }

    func replace(_ record: StoredCallCase) {
        if let index = cases.firstIndex(where: { $0.id == record.id }) { cases[index] = record } else { cases.insert(record, at: 0) }
    }

    func caseModel(for record: StoredCallCase, activity: (any CallActivityPresenting)?) -> CallCaseModel {
        CallCaseModel(record: record, backend: backend, repository: repository, activity: activity, describe: describe,
                      onChange: { [weak self] in self?.replace($0) })
    }
}

// MARK: - One case

@MainActor
@Observable
final class CallCaseModel {
    private let backend: (any CallCasesBackend)?
    private let repository: any CallCaseRepository
    private let describe: @MainActor (any Error) -> String
    private let onChange: @MainActor (StoredCallCase) -> Void
    @ObservationIgnored private weak var activity: (any CallActivityPresenting)?

    private(set) var record: StoredCallCase
    /// The newest attempt as the server last reported it; nil before any approval.
    private(set) var attemptId: UUID?
    private(set) var attemptNo: Int?
    private(set) var phase: CallPhase?
    private(set) var endReason: String?
    private(set) var answeredAt: Date?
    private(set) var hangupDueAt: Date?
    private(set) var endedAt: Date?
    private(set) var takeoverState: String?
    /// Words as Twilio transcribed them during the call (encrypted on the server until the result
    /// is saved here). Shown in the app only.
    private(set) var lines: [CallLiveLine] = []
    /// A scheduled attempt's time, from the approval.
    private(set) var scheduledFor: Date?
    /// Until when the server takes an approval of this card; it moves later after a failed try.
    private(set) var serverApprovableUntil: Date?
    /// The call is over and the answer card isn't on this iPhone yet.
    private(set) var waitingForResult = false
    private(set) var isWorking = false
    var message: String?

    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var watching: Task<Void, Never>?
    @ObservationIgnored private var collecting: Task<Void, Never>?

    init(record: StoredCallCase, backend: (any CallCasesBackend)?, repository: any CallCaseRepository,
         activity: (any CallActivityPresenting)?, describe: @escaping @MainActor (any Error) -> String,
         onChange: @escaping @MainActor (StoredCallCase) -> Void) {
        self.record = record
        self.backend = backend
        self.repository = repository
        self.activity = activity
        self.describe = describe
        self.onChange = onChange
    }

    var preview: CallPreview? { record.preview }
    var isLive: Bool { phase?.isLive ?? false }
    var canTakeOver: Bool { (phase?.canTakeOver ?? false) && !takeoverIsRunning }
    var canEnd: Bool { phase?.canEnd ?? false }
    var takeoverIsRunning: Bool { ["dialing", "ringing", "prompted", "joining", "joined"].contains(takeoverState ?? "") }

    /// The card can still be approved: never dialled, or a failed call that can be retried.
    var canApprove: Bool {
        guard preview != nil, !isLive, phase != .scheduled, record.state != "cancelled", record.state != "finished" || retryable else { return false }
        guard let until = approvableUntil else { return false }
        return until > Date() && (attemptId == nil || retryable)
    }

    var approvableUntil: Date? { serverApprovableUntil ?? preview.flatMap { ServerDates.parse($0.approvableUntil) } }

    /// The last call failed in a way a later try may fix (no answer, busy, voicemail...).
    var retryable: Bool {
        guard let result = record.result, record.resultAttemptId == attemptId || attemptId == nil else { return false }
        return result.outcome.isRetryable && (attemptNo ?? 1) < 3
    }

    /// "Zadzwoń ponownie o …": only times the whole call fits inside 8:00–20:00, within the day
    /// the server allows and before the card's payload is dropped (two days after it was made).
    func retryTimes(now: Date = Date()) -> [Date] {
        guard let preview else { return [] }
        let lastPayloadDay = record.createdAt.addingTimeInterval(2 * 86_400 - 15 * 60)
        return CallHours.retrySuggestions(after: now, maxDurationSecs: preview.maxDurationSecs, count: 6)
            .filter { $0 <= now.addingTimeInterval(86_400) && $0 <= lastPayloadDay }
            .prefix(4).map { $0 }
    }

    // MARK: Approve, end, take over

    /// Approves exactly the card on screen (its digest). `at` nil means now; a time schedules it.
    func approve(at: Date? = nil) async {
        guard let backend, let preview else { return }
        await run {
            let approval = try await backend.approveCallCase(self.record.id, digest: preview.digest, at: at)
            self.attemptId = approval.attemptId ?? self.attemptId
            self.lines = []
            self.cursor = nil
            self.takeoverState = nil
            switch approval.state {
            case "scheduled":
                self.scheduledFor = at
                self.phase = .scheduled
                self.message = at.map {
                    String(format: NSLocalizedString("Doddy will call at %@. You can cancel until then.", comment: ""), CallCaseText.time($0))
                }
            case "dialing":
                self.phase = .ringing
            default:
                // The answer never came back: the call may be ringing. Doddy never redials on its own.
                self.message = NSLocalizedString("Couldn't confirm the call started. Doddy won't redial on its own; the line is checked now.", comment: "")
            }
            try await self.saveState("active")
            self.watch()
        }
    }

    /// "Zakończ": Doddy says goodbye and hangs up.
    func end() async {
        guard let backend else { return }
        await run {
            try await backend.endCallCase(self.record.id)
            self.message = NSLocalizedString("Doddy is saying goodbye and hanging up.", comment: "")
        }
    }

    /// "Przejmij": the server rings the user's verified phone; pressing 1 joins the call.
    func takeOver() async {
        guard let backend else { return }
        await run {
            let state = try await backend.takeOverCallCase(self.record.id)
            self.takeoverState = state
            self.message = switch state {
            case "failed": NSLocalizedString("The phone service couldn't ring your phone. Doddy carries on with the call.", comment: "")
            case "unknown": NSLocalizedString("Couldn't confirm your phone is ringing. If it rings, answer and press 1. Doddy carries on until then.", comment: "")
            default: NSLocalizedString("Doddy is ringing your phone. Answer and press 1 to take over. Doddy carries on until you do.", comment: "")
            }
        }
    }

    /// Withdraws a scheduled call or an unused card.
    func cancel() async {
        guard let backend else { return }
        await run {
            try await backend.cancelCallCase(self.record.id)
            self.phase = self.phase == .scheduled ? nil : self.phase
            self.scheduledFor = nil
            try await self.saveState("cancelled")
            self.message = NSLocalizedString("Cancelled. Doddy won't call.", comment: "")
        }
    }

    // MARK: Watching the call

    /// On opening the screen: what the server knows now, then watching if a call is on.
    func refresh() async {
        guard let backend else { return }
        do {
            let snapshot = try await backend.callCase(record.id)
            adopt(snapshot)
            try await absorb(snapshot)
        } catch ServerError.unexpected(status: 404), CallCaseError.server(.unexpected(status: 404)) {
            // The server no longer has this case (expired or deleted); what is here stays.
            return
        } catch {
            message = CallCaseText.error(error, describe: describe)
            return
        }
        if phase == .scheduled || isLive || phase == .unknown { watch() } else if phase == .ended, needsResult { collect() }
    }

    /// One look at the server, no watching: saves a ready answer (then acknowledges it), the
    /// cost and the receipts. Quiet on failure; the call's own screen says what went wrong.
    func syncOnce() async {
        guard let backend else { return }
        guard let snapshot = try? await backend.callCase(record.id) else { return }
        adopt(snapshot)
        try? await absorb(snapshot)
    }

    func stopWatching() {
        watching?.cancel()
        watching = nil
        collecting?.cancel()
        collecting = nil
    }

    /// Polls the live view: every second while the call is on, every 15 s while it waits for its
    /// time. Stops when the server says it ended, then fetches the answer card.
    func watch() {
        guard watching == nil, let backend else { return }
        let caseId = record.id
        watching = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let view = try await backend.callCaseLive(caseId, after: self.cursor)
                    failures = 0
                    self.apply(view)
                    if view.attempt == nil || self.phase == .ended { break }
                } catch {
                    failures += 1
                    if failures >= 10 {
                        self.message = NSLocalizedString("Lost touch with Doddy's server. The call carries on there; open this call again to check.", comment: "")
                        break
                    }
                }
                let wait: UInt64 = self.phase == .scheduled ? 15 : 1
                try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.watching = nil
            if self.phase == .ended { self.collect() }
        }
    }

    private func apply(_ view: CallLiveView) {
        guard let attempt = view.attempt else { return }
        if attempt.id != attemptId {
            attemptId = attempt.id
            lines = []
        }
        let previous = phase
        attemptNo = attempt.attemptNo
        phase = attempt.phase
        endReason = attempt.endReason
        answeredAt = attempt.answeredAt.flatMap(ServerDates.parse)
        hangupDueAt = attempt.hangupDueAt.flatMap(ServerDates.parse)
        endedAt = attempt.endedAt.flatMap(ServerDates.parse)
        takeoverState = attempt.takeover?.state ?? takeoverState
        let known = Set(lines.map(\.key))
        lines.append(contentsOf: view.lines.filter { !known.contains($0.key) })
        if let next = view.cursor { cursor = next }
        guard previous != attempt.phase else { return }
        if attempt.phase.isLive {
            activity?.show(caseId: record.id, phase: attempt.phase, answeredAt: answeredAt)
        } else if attempt.phase == .ended {
            activity?.end(caseId: record.id, phase: .ended, endedAt: endedAt)
        }
    }

    /// The attempt as the case snapshot reports it (no lines or times).
    private func adopt(_ snapshot: CallCaseSnapshot) {
        serverApprovableUntil = ServerDates.parse(snapshot.approvableUntil)
        guard let last = snapshot.attempts.last else { return }
        if last.id != attemptId { lines = [] }
        attemptId = last.id
        attemptNo = last.attemptNo
        phase = last.phase
        endReason = last.endReason
    }

    /// The newest attempt has no result on this iPhone yet.
    private var needsResult: Bool { attemptId != nil && record.resultAttemptId != attemptId }

    /// Asks for the answer card every 3 s for up to three minutes after the call ended (the
    /// server builds it once the voice provider reports the transcript, or from the live lines).
    func collect() {
        guard collecting == nil, let backend else { return }
        waitingForResult = true
        let caseId = record.id
        collecting = Task { [weak self] in
            let deadline = Date().addingTimeInterval(180)
            while !Task.isCancelled, Date() < deadline {
                guard let self else { return }
                do {
                    let snapshot = try await backend.callCase(caseId)
                    self.adopt(snapshot)
                    try await self.absorb(snapshot)
                    let latest = snapshot.results.last { $0.attemptId == self.attemptId }
                    if !self.needsResult || latest.map({ ["acked", "expired"].contains($0.state) }) == true { break }
                } catch {
                    self.message = CallCaseText.error(error, describe: self.describe)
                    break
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            guard let self else { return }
            self.collecting = nil
            self.waitingForResult = self.needsResult
        }
    }

    /// Saves what the server reports. A ready answer card is saved on this iPhone first (the save
    /// reads the row back), and only then acknowledged, so the server deletes its copy; the
    /// receipts it returns are kept with the case. A failed acknowledgement is asked again next time.
    private func absorb(_ snapshot: CallCaseSnapshot) async throws {
        var next = record
        next.state = snapshot.state
        next.cost = snapshot.cost
        next.deletions = Self.merge(next.deletions, snapshot.deletions)
        let ready = snapshot.readyResult
        if let ready, let card = ready.result {
            next.result = card
            next.resultAttemptId = ready.attemptId
        }
        if next != record {
            next.updatedAt = Date()
            record = try await repository.save(next)
            onChange(record)
        }
        guard let backend, let ready, let digest = ready.resultDigest, record.resultAttemptId == ready.attemptId else { return }
        do {
            let receipts = try await backend.acknowledgeCallResult(record.id, attemptId: ready.attemptId, resultDigest: digest)
            var acked = record
            acked.deletions = Self.merge(acked.deletions, receipts)
            acked.updatedAt = Date()
            record = try await repository.save(acked)
            onChange(record)
        } catch {
            message = String(format: NSLocalizedString("The answer is saved on this iPhone, but the server's copy couldn't be deleted yet: %@ Doddy asks again the next time you open this call.", comment: ""),
                             CallCaseText.error(error, describe: describe))
        }
    }

    private func saveState(_ state: String) async throws {
        var next = record
        next.state = state
        next.updatedAt = Date()
        record = try await repository.save(next)
        onChange(record)
    }

    static func merge(_ old: [DeletionReceipt], _ new: [DeletionReceipt]) -> [DeletionReceipt] {
        var byId: [String: DeletionReceipt] = [:]
        var order: [String] = []
        for receipt in old + new {
            if byId[receipt.id] == nil { order.append(receipt.id) }
            byId[receipt.id] = receipt
        }
        return order.compactMap { byId[$0] }
    }

    private func run(_ work: @MainActor () async throws -> Void) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            message = CallCaseText.error(error, describe: describe)
        }
    }
}

// MARK: - Words

/// What the call screens say. English keys; the Polish lines are in l10n/pl.json.
enum CallCaseText {
    static func time(_ date: Date) -> String {
        date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }

    static func problem(_ problem: CallBriefProblem) -> String {
        switch problem {
        case .missingCalleeName: NSLocalizedString("Say who Doddy is calling.", comment: "")
        case .missingPrincipal: NSLocalizedString("Add your first name, as Doddy says it: \"on behalf of …\".", comment: "")
        case .missingGoal: NSLocalizedString("Write the goal of the call in one sentence.", comment: "")
        case .missingQuestion: NSLocalizedString("Write the one question Doddy asks.", comment: "")
        case .numberNotAllowed(let reason): destination(reason.serverCode)
        case .tooManyFacts: NSLocalizedString("Tick at most five facts Doddy may say.", comment: "")
        case .sensitiveFactKind: NSLocalizedString("A ticked fact looks like a PESEL or an address. Mark it as one, or untick it.", comment: "")
        case .peselFactInvalid: NSLocalizedString("The fact marked PESEL doesn't hold a valid PESEL.", comment: "")
        case .braces: NSLocalizedString("Curly brackets { } can't be used in a brief.", comment: "")
        case .tooLong: NSLocalizedString("Something is too long: goal up to 160 characters, question up to 200, each fact up to 160.", comment: "")
        }
    }

    static func destination(_ reason: String) -> String {
        switch reason {
        case "short_number": NSLocalizedString("Doddy never calls emergency or short numbers.", comment: "")
        case "premium", "shared_cost": NSLocalizedString("Doddy never calls premium or shared-cost numbers.", comment: "")
        case "foreign": NSLocalizedString("Doddy only calls Polish numbers for now.", comment: "")
        case "own_number": NSLocalizedString("That's your own number. Doddy calls other people for you.", comment: "")
        case "doddy_number": NSLocalizedString("That's Doddy's own number.", comment: "")
        case "not_a_number": NSLocalizedString("That doesn't look like a phone number.", comment: "")
        default: NSLocalizedString("Doddy can't call that number. Only Polish mobile, landline and 800 numbers.", comment: "")
        }
    }

    static func gate(_ gate: String) -> String {
        switch gate {
        case "outside_hours": NSLocalizedString("Doddy only calls between 8:00 and 20:00 Polish time, and the whole call must fit. Nothing was dialled.", comment: "")
        case "kill_switch": NSLocalizedString("Calls by Doddy are switched off on the server right now. Nothing was dialled.", comment: "")
        case "agent_drift": NSLocalizedString("Doddy's calling voice doesn't match its approved settings, so nothing was dialled.", comment: "")
        case "one_live_call": NSLocalizedString("Another call by Doddy is still on. One at a time. Nothing was dialled.", comment: "")
        case "limit_user_hour", "limit_user_day", "limit_global_day":
            NSLocalizedString("That's the limit for calls by Doddy for now. Nothing was dialled. Try again later.", comment: "")
        case "limit_destination_user_day", "limit_destination_day", "limit_destination_gap":
            NSLocalizedString("Doddy has called this number enough for now. Nothing was dialled. Try again later.", comment: "")
        case "no_verified_phone": NSLocalizedString("Verify your phone number first, in Settings → Notifications and texts.", comment: "")
        default: NSLocalizedString("The server stopped this call before dialling. Nothing was dialled.", comment: "")
        }
    }

    static func brief(field: String, reason: String) -> String {
        switch reason {
        case "pesel_not_ticked": NSLocalizedString("A PESEL can only be sent as a fact marked PESEL.", comment: "")
        case "pesel_invalid": NSLocalizedString("The fact marked PESEL doesn't hold a valid PESEL.", comment: "")
        case "address_not_ticked": NSLocalizedString("An address can only be sent as a fact marked Address.", comment: "")
        case "bank_account", "card_number": NSLocalizedString("Doddy never says card or bank account numbers on a call.", comment: "")
        case "question_commits": NSLocalizedString("The question asks Doddy to agree to, book or pay for something. Doddy only asks; rephrase it as a question.", comment: "")
        case "duplicate_fact": NSLocalizedString("The same fact is ticked twice.", comment: "")
        case "too_long": NSLocalizedString("Something in the brief is too long for the server.", comment: "")
        default: String(format: NSLocalizedString("The server won't send this brief (%@).", comment: ""), field)
        }
    }

    static func notApprovable(_ code: String) -> String {
        switch code {
        case "digest_mismatch": NSLocalizedString("This card doesn't match what the server holds. Make a new one.", comment: "")
        case "outside_hours": NSLocalizedString("Doddy only calls between 8:00 and 20:00 Polish time, and the whole call must fit. Pick a later time.", comment: "")
        case "attempt_open": NSLocalizedString("A call for this card is already on or waiting for its time.", comment: "")
        case "already_answered": NSLocalizedString("This call was already answered. For another call, make a new card.", comment: "")
        case "no_more_attempts": NSLocalizedString("That was the last try for this card. Make a new one to call again.", comment: "")
        case "not_approvable": NSLocalizedString("This card has expired. Make a new one from the same brief.", comment: "")
        case "too_many_open_cases": NSLocalizedString("Five cards are waiting already. Use or cancel one first.", comment: "")
        case "not_live": NSLocalizedString("The call isn't on any more.", comment: "")
        case "taken_over": NSLocalizedString("You're on the call now; hang up on your phone to end it.", comment: "")
        case "not_takeoverable": NSLocalizedString("The call can't be taken over now: it hasn't started talking, or less than 30 seconds are left.", comment: "")
        case "no_more_tries": NSLocalizedString("Your phone was rung twice already. Doddy carries on with the call.", comment: "")
        case "phone_not_supported": NSLocalizedString("Taking over needs a verified Polish phone number.", comment: "")
        case "call_live": NSLocalizedString("The call is on. End it first.", comment: "")
        case "result_mismatch": NSLocalizedString("The answer on the server changed. Open the call again.", comment: "")
        default: NSLocalizedString("The server didn't accept that right now.", comment: "")
        }
    }

    @MainActor
    static func error(_ error: any Error, describe: @MainActor (any Error) -> String) -> String {
        switch error {
        case CallCaseError.briefRefused(let field, let reason): brief(field: field, reason: reason)
        case CallCaseError.destinationRefused(let reason): destination(reason)
        case CallCaseError.gateRefused(let code): gate(code)
        case CallCaseError.notApprovable(let code): notApprovable(code)
        case CallCaseError.callsDisabled: gate("kill_switch")
        case CallCaseError.server(.notEnabled("no_verified_phone")): gate("no_verified_phone")
        case CallCaseError.server(.providerUnavailable):
            NSLocalizedString("The phone service turned the call down, so nothing was dialled. Try again in a few minutes.", comment: "")
        case CallCaseError.server(let inner): describe(inner)
        default: describe(error)
        }
    }

    static func outcome(_ outcome: CallOutcome) -> String {
        switch outcome {
        case .answered: NSLocalizedString("Answered", comment: "")
        case .noAnswer: NSLocalizedString("No answer", comment: "")
        case .busy: NSLocalizedString("Busy", comment: "")
        case .failed: NSLocalizedString("The call failed", comment: "")
        case .notPlaced: NSLocalizedString("Not dialled", comment: "")
        case .voicemail: NSLocalizedString("Voicemail", comment: "")
        case .ivr: NSLocalizedString("An automatic menu answered", comment: "")
        case .wrongNumber: NSLocalizedString("Wrong number", comment: "")
        case .noConversation: NSLocalizedString("Answered, but no conversation", comment: "")
        case .takenOver: NSLocalizedString("You took over", comment: "")
        case .voiceUnavailable: NSLocalizedString("Doddy's voice wasn't available", comment: "")
        case .stopped: NSLocalizedString("Stopped", comment: "")
        case .unknown: NSLocalizedString("Not known", comment: "")
        }
    }

    static func phase(_ phase: CallPhase) -> String {
        switch phase {
        case .scheduled: NSLocalizedString("Waiting for its time", comment: "")
        case .ringing: NSLocalizedString("Ringing", comment: "")
        case .connecting: NSLocalizedString("Connecting", comment: "")
        case .talking: NSLocalizedString("Doddy is talking", comment: "")
        case .takenOver: NSLocalizedString("You're on the call", comment: "")
        case .ending: NSLocalizedString("Saying goodbye", comment: "")
        case .ended: NSLocalizedString("Call ended", comment: "")
        case .unknown: NSLocalizedString("Not confirmed", comment: "")
        }
    }

    static func confidence(_ confidence: CallConfidence) -> String {
        switch confidence {
        case .high: NSLocalizedString("High confidence", comment: "")
        case .medium: NSLocalizedString("Medium confidence", comment: "")
        case .low: NSLocalizedString("Low confidence: check the transcript", comment: "")
        case .none: NSLocalizedString("No answer found in the transcript", comment: "")
        }
    }

    static func confidenceReason(_ reason: String) -> String {
        switch reason {
        case "live_transcript_only": NSLocalizedString("Made from the live transcript only; the voice provider's transcript never came.", comment: "")
        case "hedged_answer": NSLocalizedString("The answer sounded unsure.", comment: "")
        case "asked_outside_brief": NSLocalizedString("They asked for something outside the card.", comment: "")
        case "taken_over": NSLocalizedString("You took over, so the rest of the call isn't in the transcript.", comment: "")
        case "time_limit": NSLocalizedString("The call reached its time limit.", comment: "")
        case "doddy_line_warnings": NSLocalizedString("Something Doddy said needs a look (below).", comment: "")
        case "model_quote_rejected": NSLocalizedString("The suggested quote wasn't word for word in the transcript, so it was dropped.", comment: "")
        case "several_replies": NSLocalizedString("The answer is spread over several replies.", comment: "")
        case "no_answer_found": NSLocalizedString("No answer to the question was found.", comment: "")
        default: reason
        }
    }

    static func warning(_ kind: String) -> String {
        switch kind {
        case "possible_commitment": NSLocalizedString("Doddy may have agreed to something. Check this line.", comment: "")
        case "pesel_said": NSLocalizedString("A PESEL-like number was said by Doddy. Check this line.", comment: "")
        case "unlisted_number": NSLocalizedString("Doddy said a number that isn't on the card. Check this line.", comment: "")
        default: NSLocalizedString("Check this line.", comment: "")
        }
    }

    static func state(_ record: StoredCallCase) -> String {
        if let result = record.result { return outcome(result.outcome) }
        switch record.state {
        case "awaiting_approval": return NSLocalizedString("Waiting for your approval", comment: "")
        case "active": return NSLocalizedString("Approved", comment: "")
        case "cancelled": return NSLocalizedString("Cancelled", comment: "")
        case "expired": return NSLocalizedString("Expired", comment: "")
        default: return NSLocalizedString("No answer card yet", comment: "")
        }
    }

    static func component(_ component: String) -> String {
        switch component {
        case "twilio_call": NSLocalizedString("Phone line (Twilio)", comment: "")
        case "twilio_transcription": NSLocalizedString("Live transcript (Twilio)", comment: "")
        case "elevenlabs_voice": NSLocalizedString("Doddy's voice (ElevenLabs)", comment: "")
        case "model": NSLocalizedString("Answer card (Claude)", comment: "")
        case "twilio_takeover": NSLocalizedString("Ringing your phone (Twilio)", comment: "")
        case "twilio_conference": NSLocalizedString("Joining you in (Twilio)", comment: "")
        default: component
        }
    }

    static func deletion(_ receipt: DeletionReceipt) -> String {
        let what: String = switch receipt.item {
        case "call_result": NSLocalizedString("Answer card and transcript", comment: "")
        case "live_lines": NSLocalizedString("Live transcript lines", comment: "")
        case "call_input": NSLocalizedString("Transcript from the voice provider", comment: "")
        case "call_payload": NSLocalizedString("The approved brief", comment: "")
        case "elevenlabs_conversation": NSLocalizedString("Conversation at ElevenLabs", comment: "")
        default: receipt.item
        }
        let result: String = switch receipt.result {
        case "deleted": NSLocalizedString("deleted", comment: "")
        case "not_found": NSLocalizedString("already gone", comment: "")
        case "pending": NSLocalizedString("deletion pending", comment: "")
        default: NSLocalizedString("deletion not confirmed", comment: "")
        }
        return "\(what): \(result)"
    }
}

private extension PolishNumber.Refusal {
    /// The server's word for the same refusal.
    var serverCode: String {
        switch self {
        case .notANumber: "not_a_number"
        case .shortNumber: "short_number"
        case .foreign: "foreign"
        case .premium: "premium"
        case .sharedCost: "shared_cost"
        case .special: "special"
        case .unknownRange: "unknown_range"
        }
    }
}
