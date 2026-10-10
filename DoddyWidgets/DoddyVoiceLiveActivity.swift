import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island and Lock Screen for a running conversation: Doddy, what he is doing right now
/// (from real SDK events), whether he is live, how long you have been talking, and Mute / End.
/// Tapping it opens the app (e.g. to Save or Don't save a proposed note).
/// When the app has not refreshed the activity for `VoiceLiveActivity.staleAfter` (iOS ended
/// it in the background), iOS marks it stale and this view says so instead of "Listening".
///
/// The Lock Screen card follows the phone's light/dark setting (paper card in light, Night card
/// in dark, colours from this target's asset catalog), with the approved pose art (`DoddyArt`).
/// The Dynamic Island is always black and follows the owner's "Lean In" board (`DoddyIslandMark`).
/// No words from the conversation appear here: the Lock Screen is visible to anyone.
struct DoddyVoiceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoddyVoiceAttributes.self) { context in
            LockScreenView(shown: Shown(context), startedAt: context.attributes.startedAt)
                .activityBackgroundTint(Palette.card)
                .activitySystemActionForegroundColor(Palette.ink)
        } dynamicIsland: { context in
            let shown = Shown(context)
            // Layout, sizes and colours from the owner's "Lean In" board (Doddy-Dynamic-Island-v4,
            // board 01, ADR-210): label and time beside the camera, then Doddy with his hand at
            // his ear, what he is doing, the buttons and the voice sign.
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandLabel(shown: shown)
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedTime(startedAt: context.attributes.startedAt)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Lean.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64, alignment: .trailing)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 12) {
                        DoddyIslandMark(expression: shown.expression, cue: shown.cue(full: true), faceSize: 36)
                            .frame(width: 70, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shown.title)
                                    .font(.system(size: 21, weight: .medium))
                                    .foregroundStyle(Lean.cream)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text(shown.islandLine)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(shown.isStale ? Color.yellow : Lean.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .accessibilityElement(children: .combine)
                            HStack(spacing: 8) {
                                Controls(shown: shown, onIsland: true)
                                StateSign(shown: shown, size: .expanded)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                DoddyIslandMark(expression: shown.expression, cue: shown.cue(full: false), faceSize: 22)
            } compactTrailing: {
                StateSign(shown: shown, size: .compact)
            } minimal: {
                HStack(spacing: 2) {
                    DoddyIslandMark(expression: shown.expression, cue: .faceOnly, faceSize: 21)
                    if shown.showsLiveCue || shown.state.status == .thinking {
                        StateSign(shown: shown, size: .minimal)
                    }
                }
            }
            .keylineTint(shown.showsLiveCue ? Lean.orange : Lean.secondary)
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

    /// Doddy's face on the island: one of the Lean In pack's own expressions per real state.
    var expression: DoddyIslandMark.Expression {
        if isStale { return .calm }
        if state.isEnded { return state.savedCount > 0 ? .proud : .calm }
        if state.showsMuted { return .calm }
        switch state.status {
        case .listening: return .listening
        case .speaking: return .speaking
        // Brow up: working something out, or waiting for you in the app.
        case .thinking, .needsConfirmation: return .thinking
        default: return .calm
        }
    }

    /// The hand at his ear while the conversation runs and he can hear you; the orange arc only
    /// in the expanded view (the compact board has the hand alone). Not while connecting.
    func cue(full: Bool) -> DoddyIslandMark.Cue {
        guard showsLiveCue, state.status != .connecting else { return .faceOnly }
        return full ? .handAndArc : .hand
    }

    /// Second line in the expanded island. Never words from the conversation.
    var islandLine: String {
        if isStale { return "The app stopped in the background" }
        if let detail { return detail }
        switch state.status {
        case .connecting: return "Getting ready"
        case .listening: return "Talk it through"
        case .thinking: return "One moment"
        case .speaking: return "One step at a time"
        default: return "Doddy"
        }
    }
}

/// "VOICE" beside the camera, as on the board, plus "LIVE" in orange while Doddy can hear you.
private struct IslandLabel: View {
    let shown: Shown

    var body: some View {
        HStack(spacing: 5) {
            Text("VOICE")
                .foregroundStyle(Lean.secondary)
            if shown.showsLiveCue, shown.state.status != .connecting {
                HStack(spacing: 3) {
                    Circle().fill(Lean.orange).frame(width: 5, height: 5)
                    Text("LIVE").foregroundStyle(Lean.orange)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live, Doddy can hear you")
            }
        }
        .font(.system(size: 9.5, weight: .semibold))
        .tracking(1.1)
    }
}

/// The board's trailing sign: voice bars while listening or speaking, dots while thinking or
/// connecting, otherwise the status symbol (mic-slash, tap, warning).
private struct StateSign: View {
    let shown: Shown
    let size: LeanVoiceBars.Size

    var body: some View {
        if !shown.isStale, !shown.state.showsMuted,
           shown.state.status == .listening || shown.state.status == .speaking {
            LeanVoiceBars(size: size)
        } else if !shown.isStale, !shown.state.showsMuted,
                  shown.state.status == .thinking || shown.state.status == .connecting {
            LeanThinkingDots(orangeCentre: shown.state.status == .thinking, scale: size == .minimal ? 0.8 : 1)
        } else if size != .minimal {
            StatusGlyph(shown: shown)
                .font(size == .expanded ? .body : .caption)
        }
    }
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

/// The island's status symbol when there is no voice or thinking sign to show.
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
        if onIsland {
            islandButtons
        } else {
            lockScreenButtons
        }
    }

    /// The board's 34 pt pills: dark fill, cream label. Stop ends the conversation.
    private var islandButtons: some View {
        HStack(spacing: 6) {
            if !shown.isStale {
                Button(intent: ToggleDoddyMuteIntent()) {
                    pillLabel(shown.state.isMuted ? "Unmute" : "Mute",
                              systemImage: shown.state.isMuted ? "mic.fill" : "mic.slash.fill",
                              prominent: shown.state.isMuted)
                }
                .buttonStyle(.plain)
            }
            Button(intent: EndDoddyConversationIntent()) {
                pillLabel(shown.isStale ? "Dismiss" : "Stop",
                          systemImage: shown.isStale ? "xmark" : "stop.fill",
                          prominent: false)
            }
            .buttonStyle(.plain)
        }
    }

    /// While muted, Unmute is the cream pill so getting Doddy back is one obvious tap.
    private func pillLabel(_ title: String, systemImage: String, prominent: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(PillLabelStyle())
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Lean.black : Lean.cream)
            .padding(.horizontal, 15)
            .frame(height: 34)
            .background(prominent ? Lean.cream : Lean.pill, in: Capsule())
            .contentShape(Capsule())
    }

    private var lockScreenButtons: some View {
        HStack(spacing: 10) {
            // Mute needs the conversation's process; a stale activity has none to talk to.
            if !shown.isStale {
                muteButton
            }
            Button(intent: EndDoddyConversationIntent()) {
                Label(shown.isStale ? "Dismiss" : "End", systemImage: shown.isStale ? "xmark" : "phone.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Palette.error)
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
                .tint(Palette.ink)
                .foregroundStyle(Palette.card)
        } else {
            button
                .buttonStyle(.bordered)
                .tint(Palette.ink)
        }
    }
}

/// Icon then title, 12 pt apart, as the board's Stop pill.
private struct PillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
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
