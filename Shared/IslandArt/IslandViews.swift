import SwiftUI

// SwiftUI for the owner's V4 island boards (ADR-238, ADR-239). Shared by the widget extension,
// which puts these pieces into the Dynamic Island's regions, and the app's Settings preview,
// which lays the same pieces out in a black capsule. Sizes and colours are the boards'
// (Design-notes.md, "Shared visual system"); text is the system font, not the boards' Arial.

extension Color {
    init(islandHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    static let islandCream = Color(islandHex: IslandColor.cream)
    static let islandBlack = Color(islandHex: IslandColor.black)
    static let islandOrange = Color(islandHex: IslandColor.orange)
    static let islandSecondary = Color(islandHex: IslandColor.secondary)
    static let islandPill = Color(islandHex: IslandColor.pill)
    /// "Waiting for you" (Confirm in Doddy), as on the earlier island.
    static let islandAccent = Color(red: 0xFF / 255, green: 0xB5 / 255, blue: 0x6B / 255)
}

/// Draws an `IslandArt` at one point per unit, scaled down to fit `maxSize` if given.
struct IslandArtView: View {
    let art: IslandArt
    var face: IslandFace?
    let live: Bool
    var showsHands = true
    var maxSize: CGSize?
    /// Words the board draws on its shapes (Language Bridge's bubbles), in its own units.
    var labels: [IslandArtLabel] = []

    private var scale: CGFloat {
        guard let maxSize else { return 1 }
        return min(1, maxSize.width / CGFloat(art.viewBox.width), maxSize.height / CGFloat(art.viewBox.height))
    }

    var body: some View {
        let primitives = art.primitives(face: face, live: live, showsHands: showsHands)
        let k = scale
        ZStack(alignment: .topLeading) {
            ForEach(primitives.indices, id: \.self) { i in
                let p = primitives[i]
                let shape = IslandShape(primitive: p, viewBox: art.viewBox)
                if let fill = p.paint.fill {
                    shape.fill(Color(islandHex: fill))
                }
                if let stroke = p.paint.stroke, p.paint.width > 0 {
                    shape.stroke(Color(islandHex: stroke), style: StrokeStyle(
                        lineWidth: CGFloat(p.paint.width * p.scale) * k, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(labels.indices, id: \.self) { i in
                let label = labels[i]
                Text(label.text)
                    .font(.system(size: CGFloat(label.size) * k, weight: .bold))
                    .foregroundStyle(Color.islandBlack)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 26 * k)
                    .position(x: CGFloat(label.x - art.viewBox.x) * k, y: CGFloat(label.y - art.viewBox.y) * k)
            }
        }
        .frame(width: CGFloat(art.viewBox.width) * k, height: CGFloat(art.viewBox.height) * k)
        .accessibilityHidden(true)
    }
}

/// One primitive, mapped from the art's view box into the frame.
struct IslandShape: Shape {
    let primitive: IslandPrimitive
    let viewBox: IslandRect

    func path(in rect: CGRect) -> Path {
        let k = rect.width / CGFloat(viewBox.width)
        let p = primitive
        // Frame ← view box ← primitive's own placement.
        let transform = CGAffineTransform(translationX: rect.minX + CGFloat(p.x - viewBox.x) * k,
                                          y: rect.minY + CGFloat(p.y - viewBox.y) * k)
            .scaledBy(x: CGFloat(p.scale) * k, y: CGFloat(p.scale) * k)
        var path = Path()
        switch p.geometry {
        case .ellipse(let cx, let cy, let rx, let ry):
            path.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        case .rect(let x, let y, let w, let h, let r):
            path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: r, height: r))
        case .path(let commands):
            for c in commands {
                switch c {
                case .move(let x, let y): path.move(to: CGPoint(x: x, y: y))
                case .line(let x, let y): path.addLine(to: CGPoint(x: x, y: y))
                case .quad(let cx, let cy, let x, let y):
                    path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
                case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                    path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
                case .close: path.closeSubpath()
                }
            }
        }
        return path.applying(transform)
    }
}

/// Time left until `end`, ticking without app updates; stops at 0:00.
struct IslandCountdownText: View {
    let end: Date

