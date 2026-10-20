import SwiftUI
import WidgetKit

/// Widget extension: the voice conversation's Live Activity, Doddy's calls for the user, the tools' Live Activity (focus,
/// read-aloud), the Home and Lock Screen widgets (ADR-219) and, on iOS 18+, the
/// Talk to Doddy and New note controls.
@main
struct DoddyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        widgets()
    }

    /// From iOS 18 the tools' Live Activity is the one with an Apple Watch layout (ADR-454), and
    /// the controls exist; before that, the plain one. Two whole lists chosen with a plain
    /// `if #available` return (an opaque result may differ per availability branch, SE-0360):
    /// the bundle builder only takes `if #available` without `else`, so an `if #unavailable` entry
    /// in `body` doesn't compile (CI run 38330112860).
    private func widgets() -> some Widget {
        if #available(iOS 18.0, *) {
            return iOS18Widgets
        }
        return iOS17Widgets
    }

    @available(iOS 18.0, *)
    @WidgetBundleBuilder
    private var iOS18Widgets: some Widget {
        DoddyVoiceLiveActivity()
        ShoppingLiveActivity()
        // Doddy on a call for the user (ADR-504).
        DoddyCallLiveActivity()
        DoddyToolLiveActivityWithWatch()
        // One entry for all Home Screen widgets: the bundle builder has taken at most ten (ADR-331).
        DoddyHomeWidgets().body
        TalkToDoddyControl()
        NewNoteControl()
        #if canImport(AlarmKit)
        // A Doddy alarm's snooze countdown (ADR-283), iOS 26 and later.
        if #available(iOS 26.0, *) {
            AlarmLiveActivity()
        }
        #endif
    }

    @WidgetBundleBuilder
    private var iOS17Widgets: some Widget {
        DoddyVoiceLiveActivity()
        ShoppingLiveActivity()
        DoddyCallLiveActivity()
        DoddyToolLiveActivity()
        DoddyHomeWidgets().body
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
