import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island and Lock Screen for a running conversation: Doddy's face, what he is doing
/// right now (from real SDK events), how long you have been talking, and Mute / End.
/// Tapping it opens the app (e.g. to Save or Don't save a proposed note).
/// When the app has not refreshed the activity for `VoiceLiveActivity.staleAfter` (iOS ended
/// it in the background), iOS marks it stale and this view says so instead of "Listening".
struct DoddyVoiceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoddyVoiceAttributes.self) { context in
            LockScreenView(shown: Shown(context), startedAt: context.attributes.startedAt)
                .activityBackgroundTint(IslandStyle.lockScreenBackground)
                .activitySystemActionForegroundColor(IslandStyle.ink)
        } dynamicIsland: { context in
            let shown = Shown(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DoddyHead(size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(shown.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Doddy")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityElement(children: .combine)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedTime(startedAt: context.attributes.startedAt)
                        .font(.callout)
                        .foregroundStyle(IslandStyle.orange)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Controls(shown: shown, onDark: true)
                        .padding(.top, 4)
                }
            } compactLeading: {
                DoddyHead(size: 24)
            } compactTrailing: {
                Image(systemName: shown.symbolName)
                    .foregroundStyle(shown.isStale ? .yellow : IslandStyle.orange)
                    .accessibilityLabel(shown.title)
            } minimal: {
                DoddyHead(size: 22)
            }
            .keylineTint(IslandStyle.orange)
        }
    }
}

/// What to draw: the state the app sent, unless iOS reports it stale.
private struct Shown {
    let state: DoddyVoiceAttributes.ContentState
    let isStale: Bool

    init(_ context: ActivityViewContext<DoddyVoiceAttributes>) {
        state = context.state
        isStale = context.isStale
    }

    var title: String { isStale ? "Lost Doddy — open the app" : state.title }
    var symbolName: String { isStale ? "exclamationmark.triangle.fill" : state.symbolName }
}

private enum IslandStyle {
    /// Candidate tokens (DoddyDesignTokens): orange cue, reading ink, canvas.
    static let orange = Color(red: 0xF5 / 255, green: 0x8A / 255, blue: 0x24 / 255)
    static let ink = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x15 / 255)
    static let lockScreenBackground = Color(red: 0xFF / 255, green: 0xF7 / 255, blue: 0xE9 / 255)
}

private struct DoddyHead: View {
    let size: CGFloat

    var body: some View {
        Image("DoddyHead")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct ElapsedTime: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 64, alignment: .trailing)
    }
}

private struct Controls: View {
    let shown: Shown
    let onDark: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Mute needs the conversation's process; a stale island has none to talk to.
            if !shown.isStale {
                Button(intent: ToggleDoddyMuteIntent()) {
                    Label(shown.state.isMuted ? "Unmute" : "Mute", systemImage: shown.state.isMuted ? "mic.fill" : "mic.slash.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(onDark ? .white : IslandStyle.ink)
            }
            Button(intent: EndDoddyConversationIntent()) {
                Label(shown.isStale ? "Dismiss" : "End", systemImage: shown.isStale ? "xmark" : "phone.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .font(.callout.weight(.semibold))
        .buttonStyle(.bordered)
    }
}

private struct LockScreenView: View {
    let shown: Shown
    let startedAt: Date

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                DoddyHead(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Doddy")
                        .font(.caption)
                        .foregroundStyle(IslandStyle.ink.opacity(0.7))
                    Label(shown.title, systemImage: shown.symbolName)
                        .font(.headline)
                        .foregroundStyle(IslandStyle.ink)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                ElapsedTime(startedAt: startedAt)
                    .font(.headline)
                    .foregroundStyle(IslandStyle.ink)
            }
            Controls(shown: shown, onDark: false)
        }
        .padding(16)
        .environment(\.colorScheme, .light)
    }
}
