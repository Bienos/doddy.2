import Foundation

/// Tasks Doddy finished in the background (ADR-570), shown as cards under the thread so a result can be read where
/// the person talks to him, not only from Home's card or Tasks. The task and its result stay where they are kept
/// (`ErrandRepository` on this iPhone); the thread stores nothing new. Plain Swift for the Linux tests.
public enum ThreadTaskResults {
    /// Only tasks that finished this recently are offered here; older ones stay in Tasks.
    public static let window: TimeInterval = 7 * 24 * 3_600
    /// At most this many, the newest ones.
    public static let limit = 3

    /// Done or failed tasks (a cancelled one was the person's own choice and needs no card), newest few, oldest first.
    public static func shown(_ errands: [StoredErrand], now: Date) -> [StoredErrand] {
        errands
            .filter { ($0.state == .done || $0.state == .failed) && now.timeIntervalSince($0.updatedAt) <= window }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .sorted { $0.updatedAt < $1.updatedAt }
    }
}
