import AppIntents
import SwiftUI
import WidgetKit

/// "New note" for Control Center, the Lock Screen and the Action Button (iOS 18+). The user adds
/// it there themselves. A tap runs `NewNoteIntent`, which opens Doddy's empty capture screen.
@available(iOS 18.0, *)
struct NewNoteControl: ControlWidget {
    static let kind = "com.bienos.doddy2.newnote"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: NewNoteIntent()) {
                Label("New note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New note in Doddy")
        .description("Opens Doddy ready for a new note. Nothing is saved until you tap Save.")
    }
}
