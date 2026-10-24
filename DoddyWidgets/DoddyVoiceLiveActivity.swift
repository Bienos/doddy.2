import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island and Lock Screen for a running conversation: Doddy, what he is doing right now
/// (from real SDK events), how long you have been talking, and Mute / End.
/// With "Hey Doddy" on (ADR-254) the same activity first says the iPhone is listening for the
/// wake word, with only Stop listening; after the wake word it greets the user ("Hey Pat, what's up?").
/// Tapping it opens the app; while a card waits (a note, a text, a transfer, …) or something Doddy
/// made is ready, it opens the conversation on that card (`doddy://conversation`, ADR-608), and the
/// expanded island's main button is Show. Nothing is approved from the island: the card is.
/// When the app has not refreshed the activity for `VoiceLiveActivity.staleAfter` (iOS ended
/// it in the background), iOS marks it stale and this view says so instead of "Listening".
///
/// The Lock Screen card is cream in light and dark mode (ADR-266, `doddyCreamLockScreen`), with
/// Doddy in the island's Whole Doddy pose (`DoddyArt`, ADR-299).
/// The Dynamic Island is always black and follows the owner's V4 boards (`Shared/IslandArt`).
/// No words from the conversation appear here: the Lock Screen is visible to anyone.
struct DoddyVoiceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoddyVoiceAttributes.self) { context in
            let scene = context.state.islandScene(isStale: context.isStale)
            return LockScreenView(shown: Shown(context), scene: scene,
                           startedAt: context.state.conversationStart(activityStartedAt: context.attributes.startedAt))
                .doddyCreamLockScreen()
                .widgetURL(scene.showsInDoddy ? Self.conversationLink : nil)
        } dynamicIsland: { context in
            let shown = Shown(context)
            let scene = context.state.islandScene(isStale: context.isStale).respectingHiddenArt
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
                        IslandControls(shown: shown, showsInDoddy: scene.showsInDoddy)
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
            // ADR-608: a tap anywhere on the island goes to the card that waits, not only Home.
            .widgetURL(scene.showsInDoddy ? Self.conversationLink : nil)
        }
    }

    /// `DeepLink.conversation` in DoddyCore: the running conversation, on the card that waits.
    static let conversationLink = URL(string: "doddy://conversation")!
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
    /// Lock Screen roles from the asset catalog (Pocket Notebook semantic colours). The card
    /// draws in the light scheme (ADR-266), so these are always their dark-on-cream values.
    static let card = Color("CardBackground")
    static let ink = Color("Ink")
    static let secondary = Color("SecondaryText")
    static let accentText = Color("AccentText")
    static let confirmed = Color("Confirmed")
    static let error = Color("Error")
}

/// Doddy himself, in the same Whole Doddy pose as the island (ADR-299, ADR-264): one pose
/// means one thing everywhere, whichever island style is picked. Poses are the owner's numbered
/// pack (`WholeDoddy_*`; see docs/design/UPLOADED_MEMORY_ASSETS.md). Once the conversation has
/// ended he does the fist pump only if a note was saved; otherwise he sits and waits.
/// Lock Screen only. The card is cream (ADR-266), so the drawing needs no backing or edge.
private struct DoddyArt: View {
    let shown: Shown
    let size: CGFloat

    private var pose: IslandPose {
        if shown.state.isFailed { return .facepalm }
        if shown.state.isEnded { return shown.state.savedCount > 0 ? .fistpump : .crosslegged }
        // Translating keeps its board on the island (no pose); here he listens.
        return shown.state.wholeDoddyPose(stale: shown.isStale) ?? .listening
    }

    var body: some View {
        // Nothing when "Hide character artwork" is on in Doddy (ADR-331).
        if !WidgetDoddyArt.isHidden {
            IslandPoseView(pose: pose, maxSize: CGSize(width: size, height: size * 1.25), edged: false)
        }
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
    /// A card waits or something is ready in the conversation (ADR-608): Show, in cream, opens
    /// it; otherwise Open goes to Home.
    var showsInDoddy = false

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
            if showsInDoddy, !shown.isStale {
                // The card itself, in the conversation; opening it approves nothing.
                Link(destination: DoddyVoiceLiveActivity.conversationLink) {
                    IslandPillLabel(title: "Show", systemImage: "hand.tap.fill", prominent: !shown.state.isMuted)
                }
                .buttonStyle(.plain)
            } else {
                // Opens the app's home screen (doddy://home, as the Lock Screen's "Open Doddy" does).
                // Always offered: on a stale island it is the way back to Doddy.
                Link(destination: URL(string: "doddy://home")!) {
                    IslandPillLabel(title: "Open", systemImage: "arrow.up.forward.app")
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
    /// The island's scene, for a card that waits (ADR-608): its fixed words and Show.
    let scene: IslandScene
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
                if scene.showsInDoddy, !shown.isStale {
                    Link(destination: DoddyVoiceLiveActivity.conversationLink) {
                        Label("Show in Doddy", systemImage: "hand.tap.fill")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(Palette.card)
                            .background(Palette.ink, in: Capsule())
                    }
                }
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
                if shown.state.savedCount > 0, !shown.state.isFailed {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.confirmed)
                }
                Text(shown.detail ?? "")
                    .foregroundStyle(shown.state.savedCount > 0 && !shown.state.isFailed ? Palette.confirmed : Palette.secondary)
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
        } else if scene.showsInDoddy {
            // ADR-608: what kind of thing waits, in the island's fixed words; never what it says.
            VStack(alignment: .leading, spacing: 2) {
                Text(scene.title)
                    .foregroundStyle(Palette.accentText)
                Text(scene.subtitle)
                    .foregroundStyle(Palette.secondary)
            }
            .font(.subheadline)
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
