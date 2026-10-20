import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Doddy on a call for the user, on the Lock Screen and in the Dynamic Island (ADR-504): what is
/// happening and for how long, with Take over and End. Never who is called or what was said
/// (ADR-240); that is only in the app. Doddy's listening pose, as on the conversation island;
/// he sits when the call has ended and is not shown listening when the card is stale
/// (`DoddyActivityPose.call`, ADR-546).
struct DoddyCallLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoddyCallAttributes.self) { context in
            CallLockScreen(caseId: context.attributes.caseId, state: context.state, isStale: context.isStale)
                .doddyCreamLockScreen()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if WidgetDoddyArt.isHidden {
                        Image(systemName: "phone.arrow.up.right").font(.title3).foregroundStyle(.white).padding(.leading, 6)
                            .accessibilityHidden(true)
                    } else {
                        IslandPoseView(pose: DoddyActivityPose.call(phase: context.state.phase, isStale: context.isStale),
                                       maxSize: CGSize(width: 44, height: 40))
                            .padding(.leading, 6)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    CallPhaseTitle(phase: context.state.phase).font(.headline).foregroundStyle(.white).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CallTime(state: context.state).foregroundStyle(.white).padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CallButtons(caseId: context.attributes.caseId, state: context.state, onIsland: true)
                }
            } compactLeading: {
                Image(systemName: "phone.arrow.up.right").foregroundStyle(.white).accessibilityLabel("Doddy is on a call")
            } compactTrailing: {
                CallTime(state: context.state).foregroundStyle(.white)
            } minimal: {
                Image(systemName: "phone.arrow.up.right").foregroundStyle(.white).accessibilityLabel("Doddy is on a call")
            }
        }
    }
}

/// The phase in words; literal `Text`s so the string catalogs pick them up.
struct CallPhaseTitle: View {
    let phase: String

    var body: some View {
        switch phase {
        case "ringing": Text("Doddy is calling…")
        case "connecting": Text("Connecting…")
        case "talking": Text("Doddy is talking")
        case "taken_over": Text("You're on the call")
        case "ending": Text("Saying goodbye")
        case "ended": Text("Call ended")
        default: Text("Doddy's call")
        }
    }
}

private struct CallTime: View {
    let state: DoddyCallAttributes.ContentState

    var body: some View {
        Group {
            if let answered = state.answeredAt, let ended = state.endedAt {
                Text(Duration.seconds(max(0, ended.timeIntervalSince(answered))).formatted(.time(pattern: .minuteSecond)))
            } else if let answered = state.answeredAt, !state.isOver {
                Text(answered, style: .timer)
            } else {
                EmptyView()
            }
        }
        .font(.subheadline)
        .monospacedDigit()
    }
}

private struct CallButtons: View {
    let caseId: UUID
    let state: DoddyCallAttributes.ContentState
    let onIsland: Bool

    var body: some View {
        HStack(spacing: 10) {
            if state.canTakeOver {
                Button(intent: TakeOverCallIntent(caseId: caseId)) {
                    Label("Take over", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .tint(.green)
            }
            if state.canEnd {
                Button(intent: EndDoddyCallIntent(caseId: caseId)) {
                    Label("End", systemImage: "phone.down.fill")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .tint(.red)
            }
        }
        .buttonStyle(.borderedProminent)
        .font(onIsland ? .subheadline : .body)
    }
}

private struct CallLockScreen: View {
    let caseId: UUID
    let state: DoddyCallAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label {
                        CallPhaseTitle(phase: state.phase)
                    } icon: {
                        Image(systemName: "phone.arrow.up.right")
                    }
                    .font(.headline).lineLimit(1)
                    Spacer()
                    CallTime(state: state).foregroundStyle(Color("SecondaryText"))
                }
                if isStale && !state.isOver {
                    Text("Open Doddy to see the call as it is now.").font(.subheadline)
                } else if state.isOver {
                    Text("The answer card is in Doddy.").font(.subheadline)
                } else {
                    CallButtons(caseId: caseId, state: state, onIsland: false)
                }
            }
            WidgetPose(pose: DoddyActivityPose.call(phase: state.phase, isStale: isStale), height: 64)
        }
        .foregroundStyle(Color("Ink"))
        .padding(14)
    }
}
