import DoddyCore
import SwiftUI

/// Draws the opening (`OpeningScene`, ADR-210) over the whole screen for the time since it
/// started: a pen sketches Doddy in, he dribbles, crouches, hops and shoots, the ball flies into
/// the ring ("SWISH!", confetti, a shake), he pops up ready to talk, and then jumps into his
/// place on Home while the paper fades and Home shows through. The last frame draws him
/// exactly where Home draws him (`homeTarget`, measured by Home), with the same view
/// (`CharacterArtImage`), so when this view goes away nothing moves.
///
/// Presentation only: every value comes from `OpeningScene` and `OpeningHandover`; the view
/// never starts a conversation or reads a setting. It tells the model when the hand-over starts
/// (Home's buttons slide in) and when it is over.
struct OpeningSceneView: View {
    let play: OpeningPlay
    /// Home's picture of Doddy, in global points; nil until Home has been laid out.
    let homeTarget: ScreenBox?
    let onHandover: () -> Void
    let onFinished: () -> Void

    @State private var done = false
    @State private var scored = false
    @State private var handoverSent = false
    /// Seconds added to the clock by a tap: the tap jumps straight to the hand-over.
    @State private var shift: TimeInterval = 0

    private func time(_ date: Date) -> TimeInterval { date.timeIntervalSince(play.startedAt) + shift }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: done)) { context in
                let t = time(context.date)
                scene(OpeningScene.frame(at: t, reducedMotion: play.reducedMotion), at: t, in: geo)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Doddy's opening. Doddy scores a basket.")
        .accessibilityHint("Double-tap to skip.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("opening.scene")
        .sensoryFeedback(.impact(weight: .light), trigger: scored)
        .task {
            // The timeline draws; this only watches for three of its moments.
            let length = OpeningScene.duration(reducedMotion: play.reducedMotion)
            while !Task.isCancelled {
                let t = time(.now)
                if !play.reducedMotion && !scored && t >= OpeningScene.Beat.score && t < OpeningScene.Beat.score + 0.3 {
                    scored = true
                }
                if !handoverSent && (play.reducedMotion || t >= OpeningScene.Beat.handoverStart) {
                    handoverSent = true
                    onHandover()
                }
                if t >= length {
                    finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    /// A tap goes straight to the hand-over (or the still picture's fade), so Doddy still lands
    /// in his place instead of the screen cutting.
    private func skip() {
        let t = time(.now)
        let target = play.reducedMotion
            ? max(t, OpeningScene.duration(reducedMotion: true) - 0.25)
            : max(t, OpeningScene.Beat.handoverStart)
        shift += target - t
    }

    private func finish() {
        guard !done else { return }
        done = true
        onFinished()
    }

    // MARK: - Layers

    private func scene(_ frame: OpeningFrame, at t: TimeInterval, in geo: GeometryProxy) -> some View {
        let size = geo.size
        let origin = geo.frame(in: .global).origin
        let court = OpeningHandover.courtBox(screenWidth: Double(size.width), screenHeight: Double(size.height))
        let home = homeTarget.map {
            ScreenBox(centerX: $0.centerX - Double(origin.x), centerY: $0.centerY - Double(origin.y), height: $0.height)
        }
        let inPlace = play.reducedMotion || t >= OpeningScene.Beat.handoverStart
        let placed = OpeningHandover.place(court: court, home: home, at: t, reducedMotion: play.reducedMotion)
        return ZStack(alignment: .topLeading) {
            // The paper. As it fades, Home shows through.
            Theme.canvas.opacity(frame.backdropOpacity)
            if !play.reducedMotion {
                stage(frame, at: t, drawsReadyDoddy: !inPlace, size: size)
            }
            if inPlace { placedDoddy(placed) }
            Text("Tap to skip")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity)
                .position(x: size.width / 2, y: size.height - 40)
                .opacity(frame.hintOpacity)
        }
        .frame(width: size.width, height: size.height)
        .foregroundStyle(Theme.ink)
    }

    /// Everything on the court, through the camera (zoom about a moving point, and the shake).
    private func stage(_ frame: OpeningFrame, at t: TimeInterval, drawsReadyDoddy: Bool, size: CGSize) -> some View {
        let w = size.width
        return ZStack {
            Group {
                court(w)
                backboard(w)
                ring(w, front: false, wobble: frame.burst.ringWobble)
            }
            .opacity(frame.setOpacity)
            figure(frame.doddy, at: t, drawsReady: drawsReadyDoddy, w)
            ball(frame.ball, w)
            Group {
                ring(w, front: true, wobble: frame.burst.ringWobble)
                net(frame.netStretch, wobble: frame.burst.ringWobble, w)
                particles(frame.particles, w)
                burst(frame.burst, w)
            }
            .opacity(frame.setOpacity)
        }
        .frame(width: w, height: w * CGFloat(OpeningScene.stageHeight))
        .scaleEffect(
            CGFloat(frame.camera.scale),
            anchor: UnitPoint(x: frame.camera.anchor.x, y: frame.camera.anchor.y / OpeningScene.stageHeight))
        .offset(x: CGFloat(frame.camera.shake.x) * w, y: CGFloat(frame.camera.shake.y) * w)
        .position(x: size.width / 2, y: size.height / 2)
    }

    /// Doddy on his way to (or in) his place on Home, in screen points.
    private func placedDoddy(_ placed: PlacedDoddy) -> some View {
        CharacterArtImage(assetName: "UploadedDoddy_Listening", height: CGFloat(placed.box.height))
            .scaleEffect(
                x: CGFloat(placed.squashX), y: CGFloat(placed.squashY),
                anchor: UnitPoint(x: 0.5, y: OpeningLayout.readyFeetFraction))
            .position(x: CGFloat(placed.box.centerX), y: CGFloat(placed.box.centerY))
            .opacity(placed.opacity)
    }

    /// The floor line and the free-throw arc under the hoop, in the quiet separator colour.
    private func court(_ w: CGFloat) -> some View {
        let floor = CGFloat(OpeningLayout.floorY) * w
        let arcRadius = CGFloat(OpeningLayout.keyArcRadius) * w
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: floor))
                path.addLine(to: CGPoint(x: w, y: floor))
            }
            .stroke(Theme.separator, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            // The top half of a circle: a dome on the floor.
            Circle()
                .trim(from: 0.5, to: 1)
                .stroke(Theme.separator, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: arcRadius * 2, height: arcRadius * 2)
                .position(x: CGFloat(OpeningLayout.ringCenter.x) * w, y: floor)
        }
    }

    private func backboard(_ w: CGFloat) -> some View {
        let board = OpeningLayout.backboard
        let ring = OpeningLayout.ringCenter
        return Path { path in
            path.addRoundedRect(
                in: CGRect(
                    x: CGFloat(board.origin.x) * w, y: CGFloat(board.origin.y) * w,
                    width: CGFloat(board.width) * w, height: CGFloat(board.height) * w),
                cornerSize: CGSize(width: 3, height: 3))
            // The bracket that holds the ring.
            path.move(to: CGPoint(x: CGFloat(ring.x + OpeningLayout.ringWidth / 2) * w, y: CGFloat(ring.y) * w))
            path.addLine(to: CGPoint(x: CGFloat(board.origin.x) * w, y: CGFloat(ring.y) * w))
        }
        .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    /// The ring in two halves, so the ball passes behind its far edge and in front of its near
    /// one. It swings a little from the bracket after a score.
    private func ring(_ w: CGFloat, front: Bool, wobble: Double) -> some View {
        Ellipse()
            .trim(from: front ? 0 : 0.5, to: front ? 0.5 : 1)
            .stroke(Theme.orangeCue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: CGFloat(OpeningLayout.ringWidth) * w, height: CGFloat(OpeningLayout.ringHeight) * w)
            .rotationEffect(.radians(wobble), anchor: .trailing)
            .position(x: CGFloat(OpeningLayout.ringCenter.x) * w, y: CGFloat(OpeningLayout.ringCenter.y) * w)
    }

    private func net(_ stretch: Double, wobble: Double, _ w: CGFloat) -> some View {
        let top = OpeningLayout.ringCenter
        let half = OpeningLayout.ringWidth / 2
        let depth = OpeningLayout.netDepth * stretch
        return Path { path in
            for string in 0..<6 {
                let f = Double(string) / 5
                let x0 = top.x - half + OpeningLayout.ringWidth * f
                let x1 = top.x - half * 0.55 + OpeningLayout.ringWidth * 0.55 * f
                path.move(to: CGPoint(x: CGFloat(x0) * w, y: CGFloat(top.y) * w))
                path.addLine(to: CGPoint(x: CGFloat(x1) * w, y: CGFloat(top.y + depth) * w))
            }
            for row in [0.4, 0.8] {
                let reach = half * (1 - 0.45 * row)
                let y = CGFloat(top.y + depth * row) * w
                path.move(to: CGPoint(x: CGFloat(top.x - reach) * w, y: y))
                path.addLine(to: CGPoint(x: CGFloat(top.x + reach) * w, y: y))
            }
        }
        .stroke(Theme.ink.opacity(0.7), lineWidth: 1)
        .rotationEffect(.radians(wobble), anchor: UnitPoint(x: top.x + half, y: top.y / OpeningScene.stageHeight))
    }

    /// Dust puffs and confetti.
    private func particles(_ particles: [OpeningParticle], _ w: CGFloat) -> some View {
        ZStack {
            ForEach(Array(particles.enumerated()), id: \.offset) { _, piece in
                let size = CGFloat(piece.size) * w
                Group {
                    switch piece.kind {
                    case .dust:
                        Circle().fill(Theme.secondaryText.opacity(0.45))
                            .frame(width: size, height: size)
                    case .confettiOrange:
                        Rectangle().fill(Theme.orangeCue)
                            .frame(width: size, height: size * 0.45)
                    case .confettiInk:
                        Rectangle().fill(Theme.ink)
                            .frame(width: size, height: size * 0.45)
                    }
                }
                .rotationEffect(.radians(piece.rotation))
                .position(x: CGFloat(piece.center.x) * w, y: CGFloat(piece.center.y) * w)
                .opacity(piece.opacity)
            }
        }
    }

    // MARK: Doddy

    /// The drawing that is up and, during a change of pose, the next one fading in over it,
    /// squashed, stretched and lifted about the feet. From the hand-over the ready pose is drawn
    /// in screen points instead (`placedDoddy`), so it is left out here.
    private func figure(_ figure: OpeningDoddy, at t: TimeInterval, drawsReady: Bool, _ w: CGFloat) -> some View {
        let box = OpeningLayout.doddy
        let side = CGFloat(box.width) * w
        return ZStack(alignment: .bottom) {
            if figure.pose != .ready || drawsReady {
                pose(figure.pose, sketch: figure.sketch, readyPop: figure.readyPop, at: t, side: side, w)
                    .opacity(1 - figure.blend)
            }
            if figure.blend > 0 && (figure.nextPose != .ready || drawsReady) {
                pose(figure.nextPose, sketch: 1, readyPop: figure.readyPop, at: t, side: side, w)
                    .opacity(figure.blend)
            }
        }
        .frame(width: side, height: side, alignment: .bottom)
        .scaleEffect(x: CGFloat(figure.squashX), y: CGFloat(figure.squashY), anchor: .bottom)
        .position(x: CGFloat(box.center.x) * w, y: CGFloat(box.center.y - figure.hop) * w)
    }

    @ViewBuilder
    private func pose(_ which: OpeningPose, sketch: Double, readyPop: Double, at t: TimeInterval, side: CGFloat, _ w: CGFloat) -> some View {
        if which == .ready {
            readyArt(pop: readyPop, w)
        } else if let drawing = play.drawings[which] {
            let count = drawing.strokes.count
            DoddyFigureView(drawing: drawing, side: side) { index in
                // Only the first drawing is sketched in; the others are complete when they appear.
                which == .dribble && sketch < 1 ? OpeningScene.strokeProgress(index: index, count: count, at: t) : 1
            }
        }
    }

    /// The ready pose on the court, popping up from nothing at his feet. The same view and size
    /// as `placedDoddy` at the start of the hand-over, so the switch between them doesn't show.
    private func readyArt(pop: Double, _ w: CGFloat) -> some View {
        let box = OpeningLayout.ready
        let shooter = OpeningLayout.doddy
        // The figure frame is bottom-aligned to the shooter's box; move the art to its own box.
        let drop = CGFloat((box.origin.y + box.height) - (shooter.origin.y + shooter.height)) * w
        return CharacterArtImage(assetName: "UploadedDoddy_Listening", height: CGFloat(box.height) * w)
            .scaleEffect(CGFloat(max(0, pop)), anchor: UnitPoint(x: 0.5, y: OpeningLayout.readyFeetFraction))
            .offset(y: drop)
    }

    // MARK: Ball and burst

    private func ball(_ state: OpeningBall, _ w: CGFloat) -> some View {
        let diameter = CGFloat(state.radius) * 2 * w
        return ZStack {
            // Ghosts of where it just was, fading with distance.
            ForEach(Array(state.trail.enumerated()), id: \.offset) { index, ghost in
                Circle()
                    .fill(Theme.orangeCue)
                    .frame(width: diameter * 0.9, height: diameter * 0.9)
                    .opacity(0.28 / Double(index + 1))
                    .position(x: CGFloat(ghost.x) * w, y: CGFloat(ghost.y) * w)
            }
            ZStack {
                Circle().fill(Theme.orangeCue)
                Circle().strokeBorder(Theme.ink, lineWidth: 1.5)
                BallSeams().stroke(Theme.ink, lineWidth: 1.2)
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.radians(state.spin))
            // Stretched along the way it is going.
            .scaleEffect(x: CGFloat(state.stretch), y: CGFloat(1 / state.stretch.squareRoot()))
            .rotationEffect(.radians(state.heading))
            // Flattened on the floor.
            .scaleEffect(x: 1 + CGFloat(1 - state.squash) * 0.6, y: CGFloat(state.squash), anchor: .bottom)
            .scaleEffect(CGFloat(max(0, state.scale)))
            .position(x: CGFloat(state.center.x) * w, y: CGFloat(state.center.y) * w)
        }
        .opacity(state.opacity)
    }

    /// "SWISH!" with rays shooting out, popping in and settling.
    private func burst(_ burst: OpeningBurst, _ w: CGFloat) -> some View {
        let at = OpeningLayout.burstAt
        let inner = 0.06 * w
        let outer = inner + CGFloat(OpeningLayout.burstRayLength * burst.rays) * w
        return ZStack {
            Path { path in
                for ray in 0..<8 {
                    let angle = Double(ray) / 8 * 2 * .pi - .pi / 2
                    path.move(to: CGPoint(x: inner * CGFloat(cos(angle)), y: inner * CGFloat(sin(angle))))
                    path.addLine(to: CGPoint(x: outer * CGFloat(cos(angle)), y: outer * CGFloat(sin(angle))))
                }
            }
            .stroke(Theme.orangeCue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 1, height: 1)
            Text("SWISH!")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(Theme.ink)
                .rotationEffect(.degrees(-12))
        }
        .scaleEffect(CGFloat(max(0, burst.scale)))
        .position(x: CGFloat(at.x) * w, y: CGFloat(at.y) * w)
        .opacity(burst.opacity)
    }

}

/// One of the supplied line drawings as strokes, each drawn as far as `progress(index)` says
/// (0…1), so the pen can be seen drawing it. Ink, paper and orange follow the appearance.
private struct DoddyFigureView: View {
    let drawing: DoddyDrawing
    let side: CGFloat
    let progress: (Int) -> Double

    var body: some View {
        let scale = side / CGFloat(drawing.size)
        ZStack {
            ForEach(Array(drawing.strokes.enumerated()), id: \.offset) { index, stroke in
                let path = Self.path(stroke, scale: scale)
                let p = progress(index)
                if let fill = stroke.fill {
                    path.fill(Self.color(fill)).opacity(p)
                }
                if let ink = stroke.stroke, stroke.lineWidth > 0 {
                    path.trim(from: 0, to: CGFloat(p))
                        .stroke(Self.color(ink), style: StrokeStyle(lineWidth: CGFloat(stroke.lineWidth) * scale, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: side, height: side)
    }

    private static func color(_ role: ArtColor) -> Color {
        switch role {
        case .ink: Theme.ink
        case .paper: Theme.canvas
        case .orange: Theme.orangeCue
        }
    }

    private static func path(_ stroke: DrawnStroke, scale: CGFloat) -> Path {
        var path = Path()
        for command in stroke.commands {
            switch command {
            case .move(let x, let y):
                path.move(to: CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale))
            case .line(let x, let y):
                path.addLine(to: CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale))
            case .quad(let cx, let cy, let x, let y):
                path.addQuadCurve(
                    to: CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale),
                    control: CGPoint(x: CGFloat(cx) * scale, y: CGFloat(cy) * scale))
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                path.addCurve(
                    to: CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale),
                    control1: CGPoint(x: CGFloat(c1x) * scale, y: CGFloat(c1y) * scale),
                    control2: CGPoint(x: CGFloat(c2x) * scale, y: CGFloat(c2y) * scale))
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}

/// Two seams across the ball.
private struct BallSeams: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.width / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + r * 0.9, y: c.y))
        path.move(to: CGPoint(x: c.x - r, y: c.y))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x, y: c.y + r * 0.9))
        return path
    }
}

#Preview("Opening, mid-flight") {
    if let drawings = OpeningDrawings.load() {
        OpeningSceneView(
            play: OpeningPlay(
                reducedMotion: false, thenListen: false,
                drawings: drawings,
                startedAt: Date().addingTimeInterval(-1.2)),
            homeTarget: nil, onHandover: {}, onFinished: {})
    } else {
        Text("The pose SVGs are not in the bundle.")
    }
}
