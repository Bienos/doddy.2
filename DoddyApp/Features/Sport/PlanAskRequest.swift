import DoddyCore
import Foundation

/// A plan screen to open with a goal already chosen (ADR-626): from the voice's card or a Messages card. A new value each
/// time, so a second request opens the screen again.
struct PlanAskRequest: Identifiable, Equatable {
    let id = UUID()
    let ask: PlanAsk
}
