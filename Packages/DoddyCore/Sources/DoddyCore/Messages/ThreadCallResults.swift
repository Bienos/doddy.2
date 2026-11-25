import Foundation

/// Calls Doddy made for the person (ADR-500, ADR-730), shown as a few cards under the thread in Messages:
/// "Doddy called Anna", and a tap opens that call's page in Settings, where the recap is. The call and its
/// answer stay where they are kept (`CallCaseRepository` on this iPhone); the saved thread stores nothing
/// new, so nothing about a call is copied to Doddy Web or sent to the model as context (`ThreadSync` and
/// `ThreadRules` never see it). The card holds only the callee's name from the person's own brief. Plain
/// Swift for the Linux tests.
public enum ThreadCallResults {
    /// What a call's card says: Doddy talked to someone, or nobody was reached (no answer, busy, voicemail, failed…).
    /// A call nobody answered is not "Doddy called Anna, see the recap" (owner, 25 Nov 2026: missed calls looked like
    /// finished ones and stuck to the bottom of Messages).
    public enum Reach: Equatable, Sendable {
        case talked
        case notReached
    }

    public static func reach(of record: StoredCallCase) -> Reach {
        switch record.result?.outcome {
        case .answered?, .takenOver?: .talked
        default: .notReached
        }
    }

    /// Only calls that were answered this recently are offered here; older ones stay in Settings › Calls for you.
    public static let window: TimeInterval = 7 * 24 * 3_600
    /// At most this many, the newest ones.
    public static let limit = 3

    /// Calls that have an answer card, newest few, oldest first. A call with no card yet is still going or never
    /// ended well; the Home icon and the call's own page tell about it.
    public static func shown(_ records: [StoredCallCase], now: Date) -> [StoredCallCase] {
        records
            .filter { $0.result != nil && now.timeIntervalSince($0.updatedAt) <= window }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .sorted { $0.updatedAt < $1.updatedAt }
    }
}
