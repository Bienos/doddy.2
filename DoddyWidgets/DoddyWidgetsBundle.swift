import SwiftUI
import WidgetKit

/// Widget extension: the voice conversation's Live Activity; the Talk to Doddy, Pinned notes and
/// Next note reminder widgets (ADR-233); and, on iOS 18+, the Talk to Doddy and New note controls.
@main
struct DoddyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DoddyVoiceLiveActivity()
        TalkWidget()
        PinnedNotesWidget()
        NextReminderWidget()
        if #available(iOS 18.0, *) {
            TalkToDoddyControl()
            NewNoteControl()
        }
    }
}
