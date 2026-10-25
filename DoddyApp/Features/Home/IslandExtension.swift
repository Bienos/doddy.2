import SwiftUI
import UIKit

/// While Doddy talks on Home (ADR-596, redone by ADR-653): iOS doesn't show Doddy's own island
/// while Doddy is on screen, so Home draws the island's own footprint and moves it the way the
/// iPhone does for a call or a recording: the same black pill, the camera's height (37 pt, from
/// 11 pt below the top), pushed out to both sides with a spring, with his orange waves across the
/// whole of it. They pass behind the camera, so what you see is a wave on each side that is one
/// wave. It does not drop below the status bar and does not cover the clock or the battery.
///
/// While he speaks the waves move; while he hears you they are one still orange line; while he
/// connects, works or is muted a still grey one. On iPhones without an island (a top inset under
/// 51 pt) it isn't drawn: it would hang from nothing. Apple's guidance is to add nothing to an app
/// that draws attention to the Dynamic Island; this is the owner's decision (25 Oct 2026), kept
/// decorative: no hit testing, hidden from VoiceOver.
///
/// The waves move with the clock only (`TimelineView`), not with sound: nothing here reads the
/// microphone. Under Reduce Motion they stand still and the pill doesn't spring.
struct IslandExtension: View {
    enum Look: Equatable {
        case listening, speaking, quiet
    }

    let look: Look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 when it appears (the island as it is), 1 once it has pushed out to both sides.
    @State private var spread: CGFloat = 0

    private static var topInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        if Self.topInset >= IslandPillGeometry.minimumTopInset {
            GeometryReader { geometry in
                let width = IslandPillGeometry.width(screen: geometry.size.width, spread: spread, speaking: look == .speaking)
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color.black)
                    waves
                        // Clear of the rounded ends; the middle is the camera, which is black too.
                        .padding(.horizontal, IslandPillGeometry.height / 2)
                        .padding(.vertical, 6)
                }
                .frame(width: width, height: IslandPillGeometry.height)
                .position(x: geometry.size.width / 2, y: IslandPillGeometry.top + IslandPillGeometry.height / 2)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: width)
            }
            .frame(height: IslandPillGeometry.top + IslandPillGeometry.height)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { spread = 1 }
        }
    }

    @ViewBuilder
    private var waves: some View {
        let live = look != .quiet
        if reduceMotion || look != .speaking {
            IslandWavesView(kind: .across, live: live)
        } else {
            // One trip of the waves every 1.2 s (Figma "Jak ruszają się fale"). Capped at 30
            // frames a second like Doddy's breathing (ADR-604).
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let seconds = context.date.timeIntervalSinceReferenceDate
                IslandWavesView(kind: .across, phase: -seconds * 2 * .pi / 1.2, live: true)
            }
        }
    }
}

/// The island's footprint, in points, as iPhones with a Dynamic Island draw it. The width is the
/// compact island's: about 230 pt on a 393 pt screen, with the clock and the battery clear on both
/// sides, and a little wider while he speaks.
enum IslandPillGeometry {
    /// From the top of the screen to the island (iPhone 15 Pro: 11 pt).
    static let top: CGFloat = 11
    static let height: CGFloat = 37
    /// The camera's own width (iPhone 15 Pro: about 126 pt): the pill never gets narrower.
    static let camera: CGFloat = 126
    /// Smaller than this, a phone has a notch or no island, and nothing is drawn.
    static let minimumTopInset: CGFloat = 51
    /// Each side of the pill, as a share of the screen's width, while he hears you and while he
    /// speaks. The clock and the battery sit in the rest.
    static let listeningShare: CGFloat = 0.585
    static let speakingShare: CGFloat = 0.62

    /// The pill's width: the camera's at `spread` 0, its full width at 1.
    static func width(screen: CGFloat, spread: CGFloat, speaking: Bool) -> CGFloat {
        let full = max(camera, screen * (speaking ? speakingShare : listeningShare))
        return camera + (full - camera) * min(1, max(0, spread))
    }
}
