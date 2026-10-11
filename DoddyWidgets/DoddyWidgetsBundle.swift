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
        // The tools' Live Activity; from iOS 18 the same one with an Apple Watch layout (ADR-444).
        if #available(iOS 18.0, *) {
            DoddyToolLiveActivityWithWatch()
        }
        if #unavailable(iOS 18.0) {
            DoddyToolLiveActivity()
        }
        // One entry for all Home Screen widgets: the bundle builder has taken at most ten (ADR-331).
        DoddyHomeWidgets().body
        if #available(iOS 18.0, *) {
            TalkToDoddyControl()
            NewNoteControl()
        }
        #if canImport(AlarmKit)
        // A Doddy alarm's snooze countdown (ADR-283), iOS 26 and later.
        if #available(iOS 26.0, *) {
            AlarmLiveActivity()
        }
        #endif
    }
}

/// The Home Screen, Lock Screen and StandBy widgets, grouped so the main bundle stays within the
/// builder's ten entries (ADR-331).
struct DoddyHomeWidgets: WidgetBundle {
    var body: some Widget {
        PinnedNotesWidget()
        NextReminderWidget()
        ParkingWidget()
        ListWidget()
        TalkToDoddyWidget()
        NewNoteWidget()
        DoddyRestWidget()
    }
}
