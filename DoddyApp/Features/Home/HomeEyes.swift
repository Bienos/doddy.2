import DoddyCore
import SwiftUI

// Home's Doddy gets his eyes (ADR-546): they follow a finger anywhere on Home, half close while a
// finger is on him, and after 21:00 he gives one slow blink, once a day. The eyes are cut from the
// owner's sheets 007 and 008 (`DoddyEyes`); looking at you, the picture is the pack's own.

/// Where his eyes are on Home, from the finger, a press on him and the evening blink.
@MainActor
@Observable
final class HomeEyesModel {
    /// The piece he shows when no blink is playing.
    private(set) var look: DoddyLook = .atYou
    /// When the evening blink started; nil when none is playing.
    private(set) var blinkStart: Date?

    @ObservationIgnored private var eyes: DoddyEyePoint?
    @ObservationIgnored private var finger: DoddyEyePoint?
    @ObservationIgnored private var lifted: (point: DoddyEyePoint, at: Date)?
    @ObservationIgnored private var pressed = false
    @ObservationIgnored private var comeBack: Task<Void, Never>?

    /// Where his eyes are on the screen (window points), from the picture's frame.
    func pictureMoved(asset: String, frame: CGRect) {
        guard let centre = DoddyEyes.eyesCentre(asset) else { return }
        let unit = frame.width / CGFloat(DoddyEyes.pictureWidth)
        eyes = DoddyEyePoint(x: Double(frame.minX + CGFloat(centre.x) * unit), y: Double(frame.minY + CGFloat(centre.y) * unit))
        update()
    }

    func fingerMoved(to point: CGPoint) {
        comeBack?.cancel()
        finger = DoddyEyePoint(x: Double(point.x), y: Double(point.y))
        lifted = nil
        update()
    }

    /// The finger lifted: he keeps looking there for a moment, then back at you.
    func fingerLifted(at point: CGPoint) {
        finger = nil
        lifted = (DoddyEyePoint(x: Double(point.x), y: Double(point.y)), Date())
        update()
        comeBack?.cancel()
        comeBack = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HomeEyes.returnAfter + 0.02))
            guard !Task.isCancelled, let self else { return }
            self.lifted = nil
            self.update()
        }
    }

    func setPressed(_ down: Bool) {
        pressed = down
        update()
    }

    /// The evening's one slow blink.
    func blink() {
        let start = Date()
        blinkStart = start
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(HomeEyes.blinkDuration + 0.05))
            if self?.blinkStart == start { self?.blinkStart = nil }
        }
    }

    /// Previews and the app's tests only: show one piece.
    func show(_ look: DoddyLook) { self.look = look }

    /// The piece to draw at `date` (a playing blink wins).
    func currentLook(at date: Date) -> DoddyLook {
        if let blinkStart {
            let closed = HomeEyes.blink(elapsed: date.timeIntervalSince(blinkStart))
            if closed > 0 { return DoddyEyes.look(DoddyEyeState(closed: closed)) }
        }
        return look
    }

    private func update() {
        guard let eyes else { return }
        let new = HomeEyes.look(eyes: eyes, finger: finger,
                                lifted: lifted.map { (point: $0.point, ago: Date().timeIntervalSince($0.at)) },
                                pressed: pressed, blinkElapsed: nil, previous: look)
        if new != look { look = new }
    }
}

/// Doddy's pose picture with his eyes on it: the same drawing and crop as `WholeDoddyView`, plus
/// the cut eyes laid over the picture when they aren't on you.
struct HomeDoddyFigure: View {
    let pose: IslandPose
    var height: CGFloat = 180
    let eyes: HomeEyesModel
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            let shown = textSize.isAccessibilitySize ? min(height, 100) : height
            let box = pose.figure
            // As `IslandFigureView`: the 2:3 picture sized so its figure box fits, cropped to the box.
            let figureWidth = shown * CGFloat(box.width / box.height) / 1.5
            let width = min(figureWidth / CGFloat(box.width), shown / (CGFloat(box.height) * 1.5))
            let pictureHeight = width * 1.5
            let asset = pose.assetName
            Image(asset)
                .resizable()
                .frame(width: width, height: pictureHeight)
                .overlay(alignment: .topLeading) {
                    HomeEyesLayer(asset: asset, unit: width / CGFloat(DoddyEyes.pictureWidth), eyes: eyes)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    MainActor.assumeIsolated { eyes.pictureMoved(asset: asset, frame: frame) }
                }
                .offset(x: -CGFloat(box.x) * width, y: -CGFloat(box.y) * pictureHeight)
                .frame(width: CGFloat(box.width) * width, height: CGFloat(box.height) * pictureHeight, alignment: .topLeading)
                .islandCreamEdge(colorScheme == .dark)
                .frame(width: figureWidth, height: shown, alignment: .bottom)
                .accessibilityHidden(true)
                .doddyArtMarker("doddy.pose.\(pose.rawValue)")
        }
    }
}

/// The cut eyes over the picture: for each eye, a soft cover in the paper's colour over the
/// picture's own eye, then the eye from the owner's sheet. Positions are in pixels of the picture's
/// @3x file, `unit` points each. Nothing at all when he looks at you.
private struct HomeEyesLayer: View {
    let asset: String
    let unit: CGFloat
    let eyes: HomeEyesModel

    var body: some View {
        // Frames only while the evening blink plays; otherwise it redraws when his look changes.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: eyes.blinkStart == nil)) { context in
            let layers = DoddyEyes.layers(for: asset, look: eyes.currentLook(at: context.date))
            ZStack(alignment: .topLeading) {
                ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                    piece(layer)
                        .frame(width: CGFloat(layer.width) * unit, height: CGFloat(layer.height) * unit)
                        .position(x: CGFloat(layer.x) * unit, y: CGFloat(layer.y) * unit)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func piece(_ layer: DoddyEyeLayer) -> some View {
        switch layer.kind {
        case .cover(let fill, let blur):
            Ellipse()
                .fill(Color(red: Double(fill[0]) / 255, green: Double(fill[1]) / 255, blue: Double(fill[2]) / 255))
                .blur(radius: CGFloat(blur) * unit)
        case .piece(let asset):
            Image(asset).resizable()
        }
    }
}
