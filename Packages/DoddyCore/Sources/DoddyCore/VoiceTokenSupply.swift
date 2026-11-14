import Foundation

/// Shares a fetch ahead with a press that arrives before it finishes. Only the credential is
/// prepared: this opens no provider conversation or microphone. The shelf still owns expiry,
/// account/server binding, single use and the unused-fetch cool-down.
@MainActor
public final class VoiceTokenSupply {
    public typealias Fetch = @MainActor @Sendable (URL) async -> Result<String, VoiceTokenError>

    public struct Token: Sendable {
        public let value: String
        public let source: VoiceTokenSource
    }

    private struct Pending {
        let id: Int
        let endpoint: URL
        let owner: String
        let task: Task<Result<String, VoiceTokenError>, Never>
    }

    private var shelf = VoiceTokenShelf()
    private var pending: Pending?
    private var generation = 0
    private var nextID = 0
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { .now }) { self.now = now }

    @discardableResult
    public func warm(endpoint: URL, owner: String, fetch: @escaping Fetch) -> Bool {
        guard !owner.isEmpty else { return false }
        discardOtherOwnerOrServer(endpoint: endpoint, owner: owner)
        guard pending == nil, shelf.shouldWarm(endpoint: endpoint, owner: owner, now: now()) else { return false }
        begin(endpoint: endpoint, owner: owner, fetch: fetch)
        return true
    }

    /// A press uses a held token, joins a matching fetch already in flight, or fetches once now.
    /// Concurrent callers never receive the same token. Failure is returned without a blind retry.
    public func token(endpoint: URL, owner: String, fetch: @escaping Fetch) async throws(VoiceTokenError) -> Token {
        guard !owner.isEmpty else { throw .sessionExpired }
        guard !Task.isCancelled else { throw .cancelled }
        discardOtherOwnerOrServer(endpoint: endpoint, owner: owner)
        if let token = shelf.take(endpoint: endpoint, owner: owner, now: now()) {
            return Token(value: token, source: .shelf)
        }
        let source: VoiceTokenSource = pending == nil ? .fetched : .warming
        if pending == nil { begin(endpoint: endpoint, owner: owner, fetch: fetch) }
        guard let request = pending else { throw .cancelled }
        let started = generation
        let result = await request.task.value
        guard started == generation, !Task.isCancelled else { throw .cancelled }
        if case .failure(let error) = result { throw error }
        if let token = shelf.take(endpoint: endpoint, owner: owner, now: now()) {
            return Token(value: token, source: source)
        }
        // Another caller already consumed it, or it expired while this caller was suspended.
        return try await token(endpoint: endpoint, owner: owner, fetch: fetch)
    }

    public func clear() {
        generation += 1
        shelf.clear()
        pending?.task.cancel()
        pending = nil
    }

    private func discardOtherOwnerOrServer(endpoint: URL, owner: String) {
        if let pending, pending.endpoint != endpoint || pending.owner != owner { clear() }
    }

    private func begin(endpoint: URL, owner: String, fetch: @escaping Fetch) {
        shelf.warmStarted(now: now())
        nextID += 1
        let id = nextID
        let started = generation
        let task = Task { @MainActor in
            let result = await fetch(endpoint)
            // A cancelled request can finish after a new one began. It must neither keep its
            // credential nor erase the new request, including on sign-out and Pause all.
            guard started == self.generation, self.pending?.id == id else { return result }
            self.pending = nil
            if case .success(let token) = result {
                self.shelf.store(token, endpoint: endpoint, owner: owner, fetchedAt: self.now())
                return token.isEmpty ? .failure(.badResponse) : result
            }
            return result
        }
        pending = Pending(id: id, endpoint: endpoint, owner: owner, task: task)
    }
}
