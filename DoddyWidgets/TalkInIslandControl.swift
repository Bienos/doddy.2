import AppIntents
import SwiftUI
import WidgetKit

/// "Talk in the Island" for the Action Button, Control Center and the Lock Screen (iOS 18+,
/// ADR-577): starts a conversation without opening Doddy (`TalkInIslandIntent`); he greets you and
/// stays in the Dynamic Island. The user adds it themselves (Settings › Action Button › Controls);
/// Doddy can't place it or tell whether it was added. Since ADR-579 "Talk to Doddy" is the one
/// Doddy recommends (it follows Settings › Action Button); this one stays so a button that already
/// has it keeps working, and it always uses the island.
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
        .description("Always talks in the Dynamic Island, without opening Doddy. Press again to end.")
    }
}
