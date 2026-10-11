import ActivityKit
import DoddyCore
import Foundation

/// Shopping mode's Live Activity (ADR-252): one list on the Lock Screen and in the Dynamic Island.
/// The content is `ShoppingModeState`, built from the read-back list in the app.
struct ShoppingActivityAttributes: ActivityAttributes {
    typealias ContentState = ShoppingModeState
    let listID: UUID
}
