import ActivityKit
import Foundation

/// The Live Activity while Doddy is on a call for the user (ADR-504). Status and times only: it
/// never carries the callee's name, the number or any words of the call, because the Lock Screen
/// shows to anyone holding the iPhone (ADR-240). The transcript is only in the app. The app starts
/// it when a call begins; while the app sleeps the server moves it by push, with the same three
/// fields (server/messaging/src/taskCalls/webhooks.ts, `pushLiveActivity`).
struct DoddyCallAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The server's phase: ringing, connecting, talking, taken_over, ending, ended.
        var phase: String
        /// When the other side picked up, for the call timer.
        var answeredAtUnix: Int?
        var endedAtUnix: Int?
    }

    /// Which call the buttons act on. A random id, not personal data.
    var caseId: UUID
    var startedAt: Date
}

extension DoddyCallAttributes.ContentState {
    var answeredAt: Date? { answeredAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var endedAt: Date? { endedAtUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var canTakeOver: Bool { phase == "talking" }
    var canEnd: Bool { ["ringing", "connecting", "talking"].contains(phase) }
    var isOver: Bool { phase == "ended" }
}
