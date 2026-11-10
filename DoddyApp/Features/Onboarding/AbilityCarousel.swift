import DoddyCore
import SwiftUI

/// What I can do, as scenes (owner, 9 Nov 2026: "show what he does more creatively"; decision
/// 2026-11-09-what-i-can-do-scenes). One scene per feature this build lists: Doddy in a pose from the
/// owner's pack, something you could say to him, what it does and its honest status. The scenes move on
/// by themselves until the person swipes; with Reduce Motion they stay put and nothing bobs.
/// The art is decorative; each scene reads as one sentence to VoiceOver.
struct AbilityCarousel: View {
    let rows: [AbilityRow]
    let language: NotificationLanguage

    @State private var selection: DoddyAbility?
    /// The scene the timer moved to, so a swipe can be told from the timer.
    @State private var autoTarget: DoddyAbility?
    /// Once the person swipes, the scenes stop moving by themselves.
    @State private var personTookOver = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize

    private static let secondsPerScene: Double = 4.5

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $selection) {
                ForEach(rows) { row in
                    AbilityScene(row: row, language: language, isCurrent: selection == row.ability)
                        .padding(.horizontal, 2)
                        .tag(Optional(row.ability))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: textSize.isAccessibilitySize ? 520 : 400)
            dots
        }
        .onAppear {
            guard selection == nil else { return }
            // Set as if by the timer, so the first scene doesn't count as a swipe.
            autoTarget = rows.first?.ability
            selection = autoTarget
        }
        .onChange(of: selection) { _, new in
            if new != autoTarget { personTookOver = true }
        }
        .task(id: personTookOver) {
            guard !reduceMotion, !personTookOver, rows.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.secondsPerScene))
                if Task.isCancelled || personTookOver { return }
                let index = rows.firstIndex { $0.ability == selection } ?? 0
                let next = rows[(index + 1) % rows.count].ability
                autoTarget = next
                withAnimation(.easeInOut(duration: 0.6)) { selection = next }
            }
        }
        .accessibilityIdentifier("capabilities.carousel")
    }

    /// One dot per scene; the current one is a short orange bar. Tapping a dot goes to that scene.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(rows) { row in
                let current = row.ability == selection
                Capsule()
                    .fill(current ? Theme.orangeCue : Theme.separator)
                    .frame(width: current ? 18 : 7, height: 7)
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: selection)
                    .onTapGesture {
                        personTookOver = true
                        withAnimation { selection = row.ability }
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

/// One feature's scene.
private struct AbilityScene: View {
    let row: AbilityRow
    let language: NotificationLanguage
    let isCurrent: Bool

    /// Goes up each time the scene comes to the front: the bubble pops, Doddy hops, the sign bounces.
    @State private var bounce = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    private var look: AbilityLook { AbilityLook(row.ability) }

    /// The example in the reader's quotation marks.
    private var quoted: String {
        let example = WhatICanDo.example(row.ability, language)
        return language == .polish ? "„\(example)”" : "“\(example)”"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bubble
            stage
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text(row.does)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
                statusChip
            }
            .layoutPriority(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(row.title). \(row.does) \(WhatICanDo.exampleLead(row.ability, language)): \(quoted). \(row.statusText)"))
        .onAppear { if isCurrent { play() } }
        .onChange(of: isCurrent) { _, now in if now { play() } }
    }

    private func play() {
        if !reduceMotion { bounce += 1 }
    }

    // MARK: Parts

    /// What you could say: a speech bubble that pops in when the scene comes up.
    private var bubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: WhatICanDo.exampleLead(row.ability, language))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(verbatim: quoted)
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.canvas, in: BubbleShape())
        .overlay(BubbleShape().stroke(Theme.separator, lineWidth: 1))
        .keyframeAnimator(initialValue: 1.0, trigger: bounce) { content, scale in
            content.scaleEffect(scale, anchor: .bottomLeading)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.82, duration: 0.12)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            }
        }
    }

    /// Doddy and the feature's sign. With his pictures hidden, only the sign.
    private var stage: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 0)
            if hideCharacterArt {
                symbol(size: 54)
            } else {
                ZStack(alignment: .topTrailing) {
                    pose
                        .frame(minHeight: 70, maxHeight: 130)
                        .keyframeAnimator(initialValue: 0.0, trigger: bounce) { content, lift in
                            content.offset(y: -lift)
                        } keyframes: { _ in
                            KeyframeTrack {
                                CubicKeyframe(18, duration: 0.22)
                                SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                            }
                        }
                    symbol(size: 22)
                        .offset(x: 26, y: -6)
                }
                .doddyArtMarker("doddy.scene.\(row.ability.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 130)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var pose: some View {
        if row.ability == .talk, isCurrent, !reduceMotion {
            // Talking: the pack's mouth frames, about eight a second.
            TimelineView(.periodic(from: .now, by: 0.12)) { context in
                let frame = Int(context.date.timeIntervalSinceReferenceDate / 0.12) % 6 + 1
                Image(decorative: "VoiceDoddy_talking_\(frame)").resizable().scaledToFit()
            }
        } else {
            Image(decorative: look.pose).resizable().scaledToFit()
                .modifier(Bob(on: isCurrent && !reduceMotion))
        }
    }

    private func symbol(size: CGFloat) -> some View {
        Image(systemName: look.symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Theme.inkOnOrange)
            .padding(size * 0.45)
            .background(Theme.orangeCue, in: Circle())
            .symbolEffect(.bounce, value: bounce)
    }

    private var statusChip: some View {
        HStack(spacing: 5) {
            Image(systemName: row.status == .ready ? "checkmark.circle.fill" : "hammer.fill")
            Text(row.statusText).lineLimit(2)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(row.status == .ready ? Theme.confirmed : Theme.accentText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.canvas.opacity(0.9), in: Capsule())
    }

    private var background: some View {
        ZStack {
            Theme.quietSurface
            LinearGradient(colors: [look.tint.opacity(0.22), look.tint.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// Doddy floats gently while his scene is on screen.
private struct Bob: ViewModifier {
    let on: Bool
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: on && up ? -6 : 0)
            .rotationEffect(.degrees(on && up ? -2 : 1), anchor: .bottom)
            .animation(on ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default, value: up)
            .onAppear { up = on }
            .onChange(of: on) { _, now in up = now }
    }
}

/// A rounded bubble with a small tail at the bottom left, pointing down at Doddy.
private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        var path = Path(roundedRect: body, cornerRadius: 16, style: .continuous)
        let tailX = rect.minX + 28
        path.move(to: CGPoint(x: tailX, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: tailX + 4, y: rect.maxY + 9))
        path.addLine(to: CGPoint(x: tailX + 14, y: rect.maxY - 1))
        path.closeSubpath()
        return path
    }
}

/// Each feature's pose (only the owner's pack, `WholeDoddy_*` and the talking frames), sign and tint.
private struct AbilityLook {
    let pose: String
    let symbol: String
    let tint: Color

    init(_ ability: DoddyAbility) {
        let look = Self.look(ability)
        pose = look.pose
        symbol = look.symbol
        tint = look.tint
    }

    private static func look(_ ability: DoddyAbility) -> (pose: String, symbol: String, tint: Color) {
        switch ability {
        case .talk: ("VoiceDoddy_talking_1", "waveform", .orange)
        case .notes: ("WholeDoddy_belly_reading", "note.text", .yellow)
        case .lists: ("WholeDoddy_reaching_high", "checklist", .green)
        case .reminders: ("WholeDoddy_tiptoe", "bell.fill", .pink)
        case .messages: ("WholeDoddy_crosslegged", "text.bubble.fill", .blue)
        case .phoneCalls: ("WholeDoddy_listening", "phone.fill", .teal)
        case .callsForYou: ("WholeDoddy_fistpump", "phone.arrow.up.right.fill", .indigo)
        case .tasks: ("WholeDoddy_basketball_dribble", "briefcase.fill", .purple)
        case .leaflets: ("WholeDoddy_kneeling_inspect", "tag.fill", .mint)
        case .translator: ("WholeDoddy_wave", "character.bubble.fill", .cyan)
        }
    }
}