    var body: some View {
        Text(timerInterval: Date()...max(end, Date()), countsDown: true)
            .monospacedDigit()
    }
}

/// The running conversation time, ticking without app updates.
struct IslandElapsedText: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
    }
}

/// "VOICE" (or the moment's label) beside the camera, and an orange "● LIVE" while Doddy can
/// hear you (the owner asked to see that it is live; not on the boards).
struct IslandLabelView: View {
    let scene: IslandScene

    var body: some View {
        HStack(spacing: 5) {
            IslandText(scene.label)
                .foregroundStyle(Color.islandSecondary)
            if scene.live {
                HStack(spacing: 3) {
                    Circle().fill(Color.islandOrange).frame(width: 5, height: 5)
                    IslandText("LIVE").foregroundStyle(Color.islandOrange)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live, Doddy can hear you")
            }
        }
        .font(.system(size: 9.5, weight: .semibold))
        .tracking(1.1)
        .lineLimit(1)
    }
}

/// The top-right slot: the running time or a short status ("Saved", "2 / 3").
struct IslandTimeView: View {
    let scene: IslandScene
    let startedAt: Date

    var body: some View {
        Group {
            switch scene.time {
            case .elapsed: IslandElapsedText(startedAt: startedAt)
            case .countdown(let end): IslandCountdownText(end: end)
            case .text(let text): IslandText(text)
            }
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(Color.islandSecondary)
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .frame(maxWidth: 72, alignment: .trailing)
    }
}

/// Voice bars, dots, a symbol, a short text or a check, at the boards' three sizes.
struct IslandSignView: View {
    let sign: IslandSign
    let presentation: IslandPresentation
    let live: Bool
    let startedAt: Date

    var body: some View {
        switch sign {
        case .none:
            EmptyView()
        case .bars:
            bars
        case .dots:
            let s: CGFloat = presentation == .minimal ? 0.7 : 1
            HStack(spacing: 3.5 * s) {
                Circle().fill(Color.islandSecondary).frame(width: 3 * s, height: 3 * s)
                Circle().fill(live ? Color.islandOrange : Color.islandSecondary).frame(width: 4 * s, height: 4 * s)
                Circle().fill(Color.islandSecondary).frame(width: 3 * s, height: 3 * s)
            }
            .accessibilityHidden(true)
        case .symbol(let name, let tint):
            Image(systemName: name)
                .font(presentation == .expanded ? .body : .caption)
                .foregroundStyle(color(tint))
        case .text(let text):
            IslandText(text)
                .font(.system(size: presentation == .minimal ? 12 : 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
                .foregroundStyle(presentation == .minimal && live ? Color.islandOrange : Color.islandCream)
        case .elapsed:
            IslandElapsedText(startedAt: startedAt)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Color.islandCream)
                .frame(maxWidth: 44)
        case .countdown(let end):
            IslandCountdownText(end: end)
                .font(.system(size: presentation == .minimal ? 10 : 12.5, weight: .bold))
                .foregroundStyle(Color.islandCream)
                .multilineTextAlignment(.center)
                .frame(maxWidth: presentation == .minimal ? 36 : 44)
        case .check:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(live ? Color.islandOrange : Color.islandSecondary)
        }
    }

    private func color(_ tint: IslandTint) -> Color {
        switch tint {
        case .secondary: .islandSecondary
        case .accent: .islandAccent
        case .warning: .yellow
        case .orange: live ? .islandOrange : .islandSecondary
        }
    }

    /// The boards' bar heights: seven (expanded), five (compact), three (minimal). A fixed
    /// sign shown only while Doddy can hear you; it does not follow the microphone level.
    private var bars: some View {
        let heights: [CGFloat]
        let centre: Int
        let width: CGFloat
        let gap: CGFloat
        let plain: Color
        switch presentation {
        case .expanded: heights = [4, 7, 11, 18, 10, 6, 3]; centre = 3; width = 2.2; gap = 2.8; plain = .islandSecondary
        case .compact: heights = [6, 11, 17, 9, 5]; centre = 2; width = 2.5; gap = 2.5; plain = .islandCream
        case .minimal: heights = [5, 13, 7]; centre = 1; width = 2; gap = 2; plain = .islandSecondary
        }
        return HStack(alignment: .center, spacing: gap) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule()
                    .fill(i == centre && live ? Color.islandOrange : plain)
                    .frame(width: width, height: heights[i])
            }
        }
        .accessibilityHidden(true)
    }
}

/// The boards' 34 pt pill: dark fill and cream label, or cream fill for the main action.
/// When three pills and a sign don't fit beside Doddy, the pills drop their symbols (as the
/// Figma island's "Wycisz" and "Zakończ") instead of cutting their words to "U…" (ADR-615).
struct IslandPillLabel: View {
    let title: String
    let systemImage: String
    var prominent = false

