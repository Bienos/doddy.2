#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
import WidgetKit

/// The snooze countdown of a Doddy alarm (ADR-267), on the Lock Screen and in the Dynamic Island.
/// AlarmKit draws the ringing alarm itself; this only shows the minutes until it rings again.
@available(iOS 26.0, *)
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<DoddyAlarmMetadata>.self) { context in
            HStack {
                Image(systemName: "zzz")
                Text("Snoozed")
                Spacer()
                countdown(context.state)
                    .font(.title2.monospacedDigit())
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "alarm") }
                DynamicIslandExpandedRegion(.trailing) { countdown(context.state).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) { Text("Snoozed").font(.caption) }
            } compactLeading: {
                Image(systemName: "zzz")
            } compactTrailing: {
                countdown(context.state).monospacedDigit().frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "alarm")
            }
        }
    }

    @ViewBuilder
    private func countdown(_ state: AlarmPresentationState) -> some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
        default:
            Image(systemName: "alarm")
        }
    }
}
#endif
