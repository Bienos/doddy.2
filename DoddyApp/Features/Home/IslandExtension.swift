import SwiftUI
import UIKit

/// While Doddy talks on Home (owner, 22 Oct 2026, ADR-596): iOS doesn't show Doddy's own island
/// while Doddy is on screen, so Home draws a black shape that grows down from the top of the
/// screen, under the camera, with his orange waves moving in it. A line of waves while he hears
/// you, the whole shape in waves and a little wider while he talks, a still grey line while he
/// is muted. On iPhones without a notch or island (a top inset under 44 pt) it isn't drawn: it
/// would hang from nothing.
///
/// The waves move with the clock only (`TimelineView`), not with sound: nothing here reads the
/// microphone. Under Reduce Motion they stand still.
struct IslandExtension: View {
    enum Look: Equatable {
        case listening, speaking, quiet
    }

    let look: Look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var topInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        let top = Self.topInset
        if top >= 44 {
            let wide = look == .speaking
            let width: CGFloat = wide ? 260 : 210
            let below: CGFloat = wide ? 44 : 32
            UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous)
                .fill(Color.black)
                .overlay(alignment: .bottom) {
                    waves
                        .frame(height: wide ? below + 10 : 18)
                        .padding(.horizontal, wide ? 10 : 34)
                        .padding(.bottom, wide ? 0 : 8)
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous))
                }
                .frame(width: width, height: top + below)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: look)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var waves: some View {
        let kind: IslandWavesView.Kind = look == .speaking ? .full : .line
        let live = look != .quiet
        if reduceMotion || !live {
            IslandWavesView(kind: kind, live: live)
        } else {
            // One trip of the waves every 1.2 s (Figma "Jak ruszają się fale"). Capped at 30
            // frames a second like Doddy's breathing (ADR-604): uncapped, the nine lines were
            // redrawn at 120 Hz next to his own 120 Hz display link.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let seconds = context.date.timeIntervalSinceReferenceDate
                IslandWavesView(kind: kind, phase: -seconds * 2 * .pi / 1.2, live: live)
            }
        }
    }
}
