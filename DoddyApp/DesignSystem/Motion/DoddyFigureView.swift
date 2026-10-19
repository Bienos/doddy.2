import DoddyCore
import SwiftUI

// Motion v2, MV3: drawing the one persistent Doddy. One view (`DoddyFigureView`) draws him
// wherever the director places him: inside the surface he stands on (`DoddySlotFigure`, so the
// system moves him with it) or in the root overlay (`DoddyOverlay`, flights and fades). Only the
// owner's pack pictures, as whole pictures (Q7): moved, scaled, squashed, tilted, mirrored.

/// Sizes of the pack pictures for him.
enum DoddyFigureMetrics {
    /// The full 2:3 picture's height at 1.0×: the standing frame (`DoddyMotion_idle_1`) has its
    /// figure over 72 % of the picture's height, so 96 pt of Doddy (the brief) is 133.3 pt of picture.
    static let pictureHeight = MotionLayout.height / 0.72

    /// The image set and where his soles are in it (a fraction of its height from the top): the
    /// strips share one ground (564/600); each pose has its own (its figure box's bottom).
    static func picture(_ p: MotionArt.Picture) -> (asset: String, ground: Double) {
        switch p {
        case .strip(let name, let frame):
            let strip = DoddyMotion(rawValue: name) ?? .idle
            let n = strip.frames.contains(frame) ? frame : strip.stillFrame
            return (strip.assetName(n), strip.figure.y + strip.figure.height)
        case .pose(let name):
            let pose = IslandPose(rawValue: name) ?? .crosslegged
            return (pose.assetName, pose.figure.y + pose.figure.height)
        }
    }
}

/// Doddy as one pack picture, laid out so its bottom edge is his soles (the picture's transparent
/// margin below the ground hangs below it). Never hit-testable; hidden from VoiceOver, except as
/// a marker for UI tests (`-doddyArtMarkers YES`: `doddy.motion.idle`, `doddy.pose.crosslegged`).
struct DoddyFigureView: View {
    let figure: DoddyFigure
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let picture = DoddyFigureMetrics.picture(figure.art.picture)
        let height = CGFloat(DoddyFigureMetrics.pictureHeight * figure.scale)
        let width = height / 1.5
        let ground = CGFloat(picture.ground)
        let soles = UnitPoint(x: 0.5, y: ground)
        let art = figure.art
        let drawn = Image(picture.asset)
            .resizable()
            .frame(width: width, height: height)
            .scaleEffect(x: CGFloat((art.mirrored ? -1 : 1) * art.scaleX), y: CGFloat(art.scaleY), anchor: soles)
            .rotationEffect(.degrees(art.tilt), anchor: soles)
            // In dark appearance the black outline gets the island's thin cream edge (plan section 2).
            .islandCreamEdge(colorScheme == .dark)
            .frame(width: width, height: height * ground, alignment: .top)
            .opacity(figure.opacity)
            .allowsHitTesting(false)
            .onAppear { DoddyDirector.shared.drawingAppeared() }
            .onDisappear { DoddyDirector.shared.drawingGone() }
        if DoddyArtMarkers.isOn {
            drawn.doddyArtMarker(art.marker)
        } else {
            drawn.accessibilityHidden(true)
        }
    }
}

/// Him in a surface's slot: soles on the surface's top edge, at his spot along it.
struct DoddySlotFigure: View {
    let id: MotionSurfaceID
    private var director: DoddyDirector { .shared }

    var body: some View {
        if let figure = director.figure {
            DoddyFigureView(figure: figure)
                .alignmentGuide(.top) { $0[.bottom] }
                // Relative to the surface's own frame, so it stays exact while the system moves it.
                .offset(x: CGFloat(figure.slotDX), y: CGFloat(figure.slotDY))
        }
    }
}

/// The root overlay (in RootView, above the tab content and the tab bar, under every sheet and
/// cover): draws him only while he is in the air, fading, or crouching on a surface that has just
/// gone. With `-doddyMotionDebug YES` (DEBUG builds) it also draws the annotated mode.
struct DoddyOverlay: View {
    private var director: DoddyDirector { .shared }

    var body: some View {
        let origin = CGPoint(x: director.overlayOrigin.x, y: director.overlayOrigin.y)
        ZStack(alignment: .topLeading) {
            Color.clear
            if director.placement == .overlay, let figure = director.figure {
                let picture = DoddyFigureMetrics.picture(figure.art.picture)
                let soleBox = CGFloat(DoddyFigureMetrics.pictureHeight * figure.scale * picture.ground)
                DoddyFigureView(figure: figure)
                    .position(x: CGFloat(figure.x) - origin.x, y: CGFloat(figure.y) - origin.y - soleBox / 2)
            }
            #if DEBUG
            if DoddyMotionDebug.isOn { DoddyDebugOverlay(origin: origin) }
            #endif
        }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { o in
            MainActor.assumeIsolated { DoddyDirector.shared.overlayMoved(to: MotionPoint(x: Double(o.x), y: Double(o.y))) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The DEBUG annotated mode (plan, MV3): launched with `-doddyMotionDebug YES`.
enum DoddyMotionDebug {
    static var isOn: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "doddyMotionDebug")
        #else
        false
        #endif
    }
}

#if DEBUG
/// The surfaces he can stand on (their edges, stand range thicker), his clear zone, a frame
/// counter, his mode and surface, and the DEBUG checks' count, after the reference's annotated
/// clips. Read from the director every frame he moves.
private struct DoddyDebugOverlay: View {
    let origin: CGPoint
    private var director: DoddyDirector { .shared }

    var body: some View {
        let d = director
        let e = d.engine
        // Reading `figure` keeps this redrawn every frame he moves.
        let figure = d.figure
        ZStack(alignment: .topLeading) {
            ForEach(Array(d.host.scene.mounted).map(\.description).sorted(), id: \.self) { key in
                if let id = d.host.scene.mounted.first(where: { $0.description == key }), let f = d.frames[id] {
                    let range = d.host.surface(id).standRange()
                    Rectangle().fill(Color.blue.opacity(0.5))
                        .frame(width: CGFloat(f.width), height: 1)
                        .position(x: CGFloat(f.midX) - origin.x, y: CGFloat(f.minY) - origin.y)
                    Rectangle().fill(Color.blue)
                        .frame(width: CGFloat(max(2, range.upperBound - range.lowerBound)), height: 3)
                        .position(x: CGFloat((range.lowerBound + range.upperBound) / 2) - origin.x, y: CGFloat(f.minY) - origin.y)
                }
            }
            if let figure {
                let zone = MotionLayout.zone(soles: MotionPoint(x: figure.x, y: figure.y), scale: figure.scale)
                Rectangle().stroke(Color.red, lineWidth: 1)
                    .frame(width: CGFloat(zone.width), height: CGFloat(zone.height))
                    .position(x: CGFloat(zone.midX) - origin.x, y: CGFloat(zone.midY) - origin.y)
            }
            Text(verbatim: "f \(d.frameCount) · \(e.mode.rawValue) · \(e.activity) · \(e.anchor?.surface.description ?? "–") · \(String(format: "%.2f", e.scale))× · \(String(describing: d.placement)) · checks \(d.checks.count)")
                .font(.caption2.monospaced())
                .padding(4)
                .background(Color.white.opacity(0.85))
                .foregroundStyle(Color.black)
                .position(x: 195, y: 70)
                .accessibilityIdentifier("doddy.debug")
        }
    }
}
#endif
