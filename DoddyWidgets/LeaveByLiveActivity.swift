import ActivityKit
import SwiftUI
import WidgetKit

/// "Leave in 12:30" on the Lock Screen and in the Dynamic Island (ADR-347). After the leave time
/// iOS marks it stale (the app sets the stale date to the leave time) and it says "Time to leave".
/// On watchOS 11 and later iOS also puts it in the watch's Smart Stack.
struct LeaveByLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LeaveByActivityAttributes.self) { context in
            LeaveByLockScreenView(place: context.attributes.placeName, state: context.state, isStale: context.isStale)
                .doddyCreamLockScreen()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.placeName, systemImage: "figure.walk")
                        .font(.subheadline).lineLimit(1)
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LeaveByTime(state: context.state, isStale: context.isStale)
                        .font(.headline)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(String(format: NSLocalizedString("Leave at %@ to be there by %@", comment: "Leave-by island"),
                                context.state.leaveAt.formatted(date: .omitted, time: .shortened),
                                context.state.arriveBy.formatted(date: .omitted, time: .shortened)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "figure.walk").accessibilityLabel(Text("Time to leave"))
            } compactTrailing: {
                LeaveByTime(state: context.state, isStale: context.isStale).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "figure.walk").accessibilityLabel(Text("Time to leave"))
            }
        }
    }
}

private struct LeaveByTime: View {
    let state: LeaveByActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale || state.leaveAt <= Date() {
            Text("Now")
        } else {
            Text(timerInterval: Date()...state.leaveAt, countsDown: true).monospacedDigit()
        }
    }
}

private struct LeaveByLockScreenView: View {
    let place: String
    let state: LeaveByActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.title2)
                .foregroundStyle(Color("AccentText"))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(place)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color("SecondaryText"))
                    .lineLimit(1)
                if isStale || state.leaveAt <= Date() {
                    Text("Time to leave").font(.title2.weight(.medium)).foregroundStyle(Color("Ink"))
                } else {
                    HStack(spacing: 6) {
                        Text("Leave in").foregroundStyle(Color("Ink"))
                        Text(timerInterval: Date()...state.leaveAt, countsDown: true)
                            .monospacedDigit()
                            .foregroundStyle(Color("Ink"))
                    }
                    .font(.title2.weight(.medium))
                }
                Text(String(format: NSLocalizedString("Be there by %@. Traffic may have changed since you set this.", comment: "Leave-by Lock Screen"),
                            state.arriveBy.formatted(date: .omitted, time: .shortened)))
                    .font(.footnote)
                    .foregroundStyle(Color("SecondaryText"))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
