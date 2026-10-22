import AppIntents
import SwiftUI
import WidgetKit

/// "Talk to Doddy" for the Action Button, Control Center and the Lock Screen (iOS 18+). The user
/// adds it there themselves (iPhone Settings › Action Button › Controls); Doddy can't place it or
/// tell whether it was added. A press runs `TalkButtonIntent`, which follows Settings › Action
/// Button in Doddy (ADR-579): the Dynamic Island without opening Doddy by default, or the app.
/// Until ADR-579 this control always opened the app (`TalkToDoddyIntent`); the kind is unchanged,
/// so a button that already has it keeps it and gets the new behaviour.
@available(iOS 18.0, *)
struct TalkToDoddyControl: ControlWidget {
    static let kind = "com.bienos.doddy2.talk"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TalkButtonIntent()) {
                Label("Talk to Doddy", systemImage: "waveform")
            }
        }
        .displayName("Talk to Doddy")
        .description("Talks to Doddy the way you chose in Doddy's Settings: in the Dynamic Island or in the app. Press again to end.")
    }
}