    /// Words a pill keeps as they are in every language: "Stop" fits beside Doddy where
    /// "Zatrzymaj" didn't (owner, 24 Oct 2026, ADR-617). The Lock Screen's End is still translated.
    static let keptAsIs: Set<String> = ["Stop"]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
                word
            }
            word
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
        .foregroundStyle(prominent ? Color.islandBlack : Color.islandCream)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(prominent ? Color.islandCream : Color.islandPill, in: Capsule())
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var word: some View {
        if Self.keptAsIs.contains(title) {
            Text(verbatim: title)
        } else {
            IslandText(title)
        }
    }
}

/// The expanded island under the camera: the board's drawing, status, buttons and sign.
/// Editorial is typography-led: big status on the left, small Doddy and buttons on the right.
struct IslandBottomView<Controls: View>: View {
    let scene: IslandScene
    let startedAt: Date
    @ViewBuilder let controls: () -> Controls
    @Environment(\.islandLanguage) private var language

    /// What iOS leaves for the expanded island's bottom region is about 110 pt (measured on the
    /// native screenshot); everything here stays within it, so nothing is cut (ADR-615).
    static var fitsHeight: CGFloat { 110 }
    static var figureHeight: CGFloat { 104 }
    static var waveBand: CGFloat { 24 }

    var body: some View {
        if scene.board == .editorial {
            editorial
        } else {
            standard
        }
    }

    @ViewBuilder
    private var title: some View {
        switch scene.bigTitle {
        case .countdown(let end):
            // Tiny Promise: the time left is the status, in 32 pt numerals.
            IslandCountdownText(end: end)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.islandCream)
                .lineLimit(1)
                .accessibilityLabel(Text(verbatim: IslandLanguage.text(scene.title, language)))
        case .bigText(let text):
            IslandText(text)
                .font(.system(size: 32, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.islandCream)
                .lineLimit(1)
                .accessibilityLabel(Text(verbatim: IslandLanguage.text(scene.title, language)))
        case .text(let text):
            IslandText(text).font(.system(size: 21, weight: .medium)).foregroundStyle(Color.islandCream).lineLimit(1)
        case nil:
            IslandText(scene.title)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Color.islandCream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var subtitle: some View {
        IslandText(scene.subtitle)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(scene.subtitleIsWarning ? Color.yellow : Color.islandSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var standard: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let pose = scene.pose {
                    // Whole Doddy at his largest the island allows (owner, 22 Oct, ADR-596), with a
                    // 1.5 pt cream edge and a faint light, so his black lines read on the black
                    // island (ADR-615). 104 pt: iOS gives the expanded island's bottom region about
                    // 110 pt, and at 118 it cut his shoes off (native screenshot, run 40083307695).
                    IslandPoseView(pose: pose, maxSize: CGSize(width: 82, height: Self.figureHeight), edgeWidth: 1.5)
                        .background { IslandDoddyLight() }
                } else {
                    IslandArtView(art: scene.art(.expanded), face: scene.face, live: scene.live,
                                  showsHands: scene.showsHands, maxSize: CGSize(width: 82, height: 92),
                                  labels: scene.artLabels)
                }
            }
            .frame(width: 82)
            VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    subtitle
                }
                .accessibilityElement(children: .combine)
                // ADR-596: his waves sit under what he is doing, in one 24 pt band: a calm line
                // while he hears you; while he talks a livelier one that starts beside him
                // (owner, 24 Oct: not across the whole island, ADR-615).
                if scene.waves == .listening {
                    IslandWavesView(kind: .line, live: scene.live)
                        .frame(height: Self.waveBand)
                } else if scene.waves == .speaking {
                    IslandWavesView(kind: .speech, live: scene.live)
                        .frame(height: Self.waveBand)
                        .padding(.leading, -6)
                }
                HStack(spacing: 8) {
                    controls()
                    if scene.waves == .none {
                        IslandSignView(sign: scene.expandedSign, presentation: .expanded, live: scene.live, startedAt: startedAt)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Board E: 29 pt status, an orange caret line while live, Doddy at 25 pt top right.
    private var editorial: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    IslandText(scene.title)
                        .font(.system(size: 29, weight: .medium))
                        .tracking(-1.2)
                        .foregroundStyle(Color.islandCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    subtitle
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: 8) {
                    Capsule()
                        .fill(scene.live ? Color.islandOrange : Color.islandSecondary)
                        .frame(width: 1.7, height: 14)
                    IslandText(scene.live ? islandWord("Doddy can hear you") : " ")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.islandSecondary)
                }
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 10) {
                IslandArtView(art: Self.editorialFace, face: scene.face ?? .listening, live: scene.live)
                controls()
            }
        }
    }

