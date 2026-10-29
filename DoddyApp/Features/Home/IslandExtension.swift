import DoddyCore
import SwiftUI
import UIKit

/// While Doddy talks on Home (owner, 22 Oct 2026, ADR-596; redrawn 27 Oct, ADR-654; a thin strip
/// since 29 Oct, ADR-665): iOS doesn't show Doddy's own island while Doddy is on screen, so Home
/// draws a black strip over the Dynamic Island, the island's own height, that grows out to both
/// sides, with his voice drawn in it as a dense aurora of orange lines (mock-up "G1 Gęsta") on
/// each side of the camera. While he hears you it is 260 pt wide with a clear, calm line and a
/// faint glow; while he talks it springs out to 330 pt, pulses in his rhythm and glows; while he
/// is muted it is 260 pt, grey and still. It hangs nothing below the island (ADR-665: the 56 pt
/// block of ADR-654 was not what the owner meant). Drawn only on iPhones with a Dynamic Island
/// (a top inset of 55 pt or more): a notch can't grow to the sides.
///
/// The pulse follows how loud his voice really is (`AgentVoiceMeter`, ADR-655, from the audio he
/// plays); where there is no such audio track it falls back to a rhythm made up from a clock
/// (`SpeechPulse`). Under Reduce Motion nothing moves. Apple's guidance asks apps not to add
/// elements that draw attention to the Dynamic Island; this is the owner's choice (ADR-654).
struct IslandExtension: View {
    enum Look: Equatable {
        case listening, speaking, quiet
    }

    /// The strip's width in points while he hears you and while he talks. Both are wider than the
    /// gap in the status bar, so Home hides the status bar for the conversation
    /// (`.statusBarHidden` on Home). For a strip that keeps the clock and battery, make both 190
    /// and take `.statusBarHidden` off Home: the lines then have little room beside the camera.
    private static let listeningWidth: CGFloat = 260
    private static let speakingWidth: CGFloat = 330
    /// The Dynamic Island's own height. Its top is 48 pt above the bottom of the top inset
    /// (11 pt from the top of the screen at a 59 pt inset, 14 at 62).
    private static let stripHeight: CGFloat = 37
    private static let islandTopAboveInset: CGFloat = 48
    /// The island's camera and sensors in the middle of the strip: nothing drawn there would show.
    private static let cameraWidth: CGFloat = 126

    let look: Look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = Motion(from: 0, to: 0, since: .distantPast)

    /// The widening, as a spring from where it was to where it goes (0 narrow, 1 wide).
    private struct Motion {
        var from: Double
        var to: Double
        var since: Date
    }

