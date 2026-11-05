import AppIntents
import SwiftUI
import WidgetKit

/// The control that was "Talk in the Island" (ADR-577). It opened Doddy between ADR-593 and
/// ADR-727; it starts the conversation in the Dynamic Island again, like `TalkToDoddyControl`
/// (owner, 5 Nov 2026: press the Action Button, Doddy appears in the island and asks what's up).
/// It keeps its kind, because iOS remembers a control by its kind: an Action Button, Control
/// Center or Lock Screen already set to it needs nothing changed in Settings.
@available(iOS 18.0, *)
struct TalkInIslandControl: ControlWidget {
    static let kind = "com.bienos.doddy2.talk-island"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TalkInIslandIntent()) {
                Label("Talk to Doddy", systemImage: "waveform")
            }
        }
        .displayName("Talk to Doddy")
        .description(LocalizedStringResource("Starts a voice conversation in the Dynamic Island without opening Doddy."))
    }
}
