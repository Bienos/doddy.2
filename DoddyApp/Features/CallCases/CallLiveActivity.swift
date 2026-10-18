import ActivityKit
import DoddyCore
import Foundation

/// Starts, updates and ends the call's Live Activity (ADR-504): phase and call time only. It is
/// requested with a push token, which goes to the server (`PUT /v1/call-cases/:id/live-activity`)
/// so the island keeps up while the app sleeps; the token is cleared when the call ends.
/// Not run on a device yet.
@MainActor
final class CallLiveActivity: CallActivityPresenting {
    static let shared = CallLiveActivity()

    private var activity: Activity<DoddyCallAttributes>?
    private var tokenTask: Task<Void, Never>?
    private var updating: Task<Void, Never>?

    private init() {}

    /// At launch: the island's buttons reach the server even when iOS started the app just for them.
    func registerActions() {
        CallActivityActions.shared.takeOver = { caseId in
            _ = try? await ServerConfig.client()?.takeOverCallCase(caseId)
        }
        CallActivityActions.shared.end = { caseId in
            try? await ServerConfig.client()?.endCallCase(caseId)
        }
    }

    func show(caseId: UUID, phase: CallPhase, answeredAt: Date?) {
        let state = DoddyCallAttributes.ContentState(phase: phase.rawValue, answeredAtUnix: answeredAt.map { Int($0.timeIntervalSince1970) })
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10 * 60))
        if activity?.attributes.caseId != caseId {
            // One left from before a relaunch (the call runs on the server, so it may still be on).
            activity = Activity<DoddyCallAttributes>.activities.first { $0.attributes.caseId == caseId && $0.activityState == .active }
        }
        if let activity {
            guard activity.content.state != state else { return }
            let previous = updating
            updating = Task {
                await previous?.value
                await activity.update(content)
            }
            return
        }
        endOthers(than: caseId)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let started = try Activity.request(attributes: DoddyCallAttributes(caseId: caseId, startedAt: Date()), content: content, pushType: .token)
            activity = started
            tokenTask?.cancel()
            tokenTask = Task {
                for await token in started.pushTokenUpdates {
                    try? await ServerConfig.client()?.setCallLiveActivityToken(caseId, token: token, environment: ServerConfig.pushEnvironment)
                }
            }
        } catch {
            // Not fatal: the call screen in the app shows the same.
        }
    }

    /// "Call ended" stays on the Lock Screen for five minutes, then goes.
    func end(caseId: UUID, phase: CallPhase, endedAt: Date?) {
        tokenTask?.cancel()
        tokenTask = nil
        Task { try? await ServerConfig.client()?.clearCallLiveActivityToken(caseId) }
        let mine = activity?.attributes.caseId == caseId ? activity : Activity<DoddyCallAttributes>.activities.first { $0.attributes.caseId == caseId }
        guard let mine else { return }
        if activity?.id == mine.id { activity = nil }
        let final = DoddyCallAttributes.ContentState(phase: phase.rawValue, answeredAtUnix: mine.content.state.answeredAtUnix,
                                                     endedAtUnix: endedAt.map { Int($0.timeIntervalSince1970) })
        let pending = updating
        updating = nil
        Task {
            await pending?.value
            await mine.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(5 * 60)))
        }
    }

    private func endOthers(than caseId: UUID) {
        for other in Activity<DoddyCallAttributes>.activities where other.attributes.caseId != caseId {
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