    private static var topInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        let top = Self.topInset
        if top >= 55 {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let frame = Frame(look: look, motion: motion, date: timeline.date, reduceMotion: reduceMotion)
                Canvas { context, size in
                    Self.draw(&context, size: size, stripTop: top - Self.islandTopAboveInset, frame: frame)
                }
                // Wider than the widest strip, and tall enough for its glow.
                .frame(width: 420, height: top + 40)
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: look, initial: true) { _, newLook in retarget(to: newLook) }
        }
    }

    private func retarget(to newLook: Look) {
        let now = Date()
        let current = reduceMotion
            ? motion.to
            : IslandSpring.value(from: motion.from, to: motion.to, elapsed: now.timeIntervalSince(motion.since))
        motion = Motion(from: current, to: newLook == .speaking ? 1 : 0, since: now)
    }

    // MARK: One frame

    /// What a frame needs, worked out from the clock before drawing.
    private struct Frame {
        let look: Look
        /// How wide: 0 narrow, 1 wide (a little past 1 for a moment while it pops).
        let widening: Double
        /// How strongly the voice is drawn, 0 to 1.
        let level: Double
        /// For the lines' drift. Zero under Reduce Motion, so they stand still.
        let time: Double

        init(look: Look, motion: Motion, date: Date, reduceMotion: Bool) {
            self.look = look
            let sinceChange = date.timeIntervalSince(motion.since)
            let raw = reduceMotion ? motion.to : IslandSpring.value(from: motion.from, to: motion.to, elapsed: sinceChange)
            widening = min(1.25, max(-0.1, raw))
            time = reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
            switch look {
            case .speaking:
                if reduceMotion {
                    level = 0.4
                } else if AgentVoiceMeter.shared.hasSource {
                    // His real voice (ADR-655): the loudness of the audio he is playing.
                    level = min(1, max(0.08, AgentVoiceMeter.shared.current() * 1.1))
                } else {
                    // No audio track to listen to (another voice provider, or before it exists).
                    level = SpeechPulse.level(at: sinceChange)
                }
            // Clear enough to see at a glance that he is listening (owner, 29 Oct, ADR-665).
            case .listening: level = reduceMotion ? 0.5 : 0.5 + 0.06 * sin(date.timeIntervalSinceReferenceDate * 2)
            case .quiet: level = 0.06
            }
        }
    }

    private static let orange = (r: 236.0, g: 128.0, b: 63.0)
    private static let amber = (r: 255.0, g: 176.0, b: 102.0)
    private static let rose = (r: 229.0, g: 82.0, b: 107.0)

    private static func draw(_ context: inout GraphicsContext, size: CGSize, stripTop: CGFloat, frame f: Frame) {
        let p = CGFloat(f.widening)
        let level = CGFloat(f.level)
        // A little wider on each burst while he talks.
        let width = listeningWidth + (speakingWidth - listeningWidth) * p + (f.look == .speaking ? 8 * level : 0)
        let rect = CGRect(x: (size.width - width) / 2, y: stripTop, width: width, height: stripHeight)
        let shape = Capsule(style: .continuous).path(in: rect)
        let glow = Color(red: orange.r / 255, green: orange.g / 255, blue: orange.b / 255)

        // The black strip and its glow.
        context.drawLayer { layer in
            if f.look != .quiet {
                layer.addFilter(.shadow(color: glow.opacity(0.18 + 0.5 * f.level), radius: 6 + 18 * level, x: 0, y: 0))
            }
            layer.fill(shape, with: .color(.black))
        }

        // His voice: a dense row of thin orange columns on each side of the camera, strongest a
        // little way out from it and fading to nothing at the strip's ends.
        let inset: CGFloat = 12
        let cameraHalf = cameraWidth / 2 + 4
        let wing = width / 2 - inset - cameraHalf
        guard wing > 0 else { return }
        let bandHeight = stripHeight - 10
        let columns = Int((width - 2 * inset) / 3.6)
        let columnWidth: CGFloat = 2.6
        context.drawLayer { layer in
            layer.clip(to: shape)
            layer.blendMode = .plusLighter
            if f.look != .quiet {
                layer.addFilter(.shadow(color: glow.opacity(0.55), radius: 4, x: 0, y: 0))
            }
            for i in 0...columns {
                let x = rect.minX + inset + CGFloat(i) * 3.6
                let fromCamera = abs(x - rect.midX) - cameraHalf
                guard fromCamera >= 0 else { continue }
                let d = Double(min(1, fromCamera / wing))
                let envelope = pow(max(0, sin(Double.pi * (0.25 + 0.75 * d))), 1.1)
                let u = Double((x - rect.minX) / width)
                let noise = 0.5 + 0.25 * sin(u * 49 + f.time * 3.1) + 0.25 * sin(u * 116 - f.time * 4.3)
                let columnHeight = bandHeight * CGFloat((0.12 + 0.88 * f.level) * envelope * noise)
                guard columnHeight > 0.5 else { continue }
                let column = CGRect(x: x - columnWidth / 2, y: rect.midY - columnHeight / 2, width: columnWidth, height: columnHeight)
                let colour = f.look == .quiet ? Color(white: 0.62) : warm(u)
                layer.fill(
                    Path(column),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: colour.opacity(0), location: 0),
                            .init(color: colour.opacity(0.85), location: 0.5),
                            .init(color: colour.opacity(0), location: 1),
                        ]),
                        startPoint: CGPoint(x: x, y: column.minY),
                        endPoint: CGPoint(x: x, y: column.maxY)))
            }
        }
    }

    /// Orange at the left, amber in the middle, rose at the right.
    private static func warm(_ u: Double) -> Color {
        func mix(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double), _ amount: Double) -> Color {
            let k = min(1, max(0, amount))
            return Color(
                red: (a.r + (b.r - a.r) * k) / 255,
                green: (a.g + (b.g - a.g) * k) / 255,
                blue: (a.b + (b.b - a.b) * k) / 255)
        }
        return u < 0.5 ? mix(orange, amber, u * 1.2) : mix(amber, rose, (u - 0.5) * 1.4)
    }
}
