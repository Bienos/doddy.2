import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island and Lock Screen for a running conversation: Doddy, what he is doing right now
/// (from real SDK events), how long you have been talking, and Mute / End.
/// Tapping it opens the app (e.g. to Save or Don't save a proposed note).
/// When the app has not refreshed the activity for `VoiceLiveActivity.staleAfter` (iOS ended
/// it in the background), iOS marks it stale and this view says so instead of "Listening".
///
/// The Lock Screen card follows the phone's light/dark setting (paper card in light, Night card
/// in dark, colours from this target's asset catalog). The Dynamic Island is always black, so it
/// always uses the dark character art. Character art is the approved `Doddy_listening` and
/// `Doddy_waving` imagesets from `design/ios-ready-asset-catalog`, the same files the app uses.
/// No words from the conversation appear here: the Lock Screen is visible to anyone.
struct DoddyVoiceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoddyVoiceAttributes.self) { context in
            LockScreenView(shown: Shown(context), startedAt: context.attributes.startedAt)
                .activityBackgroundTint(Palette.card)
                .activitySystemActionForegroundColor(Palette.ink)
        } dynamicIsland: { context in
            let shown = Shown(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DoddyArt(shown: shown, size: 52, onIsland: true)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(shown.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Doddy")
                            .font(.caption)
                            .foregroundStyle(Palette.onIslandSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusGlyph(shown: shown)
                        .font(.title3)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ElapsedTime(startedAt: context.attributes.startedAt)
                            .font(.caption)
                            .foregroundStyle(Palette.onIslandSecondary)
                        Controls(shown: shown, onIsland: true)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                DoddyArt(shown: shown, size: 26, onIsland: true)
            } compactTrailing: {
                StatusGlyph(shown: shown)
            } minimal: {
                DoddyArt(shown: shown, size: 22, onIsland: true)
            }
            .keylineTint(Palette.orange)
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

    var title: String { isStale ? "Lost Doddy — open the app" : state.title }
    var detail: String? { isStale ? nil : state.detail }
    var symbolName: String { isStale ? "exclamationmark.triangle.fill" : state.symbolName }
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
    /// On the always-black Dynamic Island.
    static let onIslandSecondary = Color(red: 0xC5 / 255, green: 0xBC / 255, blue: 0xAD / 255)
    static let onIslandAccent = Color(red: 0xFF / 255, green: 0xB5 / 255, blue: 0x6B / 255)
}

/// Doddy himself: listening while the conversation runs, waving once it has ended.
private struct DoddyArt: View {
    let shown: Shown
    let size: CGFloat
    /// The island is black in light and dark mode, so it always takes the dark art.
    var onIsland = false

    @ViewBuilder
    var body: some View {
        let art = Image(shown.state.isEnded ? "Doddy_waving" : "Doddy_listening")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        if onIsland {
            art.environment(\.colorScheme, .dark)
        } else {
            art
        }
    }
}

/// The trailing status symbol on the island.
private struct StatusGlyph: View {
    let shown: Shown

    var body: some View {
        Image(systemName: shown.symbolName)
            .foregroundStyle(color)
            .accessibilityLabel(shown.title)
    }

    private var color: Color {
        if shown.isStale { return .yellow }
        if shown.showsLiveCue { return Palette.orange }
        if shown.state.status == .needsConfirmation { return Palette.onIslandAccent }
        return Palette.onIslandSecondary
    }
}

private struct ElapsedTime: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
    }
}

private struct Controls: View {
    let shown: Shown
    let onIsland: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Mute needs the conversation's process; a stale island has none to talk to.
            if !shown.isStale {
                muteButton
            }
            Button(intent: EndDoddyConversationIntent()) {
                Label(shown.isStale ? "Dismiss" : "End", systemImage: shown.isStale ? "xmark" : "phone.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(onIsland ? .red : Palette.error)
        }
        .font(.callout.weight(.semibold))
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
                .tint(onIsland ? .white : Palette.ink)
                .foregroundStyle(onIsland ? .black : Palette.card)
        } else {
            button
                .buttonStyle(.bordered)
                .tint(onIsland ? .white : Palette.ink)
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
                    Text(shown.state.isEnded ? shown.title : "Talking to Doddy")
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
                Controls(shown: shown, onIsland: false)
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
