import DoddyCore
import SwiftUI

/// The first-launch welcome, "One morning in Warsaw" (ADR-595): five chapters you swipe right to
/// left, one persistent Doddy who hops between them, and the sign-in sheet pinned at the bottom.
///
/// Everything that moves is a function of the live scroll position (`WelcomeFlow`, tested in
/// DoddyCore), so it follows the finger 1:1 and can be grabbed and reversed. The scenes are
/// scripted demonstrations; nothing here saves, sends or signs in anything.
struct WelcomeView: View {
    /// The person is through it: "Try Doddy without an account", the only way on today.
    let finish: () -> Void

    private let provider: SignInProviding = UnconnectedSignIn()
    /// The voice account is created for the voice the person has chosen (ElevenLabs unless they chose otherwise).
    private var voiceProvider: VoiceProvider {
        VoiceProvider.effective(stored: UserDefaults.standard.string(forKey: VoiceProvider.preferenceKey), tokenServerSet: true)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var textBlock: CGFloat = 196

    /// The page position, in pages (0 to 4), measured from the scroll view.
    @State private var progress: Double = 0
    @State private var scrollID: Int? = 0
    /// When each chapter began to appear; a scene plays from there. Far in the past = finished.
    @State private var starts: [Double] = WelcomeView.initialStarts()
    @State private var visible: Set<Int> = [0]
    @State private var arrived = false
    @State private var signInExpanded = false

    private static let dotsHeight: CGFloat = 24
    private static let longAgo: Double = -1_000

    private static func initialStarts() -> [Double] {
        var starts = Array(repeating: longAgo, count: WelcomeChapter.count)
        starts[0] = Date().timeIntervalSinceReferenceDate
        return starts
    }

    var body: some View {
        GeometryReader { geo in
            let below = SignInSheet.collapsedHeight + Self.dotsHeight
            let m = WelcomeMetrics(width: geo.size.width, height: geo.size.height, textBlock: textBlock, below: below)
            let pageHeight = geo.size.height - below
            ZStack(alignment: .topLeading) {
                stage(m)
                pager(m, pageHeight: pageHeight)
                header
                dots(y: pageHeight)
                scrim
                SignInSheet(expanded: $signInExpanded, provider: provider, voiceProvider: voiceProvider,
                            continueWithoutAccount: finish, signedIn: finish)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.root")
        .onAppear {
            guard !arrived else { return }
            if reduceMotion { arrived = true } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.25)) { arrived = true }
            }
        }
        .onChange(of: progress) { _, new in updateVisibility(at: new) }
    }

    // MARK: The persistent stage: light, skyline, ground, Doddy

