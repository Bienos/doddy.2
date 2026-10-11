import SwiftUI
import WidgetKit

/// Widget extension: the voice conversation's Live Activity, the tools' Live Activity (focus,
/// breathing, read-aloud), the Home and Lock Screen widgets (ADR-219) and, on iOS 18+, the
/// Talk to Doddy and New note controls.
@main
struct DoddyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DoddyVoiceLiveActivity()
        ShoppingLiveActivity()
        DoddyToolLiveActivity()
        PinnedNotesWidget()
        NextReminderWidget()
        ListWidget()
        TalkToDoddyWidget()
        if #available(iOS 18.0, *) {
            TalkToDoddyControl()
            NewNoteControl()
        }
    }
}
