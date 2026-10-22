import AppIntents
import SwiftUI
import WidgetKit

/// "Record with DODDY" for Control Center, the Lock Screen and the Action Button (iOS 18+, ADR-579).
/// It opens Doddy and starts recording (`RecordWithDoddyIntent`); the recording then carries on in
/// the Dynamic Island. iOS does not let a recording begin from a cold background, so it cannot start
/// with no screen at all (docs/implementation/CAPTURE_AUDIT.md section 3). The user adds it
/// themselves (Settings › Action Button › Controls); Doddy can't place it or tell whether it was
/// added. "Talk in the Island" and "Talk to Doddy" are separate controls and are left alone.
@available(iOS 18.0, *)
struct StartRecordingControl: ControlWidget {
    static let kind = "com.bienos.doddy2.record"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: RecordWithDoddyIntent()) {
                Label("Record with DODDY", systemImage: "record.circle")
            }
        }
        .displayName("Record with DODDY")
        .description("Opens Doddy and starts recording a meeting or conversation. The recording goes on in the Dynamic Island.")
    }
}
