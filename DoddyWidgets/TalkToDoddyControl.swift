import AppIntents
import SwiftUI
import WidgetKit

/// "Talk to Doddy" for the Action Button, Control Center and the Lock Screen (iOS 18+). The user
/// adds it there themselves (iPhone Settings › Action Button › Controls); Doddy can't place it or
/// tell whether it was added. A press runs `TalkButtonIntent`: the conversation starts in the
/// Dynamic Island without opening Doddy, and a second press ends it (ADR-632). When something only
/// the app can fix is missing, iOS asks "Open Doddy?" with the reason.
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
        .description("Talks to Doddy in the Dynamic Island, without opening him. Press again to end.")
    }
}
