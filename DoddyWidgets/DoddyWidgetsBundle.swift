import SwiftUI
import WidgetKit

/// Widget extension: the voice conversation's Live Activity, the tools' Live Activity (focus,
/// breathing, read-aloud) and, on iOS 18+, the Talk to Doddy control.
@main
struct DoddyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DoddyVoiceLiveActivity()
        DoddyToolLiveActivity()
        if #available(iOS 18.0, *) {
            TalkToDoddyControl()
            NewNoteControl()
        }
    }
}