    /// The editorial board's face: translate(330 74) scale(0.625), drawn on its own.
    private static var editorialFace: IslandArt {
        IslandArt(viewBox: IslandRect(x: -13.5, y: -13.5, width: 27, height: 27),
                  elements: [.face(x: 0, y: 0, scale: 0.625, .listening)])
    }
}

struct IslandCompactLeadingView: View {
    let scene: IslandScene
    @Environment(\.islandLanguage) private var language

    var body: some View {
        Group {
            if let pose = scene.pose {
                // Only his head (owner, 24 Oct, ADR-615): the whole of him at 30 pt was a few
                // hairlines. The expanded island shows all of him.
                IslandPoseFaceView(pose: pose, size: 26)
            } else {
                IslandArtView(art: scene.art(.compact), face: scene.face, live: scene.live, showsHands: scene.showsHands)
            }
        }
        // The drawings are hidden from VoiceOver, so the compact island says what Doddy is doing
        // ("Listening", "Muted"), the same status the expanded island and Lock Screen show.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: IslandLanguage.text(scene.title, language)))
    }
}

struct IslandCompactTrailingView: View {
    let scene: IslandScene
    let startedAt: Date

    var body: some View {
        // ADR-596: his waves while he hears you or talks; the sign otherwise.
        if scene.waves != .none {
            IslandWavesView(kind: .line, live: scene.live)
                .frame(width: 42, height: 22)
        } else {
            IslandSignView(sign: scene.compactSign, presentation: .compact, live: scene.live, startedAt: startedAt)
        }
    }
}

/// Minimal (another app's activity is also running): the board's 45 pt drawing with the sign
/// over its right side.
struct IslandMinimalView: View {
    let scene: IslandScene
    let startedAt: Date

    private static func isText(_ sign: IslandSign) -> Bool {
        if case .text = sign { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: scene.minimalSignCentred ? .center : .trailing) {
            if let pose = scene.pose {
                IslandPoseFaceView(pose: pose, size: 24)
                    .padding(.leading, 4)
                    .frame(width: 45, alignment: .leading)
            } else {
                IslandArtView(art: scene.art(.minimal), face: scene.face, live: scene.live, showsHands: false)
            }
            IslandSignView(sign: scene.minimalSign, presentation: .minimal, live: scene.live, startedAt: startedAt)
                // A language code ("EN") needs more than the bars' 16 pt, or it breaks into two lines.
                .frame(width: scene.minimalSignCentred ? 36 : (Self.isText(scene.minimalSign) ? 22 : 16))
                .padding(.trailing, scene.minimalSignCentred ? 0 : 2)
        }
    }
}

/// Whole Doddy (ADR-264): the pose standing on the bottom of `maxSize`, as large as fits. The
/// owner's drawings have black outlines, so on the black island they get a 1 pt cream edge;
/// the pictures themselves are unchanged.
struct IslandPoseView: View {
    let pose: IslandPose
    let maxSize: CGSize
    /// The cream edge for black backgrounds; off on the cream Lock Screen card.
    var edged = true
    /// The edge's width; the expanded island's is 1.5 pt and round (ADR-615).
    var edgeWidth: CGFloat = 1

    var body: some View {
        IslandFigureView(assetName: pose.assetName, figure: pose.figure, maxSize: maxSize, edged: edged,
                         edgeWidth: edgeWidth)
    }
}

