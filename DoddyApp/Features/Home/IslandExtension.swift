import SwiftUI
import UIKit

/// While Doddy talks on Home (ADR-596, reshaped by ADR-653): iOS doesn't show Doddy's own island
/// while Doddy is on screen, so Home draws one. Black around the camera, then a short strip under
/// the status bar that the island pushes out to both sides, almost to the edges of the screen, with
/// his orange waves across the whole of it (owner, 25 Oct 2026: "a small push to the sides with
/// waves across the whole thing", replacing ADR-596's tall black drop). The strip is a little
/// deeper while he talks than while he hears you; a still grey line while he connects or is muted.
/// On iPhones without a notch or island (a top inset under 44 pt) it isn't drawn: it would hang
/// from nothing.
///
/// The waves move with the clock only (`TimelineView`), not with sound: nothing here reads the
/// microphone. Under Reduce Motion they stand still and the strip doesn't spread out.
struct IslandExtension: View {
    enum Look: Equatable {
        case listening, speaking, quiet
    }

    let look: Look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 when it appears (a drop under the camera), 1 once it has pushed out to both sides.
    @State private var spread: CGFloat = 0

    /// How far the strip reaches below the status bar.
    static func depth(_ look: Look) -> CGFloat { look == .speaking ? 28 : 22 }
    /// What Home leaves above its header while he talks: the deepest strip and a little air.
    static let headerClearance: CGFloat = 38

    private static var topInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        let top = Self.topInset
        if top >= 44 {
            let depth = Self.depth(look)
            GeometryReader { geometry in
                let width = geometry.size.width
                let half = IslandStripShape.halfWidth(width, spread: spread)
                ZStack(alignment: .topLeading) {
                    IslandStripShape(top: top, depth: depth, spread: spread)
                        .fill(Color.black)
                    waves
                        // Inside the rounded ends, with room above and below the lines.
                        .frame(width: max(0, 2 * half - depth), height: max(0, depth - 6))
                        .position(x: width / 2, y: top + depth / 2)
                }
            }
            .frame(height: top + depth)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: look)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                if reduceMotion {
                    spread = 1
                } else {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { spread = 1 }
                }
            }
        }
    }

    @ViewBuilder
    private var waves: some View {
        let live = look != .quiet
        if reduceMotion || !live {
            IslandWavesView(kind: .across, live: live)
        } else {
            // One trip of the waves every 1.2 s (Figma "Jak ruszają się fale"). Capped at 30
            // frames a second like Doddy's breathing (ADR-604).
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let seconds = context.date.timeIntervalSinceReferenceDate
                IslandWavesView(kind: .across, phase: -seconds * 2 * .pi / 1.2, live: live)
            }
        }
    }
}

/// The island pushed out to both sides (ADR-653): black from the top of the screen around the
/// camera (the neck, narrow enough to leave the clock and the battery uncovered), then a strip from
/// the bottom of the status bar, `depth` deep, rounded at both ends, joined to the neck by two
/// small inward curves. `spread` 0 is the neck alone with a rounded bottom; 1 is the whole strip.
struct IslandStripShape: Shape {
    /// The status bar's height: the strip starts under it.
    var top: CGFloat
    var depth: CGFloat
    var spread: CGFloat

    /// Around the camera (the island is about 126 pt wide), clear of the clock and the battery.
    static let neck: CGFloat = 150
    /// From each edge of the screen to the end of the strip.
    static let margin: CGFloat = 12
    /// The inward curve where the neck meets the strip.
    static let shoulder: CGFloat = 10

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(depth, spread) }
        set {
            depth = newValue.first
            spread = newValue.second
        }
    }

    /// Half the strip's width in a drawing `width` wide: half the neck at `spread` 0, reaching to
    /// `margin` from each edge at 1. Never narrower than the neck.
    static func halfWidth(_ width: CGFloat, spread: CGFloat) -> CGFloat {
        let neckHalf = min(neck, width) / 2
        let full = max(neckHalf, width / 2 - margin)
        return neckHalf + (full - neckHalf) * min(1, max(0, spread))
    }

    func path(in rect: CGRect) -> Path {
        let centre = rect.midX
        let neckHalf = min(Self.neck, rect.width) / 2
        let half = Self.halfWidth(rect.width, spread: spread)
        let radius = max(0, min(depth / 2, half))
        // The shoulders and the strip's upper corners grow only as the strip gets wider than the
        // neck, so the outline never folds back on itself while it spreads.
        let shoulder = min(Self.shoulder, max(0, half - neckHalf - radius))
        let upper = max(0, min(radius, half - neckHalf - shoulder))
        let strip = rect.minY + top
        let bottom = strip + depth
        let left = centre - half
        let right = centre + half

        var path = Path()
        path.move(to: CGPoint(x: centre - neckHalf, y: rect.minY))
        path.addLine(to: CGPoint(x: centre + neckHalf, y: rect.minY))
        path.addLine(to: CGPoint(x: centre + neckHalf, y: strip - shoulder))
        path.addQuadCurve(to: CGPoint(x: centre + neckHalf + shoulder, y: strip),
                          control: CGPoint(x: centre + neckHalf, y: strip))
        path.addArc(tangent1End: CGPoint(x: right, y: strip), tangent2End: CGPoint(x: right, y: bottom), radius: upper)
        path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: left, y: bottom), radius: radius)
        path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: strip), radius: radius)
        path.addArc(tangent1End: CGPoint(x: left, y: strip), tangent2End: CGPoint(x: centre, y: strip), radius: upper)
        path.addLine(to: CGPoint(x: centre - neckHalf - shoulder, y: strip))
        path.addQuadCurve(to: CGPoint(x: centre - neckHalf, y: strip - shoulder),
                          control: CGPoint(x: centre - neckHalf, y: strip))
        path.closeSubpath()
        return path
    }
}
