import DoddyCore
import SwiftUI

// Motion v2, MV2 (docs/design/MOTION_V2_PLAN.md section 1 and 4): the views that make the app's
// edges into surfaces Doddy can stand on. A surface reports its window frame to the director and
// carries a slot on its top edge where he is drawn while he stands on it (option B: the system
// moves him with the surface, scroll, keyboard and page push included). MV2 registers them; he
// doesn't move yet, so the slot draws nothing except the UI tests' marker.

extension MotionRect {
    init(_ rect: CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }
}

extension View {
    /// This view's top edge is a surface Doddy can stand on. Only while the motion world is on
    /// (and `enabled`: the note page has no spot at accessibility text sizes).
    func motionSurface(_ id: MotionSurfaceID, enabled: Bool = true) -> some View {
        modifier(MotionSurfaceModifier(id: id, enabled: enabled))
    }

    /// Reports this view's frame by name: something his clear zone keeps away from (Ask's Send,
    /// the undo bar's Undo) or something he aims at (a tab, for the rail spot under it).
    func motionMark(_ name: String) -> some View {
        modifier(MotionMarkModifier(name: name))
    }

    /// A sheet or cover presented from this view is up while `isUp`: Doddy is hidden in the
    /// frame it starts and comes back where he stood when it has gone (MV3).
    func coversDoddy(_ isUp: Bool) -> some View {
        modifier(DoddyCoverModifier(isUp: isUp))
    }
}

private struct DoddyCoverModifier: ViewModifier {
    let isUp: Bool
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: isUp, initial: true) { _, up in DoddyDirector.shared.cover(token, isUp: up) }
            .onDisappear { DoddyDirector.shared.cover(token, isUp: false) }
            .onAppear { if isUp { DoddyDirector.shared.cover(token, isUp: true) } }
    }
}

private struct MotionSurfaceModifier: ViewModifier {
    let id: MotionSurfaceID
    var enabled = true
    private var director: DoddyDirector { .shared }

    func body(content: Content) -> some View {
        if director.isActive && enabled {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [id] frame in
                    MainActor.assumeIsolated { DoddyDirector.shared.surfaceMoved(id, to: MotionRect(frame)) }
                }
                .onAppear { director.surfaceAppeared(id) }
                .onDisappear { director.surfaceGone(id) }
                // A list card can be given another rule number when the list reorders.
                .onChange(of: id) { old, new in
                    director.surfaceGone(old)
                    director.surfaceAppeared(new)
                }
                .overlay(alignment: .top) { DoddySlot(id: id) }
        } else {
            content
        }
    }
}

private struct MotionMarkModifier: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        if DoddyDirector.shared.isActive {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [name] frame in
                MainActor.assumeIsolated { DoddyDirector.shared.markMoved(name, to: MotionRect(frame)) }
            }
        } else {
            content
        }
    }
}

/// Where Doddy is drawn on a surface's top edge: while the director places him on this surface
/// (MV3), he is drawn here, inside the surface's own view, so a scroll, the keyboard or a page
/// push moves or covers him in the same frame. With `-doddyArtMarkers YES` (UI tests, ADR-336)
/// the edge is also an accessibility element named `doddy.surface.<surface>`, so a test can check
/// that the surface is there and where. Never hit-testable, never read by VoiceOver in normal use.
struct DoddySlot: View {
    let id: MotionSurfaceID

    var body: some View {
        ZStack(alignment: .top) {
            if DoddyArtMarkers.isOn {
                Rectangle()
                    .fill(Color.white.opacity(0.01))
                    .frame(height: 2)
                    .accessibilityElement()
                    .accessibilityLabel(Self.marker(id))
                    .accessibilityIdentifier(Self.marker(id))
            }
            if DoddyDirector.shared.placement == .slot(id) {
                DoddySlotFigure(id: id)
            }
        }
        .allowsHitTesting(false)
    }

    /// `doddy.surface.stage`, `doddy.surface.rule.0`, `doddy.surface.ledge.settings`.
    static func marker(_ id: MotionSurfaceID) -> String {
        "doddy.surface." + id.description.replacingOccurrences(of: ":", with: ".")
    }
}

/// Home's stage (brief: "a short stage line", 140 pt): where Doddy stands, at 1.4×, under the
/// greeting. The separator colour, like every other hairline (no token change).
struct StageLine: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: CGFloat(MotionLayout.stageLineWidth), height: 1)
            .accessibilityHidden(true)
            .motionSurface(.stage)
    }
}

/// A short line in the separator colour under a still spot of his (the empty Memories screen).
struct LedgeLine: View {
    let name: String
    var width: CGFloat = 96

    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: width, height: 1)
            .accessibilityHidden(true)
            .motionSurface(.ledge(name))
    }
}
