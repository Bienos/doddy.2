import Foundation
import Observation

/// The rules for keeping notes and conversations on Doddy's server (ADR-595), tested on Linux.
/// The person turns each kind on or off; the server is asked first and the switch follows its answer
/// (nothing is shown as kept, or as forgotten, until the server said so: DOD-08). Notes are sent as the
/// whole current list, so a note deleted here is gone there at the next send; conversations are sent
/// one at a time when they end. Private notes and private conversations are never sent (ADR-310).
@MainActor
@Observable
public final class WebMemoryModel {
    public enum Kind: Sendable { case notes, conversations }

    /// Why something didn't work, for the screen to say in the person's language.
    public enum Problem: Error, Equatable, Sendable {
        case notConfigured
        /// The server refused this iPhone's session even after a fresh sign-in.
        case signedOut
        /// The server says that kind is off (deleted from the web, say), so nothing was stored.
        case off
        /// The server has no key for this and keeps nothing.
        case notSetUp
        case tooLarge
        case tooMany(minutes: Int)
        case offline
        case unreadable
        case server
    }

    public enum NotesStatus: Equatable, Sendable {
        case idle
        case sending
        /// The server confirmed that it holds exactly this many notes.
        case sent(count: Int, at: Date)
        case failed(Problem)
    }

    public static let notesKey = "webMemory.notes"
    public static let conversationsKey = "webMemory.conversations"
    static let pendingKey = "webMemory.pendingConversations"
    static let pendingLimit = 50

    public private(set) var notesOn: Bool
    public private(set) var conversationsOn: Bool
    public private(set) var notesStatus: NotesStatus = .idle
    /// A switch or delete that didn't go through.
    public private(set) var problem: Problem?
    /// A switch or delete is waiting for the server.
    public private(set) var working = false
    /// A note list that failed or was cut off: sent again when Doddy comes to the front.
    public private(set) var needsNotesRetry = false
    private var sentSinceLaunch = false

    private let makeClient: @Sendable () async -> (any WebMemoryClient)?
    private let renewClient: @Sendable () async -> (any WebMemoryClient)?
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private var client: (any WebMemoryClient)?
    private var pending: Task<Void, Never>?

    /// `makeClient` signs the phone in first if needed; `renewClient` gets a fresh session after the
    /// server said this one isn't valid (ADR-563), tried once per action.
    public init(
        makeClient: @escaping @Sendable () async -> (any WebMemoryClient)?,
        renewClient: @escaping @Sendable () async -> (any WebMemoryClient)?,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.makeClient = makeClient
        self.renewClient = renewClient
        self.defaults = defaults
        self.now = now
        notesOn = defaults.bool(forKey: Self.notesKey)
        conversationsOn = defaults.bool(forKey: Self.conversationsKey)
    }

    // MARK: - switches

    /// Turns one kind on or off. The server is asked first; the local switch is whatever it answered.
    /// Turning notes on sends the current list at once. Off deletes that kind on the server. Returns
    /// whether the server confirmed.
    @discardableResult
    public func setKept(_ kind: Kind, on: Bool, records: [MemoryRecord], privateNotes: PrivateNotes) async -> Bool {
        working = true
        problem = nil
        defer { working = false }
        let wantNotes = kind == .notes ? on : notesOn
        let wantConversations = kind == .conversations ? on : conversationsOn
        switch await perform({ client throws(WebMemoryError) in try await client.setState(notes: wantNotes, conversations: wantConversations) }) {
        case .failure(let failure):
            problem = failure
            return false
        case .success(let state):
            apply(notes: state.notes, conversations: state.conversations)
            if state.notes, kind == .notes, on {
                await sendNotes(records, privateNotes: privateNotes)
            } else if !state.notes {
                pending?.cancel()
                needsNotesRetry = false
                notesStatus = .idle
            }
            return true
        }
    }

    /// Deletes everything kept on the server and switches both kinds off. Nil, with `problem` set, when the
    /// server didn't confirm: then nothing here changed either.
    public func deleteEverythingOnServer() async -> WebMemoryState? {
        working = true
        problem = nil
        defer { working = false }
        switch await perform({ client throws(WebMemoryError) in try await client.deleteAll() }) {
        case .failure(let failure):
            problem = failure
            return nil
        case .success(let state):
            apply(notes: false, conversations: false)
            pending?.cancel()
            needsNotesRetry = false
            notesStatus = .idle
            savePending([])
            return state
        }
    }

    // MARK: - notes

