import DoddyCore
import SwiftUI

/// Draws the opening (`OpeningScene`, ADR-207) over the whole screen for the time since it
/// started: a pen sketches Doddy in, he dribbles, crouches, hops and shoots, the ball arcs into
/// the ring ("SWISH!"), and he pops up ready to talk with a hello while the court fades for
/// Home to take over. Presentation only: every value comes from `OpeningScene.frame(at:)`,
/// and the view never starts a conversation or reads a setting. When the timeline ends, or the
/// user taps, it tells the model, which does the rest.
struct OpeningSceneView: View {
    let play: OpeningPlay
    let onFinished: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var done = false
    @State private var scored = false

    var body: some View {
        TimelineView(.animation(paused: done)) { context in
            let t = context.date.timeIntervalSince(play.startedAt)
            stage(OpeningScene.frame(at: t, reducedMotion: play.reducedMotion), at: t)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Doddy's opening. Doddy scores a basket and says: \(play.greeting.spoken)")
        .accessibilityHint("Double-tap to skip.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("opening.scene")
        .sensoryFeedback(.impact(weight: .light), trigger: scored)
        .task {
            // The timeline is the clock; this only waits for two of its moments.
            if !play.reducedMotion {
                let untilScore = OpeningScene.Beat.score - Date().timeIntervalSince(play.startedAt)
                if untilScore > 0 { try? await Task.sleep(for: .seconds(untilScore)) }
                if Task.isCancelled { return }
                scored = true
            }
            let untilEnd = OpeningScene.duration(reducedMotion: play.reducedMotion) - Date().timeIntervalSince(play.startedAt)
            if untilEnd > 0 { try? await Task.sleep(for: .seconds(untilEnd)) }
            if Task.isCancelled { return }
            finish()
        }
    }

    private func finish() {
        guard !done else { return }
        done = true
        onFinished()
    }

    // MARK: - Stage

    private func stage(_ frame: OpeningFrame, at t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                // The set: court and hoop. It fades at the hand-over while Doddy stays.
                Group {
                    court(w)
                    backboard(w)
                    ring(w, front: false, wobble: frame.burst.ringWobble)
                }
                .opacity(frame.setOpacity)
                figure(frame.doddy, at: t, w)
                ball(frame.ball, w)
                Group {
                    ring(w, front: true, wobble: frame.burst.ringWobble)
                    net(frame.netStretch, wobble: frame.burst.ringWobble, w)
                    burst(frame.burst, w)
                }
                .opacity(frame.setOpacity)
                bubble(frame.bubble, w)
            }
            .frame(width: w, height: w * CGFloat(OpeningScene.stageHeight))
            .scaleEffect(
                CGFloat(frame.camera.scale),
                anchor: UnitPoint(x: frame.camera.anchor.x, y: frame.camera.anchor.y / OpeningScene.stageHeight))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .overlay(alignment: .bottom) {
            Text("Tap to skip")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .padding(.bottom, 12)
                .opacity(frame.hintOpacity)
        }
        .foregroundStyle(Theme.ink)
        .background { Theme.canvas.ignoresSafeArea() }
        .opacity(frame.sceneOpacity)
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
        .rotationEffect(
            .radians(wobble),
            anchor: UnitPoint(x: (top.x + half) , y: top.y / OpeningScene.stageHeight))
    }

    // MARK: Doddy

    /// The drawing that is up and, during a change of pose, the next one fading in over it,
    /// squashed, stretched and lifted about the feet.
    private func figure(_ figure: OpeningDoddy, at t: TimeInterval, _ w: CGFloat) -> some View {
        let box = OpeningLayout.doddy
        let side = CGFloat(box.width) * w
        return ZStack(alignment: .bottom) {
            pose(figure.pose, sketch: figure.sketch, readyPop: figure.readyPop, at: t, side: side, w)
                .opacity(1 - figure.blend)
            if figure.blend > 0 {
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

    /// The listening artwork Home shows too (`UploadedDoddy_Listening`), feet on the floor,
    /// popping up from nothing. In dark appearance it keeps its paper backing, as on Home.
    private func readyArt(pop: Double, _ w: CGFloat) -> some View {
        let box = OpeningLayout.ready
        let shooter = OpeningLayout.doddy
        // The figure frame is bottom-aligned to the shooter's box; move the art to its own box.
        let drop = CGFloat((box.origin.y + box.height) - (shooter.origin.y + shooter.height)) * w
        let feet = CGFloat(box.height * OpeningLayout.readyFeetFraction) / CGFloat(box.height)
        return Image(decorative: "UploadedDoddy_Listening")
            .resizable()
            .scaledToFit()
            .frame(width: CGFloat(box.width) * w, height: CGFloat(box.height) * w)
            .padding(.horizontal, colorScheme == .dark ? 12 : 0)
            .background(colorScheme == .dark ? Color(red: 245/255, green: 239/255, blue: 226/255) : .clear,
                        in: RoundedRectangle(cornerRadius: 24))
            .scaleEffect(CGFloat(max(0, pop)), anchor: UnitPoint(x: 0.5, y: feet))
            .offset(y: drop)
    }

    // MARK: Ball, burst, bubble

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

    /// The hello, in a bubble above Doddy whose tail points down at his head. It pops from the tail.
    private func bubble(_ pop: OpeningBubble, _ w: CGFloat) -> some View {
        let width = CGFloat(OpeningLayout.bubbleWidth) * w
        let height = 0.5 * w
        let anchor = OpeningLayout.bubbleAnchor
        return VStack(alignment: .leading, spacing: 4) {
            Text(play.greeting.headline)
                .font(.title3.weight(.semibold))
            Text(play.greeting.question)
                .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12 + SpeechBubble.tailHeight)
        .background {
            ZStack {
                SpeechBubble().fill(Theme.quietSurface)
                SpeechBubble().stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .frame(maxWidth: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .scaleEffect(CGFloat(max(0, pop.scale)), anchor: .bottomLeading)
        // The bubble's bottom-left corner sits at `bubbleAnchor`, whatever its size.
        .frame(width: width, height: height, alignment: .bottomLeading)
        .position(x: CGFloat(anchor.x) * w + width / 2, y: CGFloat(anchor.y) * w - height / 2)
        .opacity(pop.opacity)
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

/// A rounded box with a tail at the left of its bottom edge, drawn as one outline so the stroke
/// is clean. Corners are quadratic curves, which need no arc direction.
private struct SpeechBubble: Shape {
    static let tailHeight: CGFloat = 10
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.width / 3)
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.tailHeight)
        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + r), control: CGPoint(x: body.maxX, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addQuadCurve(to: CGPoint(x: body.maxX - r, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
        // The tail, near the left end of the bottom edge: down and a little to the left, towards Doddy's head.
        path.addLine(to: CGPoint(x: body.minX + r + 28, y: body.maxY))
        path.addLine(to: CGPoint(x: body.minX + r + 10, y: rect.maxY))
        path.addLine(to: CGPoint(x: body.minX + r + 4, y: body.maxY))
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - r), control: CGPoint(x: body.minX, y: body.maxY))
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addQuadCurve(to: CGPoint(x: body.minX + r, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        path.closeSubpath()
        return path
    }
}

#Preview("Opening, mid-flight") {
    if let drawings = OpeningDrawings.load() {
        OpeningSceneView(
            play: OpeningPlay(
                reducedMotion: false, thenListen: false,
                greeting: OpeningGreeting(headline: "Hey, it's Doddy.", question: "What's up, mate?"),
                drawings: drawings,
                startedAt: Date().addingTimeInterval(-1.2)),
            onFinished: {})
    } else {
        Text("The pose SVGs are not in the bundle.")
    }
}
