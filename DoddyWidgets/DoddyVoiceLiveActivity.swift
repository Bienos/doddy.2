import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island and Lock Screen for a running conversation: Doddy, what he is doing right now
/// (from real SDK events), how long you have been talking, and Mute / End.
/// With "Hey Doddy" on (ADR-254) the same activity first says the iPhone is listening for the
/// wake word, with only Stop listening; after the wake word it greets the user ("Hey Pat, what's up?").
/// Tapping it opens the app (e.g. to Save or Don't save a proposed note).
/// When the app has not refreshed the activity for `VoiceLiveActivity.staleAfter` (iOS ended
/// it in the background), iOS marks it stale and this view says so instead of "Listening".
///
/// The Lock Screen card follows the phone's light/dark setting (paper card in light, Night card
/// in dark, colours from this target's asset catalog), with the approved pose art (`DoddyArt`).
/// The Dynamic Island is always black and follows the owner's V4 boards (`Shared/IslandArt`).
/// No words from the conversation appear here: the Lock Screen is visible to anyone.
struct DoddyVoiceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoddyVoiceAttributes.self) { context in
            LockScreenView(shown: Shown(context), startedAt: context.state.conversationStart(activityStartedAt: context.attributes.startedAt))
                .activityBackgroundTint(Palette.card)
                .activitySystemActionForegroundColor(Palette.ink)
        } dynamicIsland: { context in
            let shown = Shown(context)
            let scene = context.state.islandScene(isStale: context.isStale)
            // After "Hey Doddy" (ADR-254) the timer counts from the conversation, not the listening.
            let startedAt = context.state.conversationStart(activityStartedAt: context.attributes.startedAt)
            // The owner's V4 boards (design/dynamic-island-v4): the style picked in Settings
            // (ADR-239), or Thought Pocket / Step Stones / Reminder Knot for a moment (ADR-240).
            // Label and time beside the camera; drawing, status, buttons and sign below it.
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
                        IslandControls(shown: shown)
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

/// What to draw: the state the app sent, unless iOS reports it stale.
private struct Shown {
    let state: DoddyVoiceAttributes.ContentState
    let isStale: Bool

    init(_ context: ActivityViewContext<DoddyVoiceAttributes>) {
        state = context.state
        // The "ended" card claims nothing that can go out of date.
        isStale = context.isStale && !context.state.isEnded
    }

    var title: String {
        guard isStale else { return state.title }
        // A stale "Hey Doddy" activity: iOS ended the app, so nothing is listening any more.
        return state.isWakeMode ? "Not listening — open Doddy" : "Lost Doddy — open the app"
    }
    var detail: String? { isStale ? nil : state.detail }
    /// Orange only while Doddy is live and can hear you; never when muted, stale or ended.
    var showsLiveCue: Bool { !isStale && state.isLiveCue }
}

private enum Palette {
    /// The bright orange cue (design token). Decoration only, never reading text on paper.
    static let orange = Color(red: 0xF5 / 255, green: 0x8A / 255, blue: 0x24 / 255)
    /// Lock Screen roles, light/dark from the asset catalog (Pocket Notebook semantic colours).
    static let card = Color("CardBackground")
    static let ink = Color("Ink")
    static let secondary = Color("SecondaryText")
    static let accentText = Color("AccentText")
    static let confirmed = Color("Confirmed")
    static let error = Color("Error")
    /// Same paper as `UploadedCharacterView`'s dark-mode backing.
    static let paperBacking = Color(red: 245 / 255, green: 239 / 255, blue: 226 / 255)
}

/// Doddy himself, from the owner's approved numbered pack (`UploadedDoddy_*`, byte-identical to
/// the ZIP; see docs/design/UPLOADED_MEMORY_ASSETS.md): listening while the conversation runs;
/// once it has ended, the fist-pump "kept" pose if a note was saved, else sitting.
/// Lock Screen only. The drawings are cream and black with no dark variant, so on the dark
/// Lock Screen they sit on a light paper backing, as `UploadedCharacterView` does in the app.
private struct DoddyArt: View {
    let shown: Shown
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var assetName: String {
        // Waiting for "Hey Doddy" is not a conversation: Doddy sits until he is called.
        if shown.state.isWakeMode { return "UploadedDoddy_Sitting" }
        guard shown.state.isEnded else { return "UploadedDoddy_Listening" }
        return shown.state.savedCount > 0 ? "UploadedDoddy_Kept" : "UploadedDoddy_Sitting"
    }

    var body: some View {
        let backed = colorScheme == .dark
        Image(decorative: assetName)
            .resizable()
            .scaledToFit()
            .padding(backed ? size * 0.08 : 0)
            .frame(width: size, height: size)
            .background(backed ? Palette.paperBacking : .clear, in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

private struct ElapsedTime: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
    }
}

/// Mute and Stop on the island, as the boards' pills. Stop ends the conversation (End intent).
/// The boards' Pause, Open and Cancel are not used: a conversation can't be paused, and
/// tapping the island already opens Doddy. While "Hey Doddy" waits (ADR-254) there is only
/// Stop listening, which turns it off.
private struct IslandControls: View {
    let shown: Shown

    var body: some View {
        HStack(spacing: 6) {
            // Mute needs the conversation's process; a stale island has none to talk to.
            // "Hey Doddy" listening has nothing to mute.
            if !shown.isStale, !shown.state.isEnded, !shown.state.isWakeMode {
                Button(intent: ToggleDoddyMuteIntent()) {
                    // While muted, Unmute is the cream pill so getting Doddy back is one obvious tap.
                    IslandPillLabel(title: shown.state.isMuted ? "Unmute" : "Mute",
                                    systemImage: shown.state.isMuted ? "mic.fill" : "mic.slash.fill",
                                    prominent: shown.state.isMuted)
                }
                .buttonStyle(.plain)
            }
            Button(intent: EndDoddyConversationIntent()) {
                IslandPillLabel(title: shown.isStale ? "Dismiss" : (shown.state.isWakeMode ? "Stop listening" : "Stop"),
                                systemImage: shown.isStale ? "xmark" : "stop.fill")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct Controls: View {
    let shown: Shown

    var body: some View {
        HStack(spacing: 10) {
            // Mute needs the conversation's process; a stale island has none to talk to.
            // "Hey Doddy" listening has nothing to mute: Stop listening turns it off.
            if !shown.isStale && !shown.state.isWakeMode {
                muteButton
            }
            Button(intent: EndDoddyConversationIntent()) {
                Label(endTitle, systemImage: endSymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Palette.error)
        }
        .font(.callout.weight(.semibold))
    }

    private var endTitle: String {
        if shown.isStale { return "Dismiss" }
        return shown.state.isWakeMode ? "Stop listening" : "End"
    }

    private var endSymbol: String {
        if shown.isStale { return "xmark" }
        return shown.state.isWakeMode ? "xmark.circle" : "phone.down.fill"
    }

    /// While muted, Unmute is the main button, so getting Doddy back is one obvious tap.
    @ViewBuilder
    private var muteButton: some View {
        let muted = shown.state.isMuted
        let button = Button(intent: ToggleDoddyMuteIntent()) {
            Label(muted ? "Unmute" : "Mute", systemImage: muted ? "mic.fill" : "mic.slash.fill")
                .frame(maxWidth: .infinity)
        }
        if muted {
            button
                .buttonStyle(.borderedProminent)
                .tint(Palette.ink)
                .foregroundStyle(Palette.card)
        } else {
            button
                .buttonStyle(.bordered)
                .tint(Palette.ink)
        }
    }
}

private struct LockScreenView: View {
    let shown: Shown
    let startedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DoddyArt(shown: shown, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(shown.state.isEnded ? shown.title : (shown.state.isWakeMode ? "Hey Doddy is on" : "Talking to Doddy"))
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    statusLine
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                if shown.showsLiveCue {
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(Palette.orange)
                        .accessibilityHidden(true)
                } else if shown.state.showsMuted, !shown.isStale {
                    Image(systemName: "mic.slash")
                        .font(.title3)
                        .foregroundStyle(Palette.secondary)
                        .accessibilityHidden(true)
                }
            }
            if shown.state.isEnded {
                Link(destination: URL(string: "doddy://home")!) {
                    Text("Open Doddy")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Palette.ink)
                        .background(Palette.secondary.opacity(0.15), in: Capsule())
                }
            } else {
                Controls(shown: shown)
            }
        }
        .padding(16)
    }

    /// "Listening · 2:14", "Muted · Doddy can't hear you", "Doddy isn't listening · 1 note saved".
    @ViewBuilder
    private var statusLine: some View {
        if shown.state.isEnded {
            HStack(spacing: 4) {
                if shown.state.savedCount > 0 {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.confirmed)
                }
                Text(shown.detail ?? "")
                    .foregroundStyle(shown.state.savedCount > 0 ? Palette.confirmed : Palette.secondary)
                if let endedAt = shown.state.endedAt {
                    Text("· \(Self.total(from: startedAt, to: endedAt)) total")
                        .foregroundStyle(Palette.secondary)
                }
            }
            .font(.subheadline)
        } else if shown.isStale {
            Text(shown.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.error)
        } else if shown.state.isWakeMode {
            VStack(alignment: .leading, spacing: 2) {
                Text(shown.title)
                    .foregroundStyle(Palette.accentText)
                Text(shown.detail ?? "")
                    .foregroundStyle(Palette.secondary)
            }
            .font(.subheadline)
        } else if let detail = shown.detail {
            Text("\(shown.title) · \(detail)")
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
        } else {
            HStack(spacing: 4) {
                Text(shown.title)
                Text("·")
                ElapsedTime(startedAt: startedAt)
            }
            .font(.subheadline)
            .foregroundStyle(Palette.accentText)
        }
    }

    private static func total(from start: Date, to end: Date) -> String {
        Duration.seconds(max(0, end.timeIntervalSince(start).rounded()))
            .formatted(.time(pattern: .minuteSecond))
    }
}
