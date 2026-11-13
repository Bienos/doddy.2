import Foundation
import Observation

/// Logbook on the iPhone, the rules the screens and launch tasks use (tested on Linux).
///
/// **On by default** (owner, 9 Nov 2026, decision 2026-11-09-usage-counts-on-by-default): the iPhone
/// counts and sends unless the person turns it off in Settings › Doddy on the web. Off stops counting
/// at once; the days already on the server are deleted there, and "deleted" is said only after the
/// server confirmed it (DOD-08). If the server can't be reached then, it is asked again at the next sync.
@MainActor
@Observable
public final class LogbookModel {
    public enum Problem: Error, Equatable, Sendable {
        case notConfigured
        /// The server refused this iPhone's session even after a fresh sign-in.
        case signedOut
        case offline
        case tooMany
        /// The server isn't set up for this account (a guest iPhone).
        case notSetUp
        case unreadable
        /// The server's own words.
        case server(String)
        /// What would be counted on this iPhone was made with another Doddy account, so nothing is sent to the
        /// signed-in one (decision 2026-11-12-local-data-owner).
        case otherAccountsData
    }

    /// The person's switch. Absent means on.
    public static let onKey = "logbook.on"
    /// What the server last confirmed for this account: on, off, or not known yet (absent).
    static let serverOnKey = "logbook.serverOn"
    static let sendStateKey = "logbook.sendState"
    static let conversationsKey = "logbook.conversations"
    /// Conversations are kept on the iPhone as long as their day can still be sent.
    static let keptConversationDays = LogbookSchedule.lookBackDays + 1
    static let keptConversations = 500

    public private(set) var isOn: Bool
    public private(set) var working = false
    public private(set) var problem: Problem?
    /// When a day last reached the server.
    public private(set) var lastSent: Date?
    /// How many days the server deleted when Logbook was last turned off, once it confirmed.
    public private(set) var deletedDays: Int?
    /// Off was chosen but the server hasn't confirmed deleting its days yet.
    public var deletionPending: Bool { !isOn && serverOn != false }

    private var serverOn: Bool? {
        get { defaults.object(forKey: Self.serverOnKey) == nil ? nil : defaults.bool(forKey: Self.serverOnKey) }
        set {
            if let newValue { defaults.set(newValue, forKey: Self.serverOnKey) } else { defaults.removeObject(forKey: Self.serverOnKey) }
        }
    }

    private let makeClient: @Sendable () async -> (any LogbookClient)?
    private let renewClient: @Sendable () async -> (any LogbookClient)?
    /// Whether this iPhone's data may go to the signed-in account now (`LocalDataOwner`), asked before a day is sent.
    private let uploadGate: @MainActor () -> LocalDataUpload
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar
    private var client: (any LogbookClient)?
    private var syncing = false

    /// `uploadGate` has no default: every caller says whose data may be sent (`LocalDataOwner.upload(for:)`).
    public init(
        makeClient: @escaping @Sendable () async -> (any LogbookClient)?,
        renewClient: @escaping @Sendable () async -> (any LogbookClient)?,
        uploadGate: @escaping @MainActor () -> LocalDataUpload,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: @escaping @Sendable () -> Calendar = { Calendar.current }
    ) {
        self.makeClient = makeClient
        self.renewClient = renewClient
        self.uploadGate = uploadGate
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        isOn = defaults.object(forKey: Self.onKey) == nil ? true : defaults.bool(forKey: Self.onKey)
    }

    // MARK: - counting

    /// Keeps a finished conversation's times and ending, never its words, while Logbook is on.
    /// The caller leaves private conversations out (ADR-131, ADR-310).
    public func recordConversation(_ conversation: LogbookConversation) {
        guard isOn else { return }
        let cutoff = now().addingTimeInterval(-Double(Self.keptConversationDays) * 86_400)
        var kept = storedConversations().filter { $0.startedAt >= cutoff }
        kept.append(conversation)
        saveConversations(Array(kept.suffix(Self.keptConversations)))
    }

    /// What the iPhone holds for the days it may still send.
    public func storedConversations() -> [LogbookConversation] {
        guard let data = defaults.data(forKey: Self.conversationsKey) else { return [] }
        return (try? JSONDecoder().decode([LogbookConversation].self, from: data)) ?? []
    }

    // MARK: - the switch

    /// The person's choice. On: counting starts and the server is told. Off: counting stops at once
    /// and the server deletes what it holds; `deletedDays` is set once it confirmed. Returns whether
    /// the server confirmed.
    @discardableResult
    public func setOn(_ on: Bool, sources: LogbookSources) async -> Bool {
        isOn = on
        defaults.set(on, forKey: Self.onKey)
        deletedDays = nil
        problem = nil
        if !on {
            // Nothing more is counted or sent, whatever the server says.
            saveConversations([])
            defaults.removeObject(forKey: Self.sendStateKey)
        }
        working = true
        defer { working = false }
        let confirmed = await matchServer()
        if confirmed, on { await upload(sources) }
        return confirmed
    }

