import SwiftUI
import WidgetKit

/// Widget extension. Today it only draws the voice conversation's Live Activity.
@main
struct DoddyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DoddyVoiceLiveActivity()
    }
}
