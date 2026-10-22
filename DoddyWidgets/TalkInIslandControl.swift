import AppIntents
import SwiftUI
import WidgetKit

/// The control that was "Talk in the Island" (ADR-577). Since ADR-593 it opens Doddy and starts
/// the conversation, like `TalkToDoddyControl` (owner, 22 Oct: the Action Button should open the
/// app, not the Dynamic Island on its own). It keeps its kind, because iOS remembers a control
/// by its kind: an Action Button, Control Center or Lock Screen already set to it now opens
/// Doddy after the update, with nothing to change in Settings. The island-only start is still
/// `TalkInIslandIntent`, listed in the Shortcuts app; no control runs it now.
@available(iOS 18.0, *)
struct TalkInIslandControl: ControlWidget {
    static let kind = "com.bienos.doddy2.talk-island"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TalkToDoddyIntent()) {
                Label("Talk to Doddy", systemImage: "waveform")
            }
        }
        .displayName("Talk to Doddy")
        .description("Opens Doddy and starts a voice conversation.")
    }
}