    /// At launch and when Doddy comes to the front or goes to the back: the server is brought in line
    /// with the switch, then whatever is due is sent. Call only after the notes were read
    /// successfully, so a failed read never replaces a day with smaller counts.
    public func sync(sources: LogbookSources) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        guard await matchServer() else { return }
        if isOn { await upload(sources) }
    }

    // MARK: - signing out

    /// The Doddy account signed out (decision 2026-11-12-local-data-owner). The person's switch stays as it is:
    /// Logbook is on unless they turned it off (decision 2026-11-09-usage-counts-on-by-default), and off also
    /// means "delete the counts on the server", which must never be applied to whichever account signs in next.
    /// What belongs to the account that left goes: the conversations counted for it, which days were sent, and,
    /// while the switch is on, what its server last confirmed (the next account's server is asked afresh). With
    /// nobody signed in, the upload gate sends nothing.
    public func accountSignedOut() {
        saveConversations([])
        defaults.removeObject(forKey: Self.sendStateKey)
        if isOn { serverOn = nil }
        client = nil
        problem = nil
        lastSent = nil
        deletedDays = nil
    }

    // MARK: - plumbing

    /// Asks the server to match the switch, if it doesn't already. True when it matches now.
    private func matchServer() async -> Bool {
        if serverOn == isOn { return true }
        let want = isOn
        switch await perform({ client throws(LogbookError) in try await client.setEnabled(want) }) {
        case .success(let deleted):
            serverOn = want
            problem = nil
            if !want { deletedDays = deleted }
            return true
        case .failure(let failure):
            problem = failure
            return false
        }
    }

    private func upload(_ sources: LogbookSources) async {
        switch uploadGate() {
        case .allowed: break
        case .waiting: return
        case .otherAccount:
            problem = .otherAccountsData
            return
        }
        var all = sources
        all.conversations = storedConversations()
        var state = loadSendState()
        let result = await sendDue(all, state: &state)
        saveSendState(state)
        if !result.sent.isEmpty { lastSent = now() }
        switch result.failure {
        case nil:
            problem = nil
        case .off?:
            // The server has Logbook off for this account (another account signed in here, say): turn
            // it on again, once, and send what's due.
            serverOn = false
            guard isOn, await matchServer() else { return }
            var retry = loadSendState()
            let second = await sendDue(all, state: &retry)
            saveSendState(retry)
            if !second.sent.isEmpty { lastSent = now() }
            problem = second.failure.map(Self.problem)
        case let failure?:
            problem = Self.problem(failure)
        }
    }

    private func sendDue(_ sources: LogbookSources, state: inout LogbookSendState) async -> LogbookUpload.Result {
        if client == nil { client = await makeClient() }
        guard let current = client else { return LogbookUpload.Result(sent: [], failure: .notConfigured) }
        let at = now(), cal = calendar()
        var result = await LogbookUpload.run(client: current, sources: sources, state: &state, now: at, calendar: cal)
        guard result.failure == .unauthenticated, let renewed = await renewClient() else { return result }
        client = renewed
        let more = await LogbookUpload.run(client: renewed, sources: sources, state: &state, now: at, calendar: cal)
        result.sent += more.sent
        result.failure = more.failure
        return result
    }

    private func perform<T: Sendable>(_ action: (any LogbookClient) async throws(LogbookError) -> T) async -> Result<T, Problem> {
        if client == nil { client = await makeClient() }
        guard let current = client else { return .failure(.notConfigured) }
        do throws(LogbookError) {
            return .success(try await action(current))
        } catch {
            guard error == .unauthenticated else { return .failure(Self.problem(error)) }
        }
        guard let renewed = await renewClient() else { return .failure(.signedOut) }
        client = renewed
        do throws(LogbookError) {
            return .success(try await action(renewed))
        } catch {
            return .failure(Self.problem(error))
        }
    }

    static func problem(_ error: LogbookError) -> Problem {
        switch error {
        case .notConfigured: .notConfigured
        case .unauthenticated: .signedOut
        case .off: .server("Logbook is off on Doddy's server.")
        case .transport: .offline
        case .unreadable: .unreadable
        case .rateLimited: .tooMany
        case .notSetUp: .notSetUp
        case .refused(let message): .server(message)
        }
    }

    private func loadSendState() -> LogbookSendState {
        guard let data = defaults.data(forKey: Self.sendStateKey) else { return LogbookSendState() }
        return (try? JSONDecoder().decode(LogbookSendState.self, from: data)) ?? LogbookSendState()
    }

    private func saveSendState(_ state: LogbookSendState) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.sendStateKey) }
    }

    private func saveConversations(_ conversations: [LogbookConversation]) {
        if conversations.isEmpty {
            defaults.removeObject(forKey: Self.conversationsKey)
        } else if let data = try? JSONEncoder().encode(conversations) {
            defaults.set(data, forKey: Self.conversationsKey)
        }
    }
}
