import Foundation

// Private notes and the Face ID lock (ADR-310). A note marked Private stays in Doddy on this
// iPhone but is left out of everything that takes notes elsewhere or shows them without asking:
// the voice agent's saved notes and its search, Siri, Ask Doddy, the widgets and the watch, and
// the opt-in server copy for phone calls. In the app its text shows only after Face ID (or the
// passcode). Separately, the whole app can ask for Face ID when it opens. Which notes are private
// is kept on this iPhone only, as their identifiers, and read back after every change.

public struct PrivateNotes: Equatable, Sendable {
    public static let storageKey = "privateNotes.ids"
    /// Settings › Lock Doddy with Face ID.
    public static let appLockKey = "privacy.appLock"
    /// After this long in the background, the app asks again.
    public static let relockAfter: TimeInterval = 60

    public private(set) var ids: Set<UUID>

    public init(ids: Set<UUID> = []) {
        self.ids = ids
    }

    /// From what is stored: identifiers separated by commas; anything else is ignored.
    public init(stored: String?) {
        ids = Set((stored ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) })
    }

    /// Sorted, so the same set is always stored the same way and reads back equal.
    public var stored: String { ids.map(\.uuidString).sorted().joined(separator: ",") }

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    public mutating func set(_ id: UUID, isPrivate: Bool) {
        if isPrivate { ids.insert(id) } else { ids.remove(id) }
    }

    /// The notes that may leave the app or show without Face ID.
    public func shareable(_ records: [MemoryRecord]) -> [MemoryRecord] {
        ids.isEmpty ? records : records.filter { !ids.contains($0.id) }
    }

    public func shareable(_ outcome: RecallOutcome) -> RecallOutcome {
        guard case .matches(let found) = outcome, !ids.isEmpty else { return outcome }
        let kept = found.filter { !ids.contains($0.record.id) }
        return kept.isEmpty ? .noMatch : .matches(kept)
    }

    /// What a private note shows in place of its words until Face ID.
    public static let hiddenText = "Private note"

    /// True when the app should ask again: the lock is on and it was away long enough (or never unlocked).
    public static func needsUnlock(lockOn: Bool, unlockedAt: Date?, backgroundSince: Date?, now: Date) -> Bool {
        guard lockOn else { return false }
        guard let unlockedAt else { return true }
        if let backgroundSince, now.timeIntervalSince(backgroundSince) >= relockAfter { return true }
        return unlockedAt > now
    }
}

/// Search for anything outside the app's own screens (the voice agent, Siri, Ask Doddy): private
/// notes are never found there.
public struct ShareableRecallService: RecallService {
    private let base: any RecallService
    private let privateIDs: @Sendable () -> Set<UUID>

    public init(base: any RecallService, privateIDs: @escaping @Sendable () -> Set<UUID>) {
        self.base = base
        self.privateIDs = privateIDs
    }

    public func recall(_ question: String, limit: Int) async throws -> RecallOutcome {
        PrivateNotes(ids: privateIDs()).shareable(try await base.recall(question, limit: limit))
    }
}
