@preconcurrency import ActivityKit
import Foundation

/// Starts, updates and ends one tool's Live Activity (focus, breathing, read-aloud, the timer
/// and wind-down of ADR-337, the "Note saved" card of ADR-338), like `VoiceLiveActivity` does
/// for a conversation. Optional: if Live Activities are off for Doddy,
/// or the request fails, the tool still works in the app.
///
/// Stale dates keep the island honest when the app is not running:
/// - focus, breathing, timer and wind-down: the end time, so once it passes iOS marks it stale
///   and the island says the time is up instead of a running countdown;
/// - read-aloud: 90 s ahead, pushed forward by a heartbeat while the app is reading, so a
///   killed app can't leave "Reading aloud" behind.
@MainActor
final class ToolLiveActivity {
    static let heartbeatStaleAfter: TimeInterval = 90
    static let heartbeatEvery: TimeInterval = 40

    let kind: DoddyToolAttributes.Kind
    private var activity: Activity<DoddyToolAttributes>?
    private var shown: DoddyToolAttributes.ContentState?
    private var updating: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?

    init(kind: DoddyToolAttributes.Kind) {
        self.kind = kind
    }

    /// Picks up an activity of this kind left from before a relaunch (the focus timer keeps
    /// running across one). Any extra copies are ended.
    func adoptExisting() {
        let existing = Activity<DoddyToolAttributes>.activities.filter {
            $0.attributes.kind == kind && ($0.activityState == .active || $0.activityState == .stale)
        }
        activity = existing.first
        shown = existing.first?.content.state
        for extra in existing.dropFirst() {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func show(_ state: DoddyToolAttributes.ContentState, startedAt: Date, duration: TimeInterval) {
        let state = Self.styled(state)
        let content = ActivityContent(state: state, staleDate: staleDate(for: state))
        if let activity {
            guard state != shown else { return }
            shown = state
            let previous = updating
            updating = Task {
                await previous?.value
                await activity.update(content)
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: DoddyToolAttributes(kind: kind, startedAt: startedAt, duration: duration),
                content: content,
                pushType: nil)
            shown = state
            if kind == .readAloud { startHeartbeat() }
        } catch {
            // Not fatal: the tool works without the island.
        }
    }

    /// Ends with a last state shown on the Lock Screen for `keepFor` (the island drops it at once),
    /// or at once when `final` is nil.
    func end(final: DoddyToolAttributes.ContentState?, keepFor: TimeInterval = 0) {
        heartbeat?.cancel()
        heartbeat = nil
        guard let activity else { return }
        self.activity = nil
        shown = nil
        let pending = updating
        updating = nil
        Task {
            await pending?.value
            if let final, keepFor > 0 {
                await activity.end(ActivityContent(state: Self.styled(final), staleDate: nil),
                                   dismissalPolicy: .after(Date().addingTimeInterval(keepFor)))
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// At launch: ends tool activities a previous run left behind, except the kinds that are
    /// restored (the focus timer).
    static func endLeftovers(keeping kept: Set<DoddyToolAttributes.Kind>) {
        for activity in Activity<DoddyToolAttributes>.activities where !kept.contains(activity.attributes.kind) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// The state with the island style picked in Settings (ADR-299), read when it is sent.
    private static func styled(_ state: DoddyToolAttributes.ContentState) -> DoddyToolAttributes.ContentState {
        var state = state
        state.islandStyle = IslandStyle.stored(UserDefaults.standard.string(forKey: PreferenceKey.islandStyle))
        return state
    }

    private func staleDate(for state: DoddyToolAttributes.ContentState) -> Date? {
        if state.isFinished || state.isPaused && kind != .readAloud { return nil }
        switch kind {
        // Countdowns (focus, breathing, timer, wind-down): stale at the end means "time's up".
        case .focus, .breathing, .timer, .windDown: return state.endsAt
        case .readAloud: return Date().addingTimeInterval(Self.heartbeatStaleAfter)
        // Finished from the start (ADR-338); ended by the app after a few seconds.
        case .noteSaved: return nil
        }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatEvery))
                guard !Task.isCancelled, let self, let activity = self.activity, let shown = self.shown else { return }
                await activity.update(ActivityContent(state: shown, staleDate: self.staleDate(for: shown)))
            }
        }
    }
}