    private func stage(_ m: WelcomeMetrics) -> some View {
        let k = m.doddyHeight / 255
        let moving = !reduceMotion
        let hop = moving ? WelcomeFlow.hop(progress: progress) : 0
        let tilt = moving ? WelcomeFlow.tilt(progress: progress) : 0
        let skylineX = moving ? CGFloat(WelcomeFlow.skylineOffset(progress: progress, pageWidth: Double(m.width))) : 0
        let groundX = moving ? CGFloat(WelcomeFlow.groundOffset(progress: progress, pageWidth: Double(m.width))) : 0
        return ZStack(alignment: .topLeading) {
            // A warm glow behind him.
            Circle()
                .fill(Theme.orangeCue.opacity(0.18))
                .frame(width: m.doddyHeight * 0.95, height: m.doddyHeight * 0.95)
                .blur(radius: 26)
                .position(x: m.width / 2, y: m.groundY - m.doddyHeight * 0.42)
                .opacity(arrived ? 1 : 0)
            // The Warsaw line drifts slower than the ground (parallax). PLACEHOLDER scenery.
            WarsawLine(scale: k)
                .offset(x: skylineX, y: m.groundY - 130 * k)
            // The ground: one line, with ticks that move 1:1 with the pages so he seems to walk.
            Rectangle().fill(Theme.ink)
                .frame(width: m.width, height: 2)
                .offset(y: m.groundY - 1)
            groundTicks(m, offset: groundX)
            // Doddy.
            ZStack {
                Ellipse().fill(Theme.ink.opacity(0.1))
                    .frame(width: m.doddyWidth * 0.7, height: 9)
                    .scaleEffect(1 - 0.4 * hop)
                    .position(x: m.width / 2, y: m.groundY + 6)
                ZStack {
                    ForEach(WelcomeChapter.allCases) { chapter in
                        CharacterArtImage(assetName: chapter.pose.assetName, height: m.doddyHeight)
                            .opacity(WelcomeFlow.poseOpacity(chapter: chapter.rawValue, progress: progress))
                            .position(x: m.width / 2,
                                      y: m.groundY - CGFloat(chapter.pose.soleFraction) * m.doddyHeight + m.doddyHeight / 2)
                    }
                }
                .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.5, y: m.groundY / max(m.stageHeight, 1)))
                .offset(y: -CGFloat(hop) * 34 * k)
            }
            .offset(x: arrived ? 0 : m.width * 0.5)
            .opacity(arrived ? 1 : 0)
        }
        .frame(width: m.width, height: m.stageHeight + 16, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func groundTicks(_ m: WelcomeMetrics, offset: CGFloat) -> some View {
        let spacing: CGFloat = 72
        let shift = offset.truncatingRemainder(dividingBy: spacing)
        let count = Int(m.width / spacing) + 3
        return ZStack(alignment: .topLeading) {
            ForEach(0..<count, id: \.self) { i in
                Rectangle().fill(Theme.ink.opacity(0.22))
                    .frame(width: 2, height: 5)
                    .offset(x: CGFloat(i) * spacing + shift, y: m.groundY + 10)
            }
        }
    }

    // MARK: Pages

    private func pager(_ m: WelcomeMetrics, pageHeight: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(WelcomeChapter.allCases) { chapter in
                    page(chapter, m, textHeight: pageHeight - m.stageHeight)
                        .frame(width: m.width, height: pageHeight, alignment: .top)
                        .id(chapter.rawValue)
                }
            }
            .scrollTargetLayout()
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.frame(in: .named("welcomePager")).minX, initial: true) { _, x in
                            guard m.width > 0 else { return }
                            progress = WelcomeFlow.clamped(Double(-x / m.width))
                        }
                }
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrollID)
        .coordinateSpace(name: "welcomePager")
        .frame(width: m.width, height: pageHeight)
        .accessibilityIdentifier("welcome.pager")
    }

    private func page(_ chapter: WelcomeChapter, _ m: WelcomeMetrics, textHeight: CGFloat) -> some View {
        let index = chapter.rawValue
        let isVisible = visible.contains(index)
        let textOpacity = WelcomeFlow.textOpacity(chapter: index, progress: progress)
        let slide = reduceMotion ? 0 : CGFloat(WelcomeFlow.textOffset(chapter: index, progress: progress))
        return VStack(spacing: 0) {
            // The scene: a pure function of the time since this chapter began to appear.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isVisible)) { context in
                let elapsed = reduceMotion ? 999 : context.date.timeIntervalSinceReferenceDate - starts[index]
                ZStack(alignment: .topLeading) {
                    if m.showsScene {
                        WelcomeSceneView(chapter: chapter, e: elapsed, m: m)
                    }
                    pigeon(chapter, m, elapsed: context.date.timeIntervalSinceReferenceDate)
                }
                .frame(width: m.width, height: m.stageHeight, alignment: .topLeading)
            }
            .frame(width: m.width, height: m.stageHeight)
            // The words: a label, the title, and what Doddy says.
            ScrollView(.vertical, showsIndicators: false) {
                chapterText(chapter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: max(textHeight, 0), alignment: .top)
            .offset(x: slide)
            .opacity(textOpacity)
        }
    }

    /// The pigeon pecks near the ground line on every page, a different spot each time, and ends beside Doddy.
    private func pigeon(_ chapter: WelcomeChapter, _ m: WelcomeMetrics, elapsed time: Double) -> some View {
        let spots: [(x: CGFloat, facing: PigeonView.Facing)] = [
            (0.77, .left), (0.81, .left), (0.09, .right), (0.80, .left), (0.74, .left),
        ]
        let spot = spots[chapter.rawValue]
        return PigeonView(facing: spot.facing, peck: reduceMotion ? 0 : WelcomeTimeline.peck(time + Double(chapter.rawValue) * 0.9))
            .position(x: m.width * spot.x + 23, y: m.groundY - 17)
    }

    @ViewBuilder private func chapterText(_ chapter: WelcomeChapter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch chapter {
            case .castleSquare:
                label(Text("One morning in Warsaw"))
                title(Text("Hi, I'm Doddy."))
                line(Text("Let's take a walk."))
            case .notes:
                label(Text(verbatim: "18:45"))
                title(Text("My brain has left the chat."))
                line(Text("Your words, not a guess."))
            case .reminder:
                label(Text(verbatim: "22:30"))
                title(Text("Don't let me forget."))
                line(Text("Tomorrow. Morning or evening? Pick one."))
            case .plan:
                label(Text(verbatim: "23:30"))
                title(Text("Sort tomorrow out."))
                line(Text("Three things, one tap. Untick to skip any."))
            case .pocket:
                label(Text("A mate in your pocket"))
                title(Text("One tap away."))
                line(Text("Dynamic Island, Action Button, or a tap on the back."))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome.chapter.\(chapter.rawValue)")
    }

    private func label(_ text: Text) -> some View {
        text.font(.footnote.weight(.semibold)).tracking(0.6).textCase(.uppercase).foregroundStyle(Theme.secondaryText)
    }

    private func title(_ text: Text) -> some View {
        text.font(.largeTitle.weight(.bold)).tracking(-0.7)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func line(_ text: Text) -> some View {
        text.font(Theme.hand(.title2)).padding(.top, 4)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Header, dots, scrim

    private var header: some View {
        HStack {
            DoddyWordmark()
            Spacer()
            if WelcomeFlow.page(at: progress) < WelcomeFlow.lastPage {
                Button {
                    go(to: WelcomeFlow.lastPage)
                } label: {
                    Text("Skip").font(.body.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcome.skip")
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func dots(y pageHeight: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<WelcomeChapter.count, id: \.self) { i in
                let on = WelcomeFlow.page(at: progress) == i
                Capsule()
                    .fill(on ? Theme.ink : Theme.ink.opacity(0.22))
                    .frame(width: on ? 20 : 7, height: 7)
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1), value: on)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.dotsHeight)
        .offset(y: pageHeight)
        .accessibilityHidden(true)
    }

    /// Dims the welcome while the sign-in sheet is open; a tap on it closes the sheet.
    private var scrim: some View {
        Color.black.opacity(0.34 * (signInExpanded ? 1 : 0))
            .ignoresSafeArea()
            .allowsHitTesting(signInExpanded)
            .onTapGesture { signInExpanded = false }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: signInExpanded)
            .accessibilityHidden(true)
    }

    // MARK: Actions

    private func go(to page: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 1)) { scrollID = page }
    }

    /// A chapter's scene starts the moment its page begins to slide in, and resets once it has gone.
    private func updateVisibility(at position: Double) {
        for index in 0..<WelcomeChapter.count {
            let showing = abs(Double(index) - position) < 1
            if showing, !visible.contains(index) {
                starts[index] = Date().timeIntervalSinceReferenceDate
                visible.insert(index)
            } else if !showing, visible.contains(index) {
                visible.remove(index)
                starts[index] = Self.longAgo
            }
        }
    }
}
