import AppIntents
import SwiftUI
import WidgetKit

/// The control that was "Talk in the Island" (ADR-577). It does what `TalkToDoddyControl` does:
/// the Dynamic Island without opening Doddy, press again to end (ADR-632; from ADR-593 to then it
/// opened the app). It keeps its kind, because iOS remembers a control by its kind: an Action
/// Button, Control Center or Lock Screen already set to it gets the island after the update, with
/// nothing to change in Settings.
@available(iOS 18.0, *)
struct TalkInIslandControl: ControlWidget {
    static let kind = "com.bienos.doddy2.talk-island"

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
