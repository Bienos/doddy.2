import Foundation

/// Paces a Live Activity's content updates (ADR-604). The newest state always wins, and two
/// updates go at least `minimumGap` apart, so a status that flips quickly (Doddy speaking, then
/// listening for a moment between two sentences, then speaking again) can't build a queue of
/// updates that reach the Dynamic Island one after another, seconds late.
///
/// This only decides *what* to send and *when it may go*; the app owns the waiting (a task that
/// sleeps `delay(now:)`) and the ActivityKit calls. It holds no ActivityKit types, so the rules are
/// tested on Linux.
public struct LiveActivityPacer<State: Equatable> {
    /// The shortest time between two content updates.
    public let minimumGap: TimeInterval
    /// The state the app wants shown now.
    public private(set) var latest: State?
    /// The state iOS was last given.
    public private(set) var sent: State?
    private var sentAt: Date?

    public init(minimumGap: TimeInterval) {
        self.minimumGap = minimumGap
    }

    /// A new activity started, showing `state`.
    public mutating func started(with state: State, at now: Date) {
        latest = state
        sent = state
        sentAt = now
    }

    /// The app wants `state` shown. True when that is a change from what it wanted before, so
    /// the caller should make sure an update is waiting to go; false when nothing changed.
    @discardableResult
    public mutating func want(_ state: State) -> Bool {
        guard state != latest else { return false }
        latest = state
        return true
    }

    /// True when the state the app wants is not the one iOS has.
    public var hasPending: Bool {
        guard let latest else { return false }
        return latest != sent
    }

    /// Seconds to wait before the next update may go (0 when it may go now).
    public func delay(now: Date) -> TimeInterval {
        guard let sentAt else { return 0 }
        return max(0, sentAt.addingTimeInterval(minimumGap).timeIntervalSince(now))
    }

    /// The state to send now, marked as sent; nil when iOS already has the newest one (the
    /// status flipped and flipped back while the update waited).
    public mutating func next(now: Date) -> State? {
        guard let latest, latest != sent else { return nil }
        sent = latest
        sentAt = now
        return latest
    }

    /// For an update that goes whatever iOS has (a heartbeat with a fresh stale date, or the
    /// alert that opens the island up): the newest state, marked as sent; nil before the start.
    public mutating func resend(now: Date) -> State? {
        guard let latest else { return nil }
        sent = latest
        sentAt = now
        return latest
    }

    /// The activity ended: nothing is wanted or shown any more.
    public mutating func reset() {
        latest = nil
        sent = nil
        sentAt = nil
    }
}

extension LiveActivityPacer: Sendable where State: Sendable {}
