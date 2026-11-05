import AppIntents
import SwiftUI
import WidgetKit

/// "Talk to Doddy" for Control Center, the Lock Screen and the Action Button (iOS 18+). The user
/// adds it there themselves; Doddy can't place it or tell whether it was added. A press runs
/// `TalkInIslandIntent` (ADR-727, owner, 5 Nov 2026): Doddy appears in the Dynamic Island, says
/// "Hey Pat, what's up?" and listens, and the app does not open. Siri, Back Tap and the
/// Shortcuts app still use `TalkToDoddyIntent`, which opens Doddy.
@available(iOS 18.0, *)
struct TalkToDoddyControl: ControlWidget {
    static let kind = "com.bienos.doddy2.talk"

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
