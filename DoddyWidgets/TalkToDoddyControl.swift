import AppIntents
import SwiftUI
import WidgetKit

/// "Talk to Doddy" for Control Center, the Lock Screen and the Action Button (iOS 18+). The user
/// adds it there themselves; Doddy can't place it or tell whether it was added. A tap runs
/// `TalkToDoddyIntent`, which opens Doddy and starts the conversation.
@available(iOS 18.0, *)
struct TalkToDoddyControl: ControlWidget {
    static let kind = "com.bienos.doddy2.talk"

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
