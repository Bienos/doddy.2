import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island and Lock Screen for the focus timer (Tiny Promise, ADR-241), breathing
/// (Calm Tide, ADR-242) and reading a note aloud (Story Spool, ADR-243), from the owner's V4
/// boards. Countdowns tick on their own; everything else changes only when the app sends a new
/// state or iOS marks it stale (see `ToolLiveActivity` for what stale means for each).
struct DoddyToolLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoddyToolAttributes.self) { context in
            ToolLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color("CardBackground"))
                .activitySystemActionForegroundColor(Color("Ink"))
        } dynamicIsland: { context in
            let scene = context.attributes.islandScene(context.state, isStale: context.isStale)
            let startedAt = context.attributes.startedAt
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandLabelView(scene: scene)
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandTimeView(scene: scene, startedAt: startedAt)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottomView(scene: scene, startedAt: startedAt) {
                        ToolButtons(kind: context.attributes.kind, state: context.state, scene: scene)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                IslandCompactLeadingView(scene: scene)
            } compactTrailing: {
                IslandCompactTrailingView(scene: scene, startedAt: startedAt)
            } minimal: {
                IslandMinimalView(scene: scene, startedAt: startedAt)
            }
            .keylineTint(scene.live ? Color.islandOrange : Color.islandSecondary)
        }
    }
}

/// Pause/Resume (focus, read-aloud) and Stop as the boards' pills. Nothing once it is over.
private struct ToolButtons: View {
    let kind: DoddyToolAttributes.Kind
    let state: DoddyToolAttributes.ContentState
    let scene: IslandScene

    private var over: Bool { state.isFinished || (!scene.live && !state.isPaused) }

    var body: some View {
        HStack(spacing: 6) {
            if !over {
                if kind != .breathing {
                    Button(intent: ToggleDoddyToolPauseIntent(kind)) {
                        IslandPillLabel(title: state.isPaused ? "Resume" : "Pause",
                                        systemImage: state.isPaused ? "play.fill" : "pause.fill",
                                        prominent: state.isPaused)
                    }
                    .buttonStyle(.plain)
                }
                Button(intent: StopDoddyToolIntent(kind)) {
                    IslandPillLabel(title: "Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: StopDoddyToolIntent(kind)) {
                    IslandPillLabel(title: "Dismiss", systemImage: "xmark")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The Lock Screen card: same words as the island, in the Lock Screen colours (ADR-106).
private struct ToolLockScreenView: View {
    let attributes: DoddyToolAttributes
    let state: DoddyToolAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let scene = attributes.islandScene(state, isStale: isStale)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                IslandArtView(art: scene.art(.compact), face: scene.face, live: scene.live)
                    .background(Color.islandBlack, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(scene.label.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color("SecondaryText"))
                    Group {
                        switch scene.bigTitle {
                        case .countdown(let end): IslandCountdownText(end: end)
                        case .bigText(let text): Text(text).monospacedDigit()
                        default: Text(scene.title)
                        }
                    }
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color("Ink"))
                    Text(scene.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(scene.subtitleIsWarning ? Color("Error") : Color("SecondaryText"))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if case .countdown(let end) = scene.time {
                    IslandCountdownText(end: end)
                        .font(.headline)
                        .foregroundStyle(Color("AccentText"))
                }
            }
            ToolButtons(kind: attributes.kind, state: state, scene: scene)
        }
        .padding(16)
    }
}
