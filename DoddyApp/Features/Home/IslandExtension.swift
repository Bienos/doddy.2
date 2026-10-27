import DoddyCore
import SwiftUI
import UIKit

/// While Doddy talks on Home (owner, 22 Oct 2026, ADR-596; redrawn 27 Oct, ADR-654): iOS doesn't
/// show Doddy's own island while Doddy is on screen, so Home draws a black shape that hangs from
/// the top of the screen under the camera and grows on both sides, with his voice drawn in it as
/// a dense aurora of orange lines (mock-up "G1 Gęsta"). While he hears you it is narrow, with a
/// calm line; while he talks it springs out to the sides, pulses in his rhythm and glows; while
/// he is muted it is narrow and grey and still. On iPhones without a notch or island (a top
/// inset under 44 pt) it isn't drawn: it would hang from nothing.
///
/// The rhythm is made up from a clock (`SpeechPulse`), not read from his voice: the app has no
/// loudness for it. Under Reduce Motion nothing moves. Apple's guidance asks apps not to add
/// elements that draw attention to the Dynamic Island; this is the owner's choice (ADR-654).
struct IslandExtension: View {
    enum Look: Equatable {
        case listening, speaking, quiet
    }

    /// The shape's width in points while he hears you and while he talks. While he talks it is
    /// wider than the gap in the status bar, so Home hides the status bar for the conversation
    /// (`HomeView.hidesStatusBar`). For a width that keeps the clock and battery, make
    /// `speakingWidth` 190 and take `.statusBarHidden` off Home.
    private static let listeningWidth: CGFloat = 176
    private static let speakingWidth: CGFloat = 330

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
        if top >= 44 {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let frame = Frame(look: look, motion: motion, date: timeline.date, reduceMotion: reduceMotion)
                Canvas { context, size in
                    Self.draw(&context, size: size, top: top, frame: frame)
                }
                // Wider than the widest shape, and tall enough for its glow.
                .frame(width: 420, height: top + 130)
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
            case .speaking: level = reduceMotion ? 0.4 : SpeechPulse.level(at: sinceChange)
            case .listening: level = reduceMotion ? 0.16 : 0.16 + 0.05 * sin(date.timeIntervalSinceReferenceDate * 2)
            case .quiet: level = 0.06
            }
        }
    }

    private static let orange = (r: 236.0, g: 128.0, b: 63.0)
    private static let amber = (r: 255.0, g: 176.0, b: 102.0)
    private static let rose = (r: 229.0, g: 82.0, b: 107.0)

    private static func draw(_ context: inout GraphicsContext, size: CGSize, top: CGFloat, frame f: Frame) {
        let p = CGFloat(f.widening)
        let width = listeningWidth + (speakingWidth - listeningWidth) * p
        let level = CGFloat(f.level)
        // Below the camera: 30 pt of black while he listens, 56 while he talks, and a little more
        // on each burst.
        let below = 30 + 26 * p + (f.look == .speaking ? 6 * level : 0)
        let rect = CGRect(x: (size.width - width) / 2, y: 0, width: width, height: top + below)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous)
            .path(in: rect)
        let glow = Color(red: orange.r / 255, green: orange.g / 255, blue: orange.b / 255)

        // The black shape and its glow.
        context.drawLayer { layer in
            if f.look != .quiet {
                layer.addFilter(.shadow(color: glow.opacity(0.18 + 0.5 * f.level), radius: 8 + 26 * level, x: 0, y: 0))
            }
            layer.fill(shape, with: .color(.black))
        }

        // His voice: a dense row of thin orange columns, brightest in the middle, added together.
        let bandTop: CGFloat = 50   // just under the camera
        let bandBottom = rect.maxY - 8
        let bandHeight = max(0, bandBottom - bandTop)
        let centreY = (bandTop + bandBottom) / 2
        let bandWidth = max(0, width - 40)
        let columns = max(24, Int(bandWidth / 3.6))
        let columnWidth: CGFloat = 2.6
        context.drawLayer { layer in
            layer.clip(to: shape)
            layer.blendMode = .plusLighter
            if f.look != .quiet {
                layer.addFilter(.shadow(color: glow.opacity(0.55), radius: 4, x: 0, y: 0))
            }
            for i in 0..<columns {
                let u = Double(i) / Double(columns - 1)
                let noise = 0.5 + 0.25 * sin(u * 49 + f.time * 3.1) + 0.25 * sin(u * 116 - f.time * 4.3)
                let window = pow(sin(Double.pi * u), 1.1)
                let height = bandHeight * CGFloat((0.12 + 0.88 * f.level) * window * noise)
                guard height > 0.5 else { continue }
                let x = rect.minX + 20 + CGFloat(u) * bandWidth
                let column = CGRect(x: x - columnWidth / 2, y: centreY - height / 2, width: columnWidth, height: height)
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
