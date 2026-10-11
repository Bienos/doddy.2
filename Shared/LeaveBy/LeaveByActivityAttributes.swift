import ActivityKit
import Foundation

/// The leave-by countdown (ADR-347): the place the user picked on the card, when to leave and
/// when to arrive. Shown only if the user switched it on for this reminder. Compiled into the app,
/// which starts and ends it, and into the widget extension, which draws it.
struct LeaveByActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var leaveAt: Date
        var arriveBy: Date
    }

    /// The place as Apple Maps named it on the card.
    let placeName: String
}