/// A 2:3 picture from the owner's pack cropped to its figure box and standing on the bottom of
/// `maxSize`, as large as fits. Used for the poses and for the voice screen's talking frames
/// (ADR-299), which share one box so Doddy doesn't jump between frames.
struct IslandFigureView: View {
    let assetName: String
    let figure: IslandRect
    let maxSize: CGSize
    var edged = true
    /// Up to 1 pt: the four-shadow edge. Wider: a round edge of sixteen cream copies of the
    /// picture's shape, which has no gaps on the diagonals (ADR-615).
    var edgeWidth: CGFloat = 1

    var body: some View {
        if edged, edgeWidth > 1 {
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    let angle = Double(i) * .pi / 8
                    picture(.template)
                        .foregroundStyle(Color.islandCream)
                        .offset(x: edgeWidth * CGFloat(cos(angle)), y: edgeWidth * CGFloat(sin(angle)))
                }
                picture(.original)
            }
            .frame(width: maxSize.width, height: maxSize.height, alignment: .bottom)
            .accessibilityHidden(true)
        } else {
            picture(.original)
                .islandCreamEdge(edged)
                .frame(width: maxSize.width, height: maxSize.height, alignment: .bottom)
                .accessibilityHidden(true)
        }
    }

    /// The picture cropped to the figure box; `.template` draws only its shape.
    private func picture(_ mode: Image.TemplateRenderingMode) -> some View {
        let box = figure
        // Picture width (points) so the figure fits; the picture is 2:3.
        let width = min(maxSize.width / CGFloat(box.width), maxSize.height / (CGFloat(box.height) * 1.5))
        let height = width * 1.5
        return Image(assetName)
            .renderingMode(mode)
            .resizable()
            .frame(width: width, height: height)
            .offset(x: -CGFloat(box.x) * width, y: -CGFloat(box.y) * height)
            .frame(width: CGFloat(box.width) * width, height: CGFloat(box.height) * height, alignment: .topLeading)
    }
}

/// Whole Doddy's face for compact and minimal: a circle cropped from the pose's face pose.
struct IslandPoseFaceView: View {
    let pose: IslandPose
    let size: CGFloat

    var body: some View {
        let face = pose.facePose
        let head = face.head ?? (x: 0.5, y: 0.3, diameter: 0.5)
        let width = size / CGFloat(head.diameter * 1.06)
        let height = width * 1.5
        Image(face.assetName)
            .resizable()
            .frame(width: width, height: height)
            .offset(x: size / 2 - CGFloat(head.x) * width, y: size / 2 - CGFloat(head.y) * height)
            .frame(width: size, height: size, alignment: .topLeading)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// A faint light behind Whole Doddy on the expanded island, after the Figma island's
/// "Światło za Doddym" (frame "A 2 · Słucham", file `yqoQlkN6BpevFGW3ySnNJU`) but at a fifth of
/// its strength: the owner didn't want him lit up (24 Oct, ADR-615). His 1.5 pt cream edge is
/// what makes his black lines read on black; the light only lifts him off the island a little.
struct IslandDoddyLight: View {
    static let peak = 0.2
    /// Fades out smoothly (a smoothstep) to nothing at the edge of a 110 x 120 pt ellipse.
    static let stops: [Gradient.Stop] = [
        .init(color: .islandCream.opacity(peak), location: 0),
        .init(color: .islandCream.opacity(peak * 0.84), location: 0.25),
        .init(color: .islandCream.opacity(peak * 0.5), location: 0.5),
        .init(color: .islandCream.opacity(peak * 0.16), location: 0.75),
        .init(color: .islandCream.opacity(0), location: 1),
    ]

    var body: some View {
        EllipticalGradient(stops: Self.stops, center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: 110, height: 120)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A 1 pt cream edge around a picture's opaque pixels, so black outlines read on black.
    func islandCreamEdge(_ on: Bool = true) -> some View {
        let edge = on ? Color.islandCream : .clear
        return shadow(color: edge, radius: 0, x: 1, y: 0)
            .shadow(color: edge, radius: 0, x: -1, y: 0)
            .shadow(color: edge, radius: 0, x: 0, y: 1)
            .shadow(color: edge, radius: 0, x: 0, y: -1)
    }
}
