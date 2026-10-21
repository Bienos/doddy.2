import AppIntents
import SwiftUI
import WidgetKit

/// "Talk in the Island" for the Action Button, Control Center and the Lock Screen (iOS 18+,
/// ADR-569): starts a conversation without opening Doddy (`TalkInIslandIntent`); he greets you and
/// stays in the Dynamic Island. The user adds it themselves (Settings › Action Button › Controls);
/// Doddy can't place it or tell whether it was added. "Talk to Doddy" stays the control that
/// opens the app.
@available(iOS 18.0, *)
struct TalkInIslandControl: ControlWidget {
    static let kind = "com.bienos.doddy2.talk-island"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TalkInIslandIntent()) {
                Label("Talk in the Island", systemImage: "waveform.circle")
            }
        }
        .displayName("Talk in the Island")
        .description("Starts a conversation without opening Doddy. He stays in the Dynamic Island while you talk.")
    }
}
