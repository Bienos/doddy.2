import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action Button control (iOS 18+). The user adds it themselves;
/// Doddy can't place it. Tapping it runs `TalkToDoddyIntent`, which opens the app.
@main
struct DoddyControlsBundle: WidgetBundle {
    var body: some Widget {
        TalkToDoddyControl()
    }
}

struct TalkToDoddyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.bienos.doddy2.talk") {
            ControlWidgetButton(action: TalkToDoddyIntent()) {
                Label("Talk to Doddy", systemImage: "waveform")
            }
        }
        .displayName("Talk to Doddy")
        .description("Opens Doddy and starts a voice conversation.")
    }
}
