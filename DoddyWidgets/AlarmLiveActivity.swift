#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
import WidgetKit

/// The snooze countdown of a Doddy alarm (ADR-283), on the Lock Screen and in the Dynamic Island.
/// AlarmKit draws the ringing alarm itself; this only shows the minutes until it rings again.
/// Doddy stretches awake beside it, on the cream card like his other Lock Screen cards (ADR-323).
@available(iOS 26.0, *)
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<DoddyAlarmMetadata>.self) { context in
            HStack(spacing: 12) {
                WidgetPose(pose: .yawnStretch, height: 64)
                Label("Snoozed", systemImage: "zzz")
                    .font(.headline)
                Spacer()
                countdown(context.state)
                    .font(.title2.monospacedDigit())
            }
            .padding()
            .doddyCreamLockScreen()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if WidgetDoddyArt.isHidden {
                        Image(systemName: "alarm")
                    } else {
                        IslandPoseView(pose: .yawnStretch, maxSize: CGSize(width: 44, height: 52))
                            .padding(.leading, 6)
                    }
                }
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
            // Never a backwards range, even if this draws after the alarm was due (ADR-331).
            Text(timerInterval: Date.now...max(Date.now, countdown.fireDate), countsDown: true)
        default:
            Image(systemName: "alarm")
        }
    }
}
#endif