    /// Sends the whole current list now and waits for the server's answer. Does nothing while notes are off.
    public func sendNotes(_ records: [MemoryRecord], privateNotes: PrivateNotes) async {
        guard notesOn else { return }
        notesStatus = .sending
        needsNotesRetry = true
        let items = KeptNote.from(records, excluding: privateNotes)
        switch await perform({ client throws(WebMemoryError) in try await client.replaceNotes(items) }) {
        case .success(let count):
            notesStatus = .sent(count: count, at: now())
            needsNotesRetry = false
            sentSinceLaunch = true
        case .failure(.off):
            // The server isn't keeping notes (it was deleted from the web): stop sending.
            apply(notes: false, conversations: conversationsOn)
            needsNotesRetry = false
            notesStatus = .idle
        case .failure(let failure):
            notesStatus = .failed(failure)
        }
    }

    /// After a change: one send for a burst of edits, with the latest list. Call only after the notes were
    /// read successfully: a failed read can leave the list empty or stale, and sending it would wipe or
    /// roll back what the server holds (DOD-06).
    public func scheduleNotes(_ records: [MemoryRecord], privateNotes: PrivateNotes, delay: Duration = .seconds(2)) {
        guard notesOn else { return }
        pending?.cancel()
        needsNotesRetry = true
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.sendNotes(records, privateNotes: privateNotes)
        }
    }

    /// At launch and when Doddy comes to the front: sends the list again if the last send didn't go
    /// through, and once per launch so the server matches this iPhone. `notesLoaded` must be false
    /// when reading the notes failed.
    public func retryIfNeeded(_ records: [MemoryRecord], privateNotes: PrivateNotes, notesLoaded: Bool) {
        guard notesOn, notesLoaded, needsNotesRetry || !sentSinceLaunch else { return }
        scheduleNotes(records, privateNotes: privateNotes, delay: .zero)
    }

    /// Waits for a scheduled send to finish (tests, and callers that must say what happened).
    public func settle() async {
        await pending?.value
    }

    // MARK: - conversations

    /// Sends one finished conversation, once it ends, if the person keeps conversations on the server and
    /// it isn't private. A send that fails is remembered and tried again by `retryConversations`.
    public func sendConversation(_ log: ConversationLog, language: String?, isPrivate: Bool) async {
        guard KeptConversation.mayBeSent(keptOnServer: conversationsOn, isPrivate: isPrivate, lineCount: log.lines.count),
              let conversation = KeptConversation.from(log, language: language, now: now())
        else { return }
        switch await perform({ client throws(WebMemoryError) in try await client.putConversation(conversation) }) {
        case .success, .failure(.tooLarge):
            forgetPending(log.id)
        case .failure(.off):
            apply(notes: notesOn, conversations: false)
            savePending([])
        case .failure:
            rememberPending(log.id)
        }
    }

    /// At launch: conversations that couldn't be sent, if this iPhone still has them (the last ten).
    public func retryConversations(from logs: [ConversationLog], language: String?) async {
        guard conversationsOn else { return }
        let waiting = Set(loadPending())
        for log in logs where waiting.contains(log.id.uuidString) {
            await sendConversation(log, language: language, isPrivate: false)
        }
    }

    // MARK: - plumbing

    private func apply(notes: Bool, conversations: Bool) {
        notesOn = notes
        conversationsOn = conversations
        defaults.set(notes, forKey: Self.notesKey)
        defaults.set(conversations, forKey: Self.conversationsKey)
    }

    private func loadPending() -> [String] { defaults.stringArray(forKey: Self.pendingKey) ?? [] }
    private func savePending(_ ids: [String]) { defaults.set(Array(ids.suffix(Self.pendingLimit)), forKey: Self.pendingKey) }
    private func rememberPending(_ id: UUID) {
        var ids = loadPending().filter { $0 != id.uuidString }
        ids.append(id.uuidString)
        savePending(ids)
    }
    private func forgetPending(_ id: UUID) { savePending(loadPending().filter { $0 != id.uuidString }) }

    private func perform<T: Sendable>(_ action: (any WebMemoryClient) async throws(WebMemoryError) -> T) async -> Result<T, Problem> {
        if client == nil { client = await makeClient() }
        guard let current = client else { return .failure(.notConfigured) }
        do throws(WebMemoryError) {
            return .success(try await action(current))
        } catch {
            guard error == .unauthenticated else { return .failure(Self.problem(error)) }
        }
        guard let renewed = await renewClient() else { return .failure(.signedOut) }
        client = renewed
        do throws(WebMemoryError) {
            return .success(try await action(renewed))
        } catch {
            return .failure(Self.problem(error))
        }
    }

    static func problem(_ error: WebMemoryError) -> Problem {
        switch error {
        case .notConfigured: .notConfigured
        case .unauthenticated: .signedOut
        case .off: .off
        case .notSetUp: .notSetUp
        case .tooLarge: .tooLarge
        case .rateLimited(let seconds): .tooMany(minutes: max(1, Int((Double(seconds ?? 60) / 60).rounded(.up))))
        case .transport: .offline
        case .unreadable: .unreadable
        case .server: .server
        }
    }
}
