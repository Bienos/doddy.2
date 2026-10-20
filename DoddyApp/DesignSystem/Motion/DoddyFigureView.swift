import DoddyCore
import SwiftUI

// Motion v2, MV3: drawing the one persistent Doddy. One view (`PersistentDoddyView`) draws him
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
struct PersistentDoddyView: View {
    let figure: DoddyFigure
    /// Where this view draws him (`slot ledge:settings`, `overlay`), for the one-Doddy check.
    let spot: String
    /// Home's eyes (ADR-560), drawn while he stands on Home's stage: they follow a finger on Home,
    /// half close while he is touched and blink once in the evening. Nil everywhere else, where
    /// his eyes stay as the pack drew them.
    var homeEyes: HomeEyesModel?
    @Environment(\.colorScheme) private var colorScheme
    @State private var token = UUID()

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
            // Over the picture, so they squash, tilt, mirror and fade with it. Only pictures with
            // a measured, front-facing face (breathing, the wave, sitting); nothing at all while
            // his eyes are on you.
            .modifier(HomeEyesOnFigure(eyes: homeEyes, asset: picture.asset, width: width, mirrored: art.mirrored))
            .scaleEffect(x: CGFloat((art.mirrored ? -1 : 1) * art.scaleX), y: CGFloat(art.scaleY), anchor: soles)
            .rotationEffect(.degrees(art.tilt), anchor: soles)
            // In dark appearance the black outline gets the island's thin cream edge (plan section 2).
            .islandCreamEdge(colorScheme == .dark)
            .frame(width: width, height: height * ground, alignment: .top)
            .opacity(figure.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { DoddyDirector.shared.drawingAppeared(token, in: spot) }
            .onDisappear { DoddyDirector.shared.drawingGone(token) }
        if DoddyArtMarkers.isOn {
            // The UI tests' marker is a box exactly his laid-out size, its bottom edge his soles
            // (the picture's own frame reaches below them, to its transparent margin).
            drawn.overlay {
                Rectangle()
                    .fill(Color.white.opacity(0.01))
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel(art.marker)
                    .accessibilityIdentifier(art.marker)
            }
        } else {
            drawn
        }
    }
}

/// Home's eyes on his picture, and where his eyes are on the screen for them to look from. The
/// frame is the picture's own (before it is squashed, tilted or mirrored), which is close enough
/// for which of nine looks to show.
private struct HomeEyesOnFigure: ViewModifier {
    let eyes: HomeEyesModel?
    let asset: String
    let width: CGFloat
    let mirrored: Bool

    func body(content: Content) -> some View {
        if let eyes, DoddyEyes.hasFace(asset) {
            content
                .overlay(alignment: .topLeading) {
                    HomeEyesLayer(asset: asset, unit: width / CGFloat(DoddyEyes.pictureWidth), eyes: eyes, mirrored: mirrored)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [asset, mirrored] frame in
                    MainActor.assumeIsolated { eyes.pictureMoved(asset: asset, frame: frame, mirrored: mirrored) }
                }
        } else {
            content
        }
    }
}

/// Him in a surface's slot: soles on the surface's top edge, at his spot along it.
struct DoddySlotFigure: View {
    let id: MotionSurfaceID
    private var director: DoddyDirector { .shared }

    var body: some View {
        if let figure = director.figure {
            // A zero-size point on the surface's top edge, with him standing on it: his soles are
            // on the edge whatever his height (an alignment guide doesn't pass through the slot's
            // stack, which drew him hanging below the edge in hosted run 39210073005).
            Color.clear
                .frame(width: 0, height: 0)
                .overlay(alignment: .bottom) {
                    PersistentDoddyView(figure: figure, spot: "slot \(id)", homeEyes: id == .stage ? .shared : nil).fixedSize()
                }
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
                PersistentDoddyView(figure: figure, spot: "overlay")
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

    /// UI tests only (MV6): `-doddyReduceMotion YES` makes him behave as with Reduce Motion on,
    /// since a test can't turn the system setting on. DEBUG builds only; the app itself follows
    /// the system setting.
    static var forcesReduceMotion: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "doddyReduceMotion")
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
                let zone = MotionLayout.zone(soles: e.pos, scale: figure.scale)
                Rectangle().stroke(Color.red, lineWidth: 1)
                    .frame(width: CGFloat(zone.width), height: CGFloat(zone.height))
                    .position(x: CGFloat(zone.midX) - origin.x, y: CGFloat(zone.midY) - origin.y)
            }
            Text(verbatim: "f \(d.frameCount) · \(e.mode.rawValue) · \(e.activity) · \(e.anchor?.surface.description ?? "–") · \(String(format: "%.2f", e.scale))× · \(String(describing: d.placement)) · flights \(d.flightsSeen) · checks \(d.checks.count)")
                .font(.caption2.monospaced())
                .padding(4)
                .background(Color.white.opacity(0.85))
                .foregroundStyle(Color.black)
                .position(x: 195, y: 70)
                .accessibilityIdentifier("doddy.debug")
            // The newest finding in words, so a failing run says what broke.
            Text(verbatim: d.checks.lastDetail)
                .font(.caption2.monospaced())
                .padding(4)
                .background(Color.white.opacity(0.85))
                .foregroundStyle(Color.red)
                .position(x: 195, y: 100)
                .accessibilityIdentifier("doddy.debug.last")
            // The engine's last decisions and where each drawing of him is, for a failing run.
            Text(verbatim: "drawn: \(d.drawingsDescription) | " + e.metrics.events.suffix(5).map { "\(Int($0.t)) \($0.message)" }.joined(separator: " | "))
                .font(.system(size: 8, design: .monospaced))
                .padding(2)
                .background(Color.white.opacity(0.85))
                .foregroundStyle(Color.black)
                .frame(width: 380, alignment: .leading)
                .position(x: 195, y: 150)
                .accessibilityIdentifier("doddy.debug.trail")
        }
    }
}
#endif
