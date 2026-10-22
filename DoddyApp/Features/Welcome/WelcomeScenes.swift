import DoddyCore
import SwiftUI
import UIKit

// The five scenes of the welcome (ADR-579). Each is a SCRIPTED DEMONSTRATION: nothing is saved,
// reminded, sent or looked up, and every card says "Example". A scene is a pure function of `e`,
// the seconds since its chapter began to appear (`WelcomeTimeline`), so a swipe can end it at any
// moment. A scene that is not on screen is drawn in its final state (`e` is large).

/// Where the layers of the welcome agree they are, in points, inside the region above the sheet.
struct WelcomeMetrics: Equatable {
    var width: CGFloat
    /// The top part of each page, where the scene and Doddy live. The ground line is its bottom edge.
    var stageHeight: CGFloat
    var doddyHeight: CGFloat

    var doddyWidth: CGFloat { doddyHeight * 2 / 3 }
    var groundY: CGFloat { stageHeight }
    /// The highest his picture's ink reaches (the tallest pose), from the top of the region.
    var figureTop: CGFloat { groundY - doddyHeight * 0.86 }
    /// Free room between the wordmark row and the top of his head, for a card.
    var sceneRoom: CGFloat { figureTop - Self.sceneTop - 8 }
    var showsScene: Bool { sceneRoom >= 110 }

    /// Below the wordmark and Skip row.
    static let sceneTop: CGFloat = 56

    init(width: CGFloat, height: CGFloat, textBlock: CGFloat, below: CGFloat) {
        self.width = width
        let room = height - textBlock - below
        stageHeight = min(max(room, height * 0.30), height)
        doddyHeight = min(255, stageHeight * 0.6)
    }
}

/// The scene for a chapter.
struct WelcomeSceneView: View {
    let chapter: WelcomeChapter
    let e: Double
    let m: WelcomeMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch chapter {
            case .castleSquare: CastleScene(e: e, m: m)
            case .notes: NotesScene(e: e, m: m)
            case .reminder: ReminderScene(e: e, m: m)
            case .plan: PlanScene(e: e, m: m)
            case .pocket: PocketScene(e: e, m: m)
            }
        }
        .frame(width: m.width, height: m.stageHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// MARK: Pieces

private func appear(_ e: Double, _ start: Double, _ duration: Double = 0.5) -> Double {
    WelcomeTimeline.easeOut(WelcomeTimeline.fraction(e, start: start, duration: duration))
}

/// Text that types itself, with its final size reserved so nothing moves while it types.
private struct TypedText: View {
    let full: String
    let e: Double
    let start: Double
    let duration: Double
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: full).font(font).opacity(0)
            Text(verbatim: WelcomeTimeline.typed(full, elapsed: e, start: start, duration: duration)).font(font)
        }
    }
}

private struct ExampleTag: View {
    var body: some View {
        Text("Example")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.separator.opacity(0.5)))
    }
}

/// A scene card: soft paper, a shadow, and the honest "Example" tag above it.
private struct WelcomeCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ExampleTag().padding(.trailing, 4)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.quietSurface))
            .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 6)
        }
        .padding(.horizontal, 28)
        .padding(.top, WelcomeMetrics.sceneTop - 22)
    }
}

private struct Eyebrow: View {
    let text: Text

    var body: some View {
        text
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.secondaryText)
    }
}

private struct MicGlyph: View {
    var body: some View {
        Image(systemName: "mic.fill")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
    }
}

// MARK: 1. Castle Square

private struct CastleScene: View {
    let e: Double
    let m: WelcomeMetrics

    var body: some View {
        let pop = appear(e, 1.2, 0.6)
        ZStack(alignment: .topLeading) {
            // The greeting is Polish in every language: it is what Warsaw says, not a translation.
            Text(verbatim: WelcomeTimeline.typed("Dzień dobry!", elapsed: e, start: 0.3, duration: 0.9))
                .font(Theme.hand(.largeTitle))
                .rotationEffect(.degrees(-4), anchor: .bottomLeading)
                .padding(.leading, 28)
                .padding(.top, WelcomeMetrics.sceneTop + 14)
            Text("hi!")
                .font(Theme.hand(.largeTitle))
                .scaleEffect(0.6 + 0.4 * pop, anchor: .bottomLeading)
                .opacity(pop)
                .rotationEffect(.degrees(-6))
                .position(x: m.width / 2 + m.doddyWidth * 0.55, y: m.groundY - m.doddyHeight * 0.752 - 30)
        }
    }
}

// MARK: 2. Notes

private struct NotesScene: View {
    let e: Double
    let m: WelcomeMetrics

    var body: some View {
        let card = appear(e, 0.15, 0.5)
        ZStack(alignment: .topLeading) {
            WelcomeCard {
                Eyebrow(text: Text("Found in your notes"))
                TypedText(
                    full: NSLocalizedString("Italian place for Ola's birthday: Trattoria Nonna, Hoża 9.", comment: ""),
                    e: e, start: 0.5, duration: 1.7)
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.caption)
                    Text("Saved 4 Oct · your typed note").font(.footnote)
                }
                .foregroundStyle(Theme.secondaryText)
                .opacity(appear(e, 1.7, 0.4))
            }
            .offset(y: CGFloat((1 - card) * -20))
            .opacity(card)

            scraps
        }
    }

    /// Three loose scraps drift between the card and his head: the things that vanish.
    @ViewBuilder private var scraps: some View {
        let top = WelcomeMetrics.sceneTop + 150
        let bottom = m.groundY - m.doddyHeight * 0.362 - 16
        if bottom - top > 50 {
            let span = bottom - top
            Group {
                scrap(Text("Marta's book"), x: 100, y: top + span * 0.35, tilt: -6, phase: 0)
                scrap(Text("Locker 4471"), x: m.width - 100, y: top + span * 0.05, tilt: 5, phase: 1.4)
                scrap(Text("Parked on B2"), x: m.width - 96, y: top + span * 0.70, tilt: -3, phase: 2.6)
            }
        }
    }

    private func scrap(_ text: Text, x: CGFloat, y: CGFloat, tilt: Double, phase: Double) -> some View {
        text
            .font(Theme.hand(.title3))
            .foregroundStyle(Theme.ink.opacity(0.42))
            .rotationEffect(.degrees(tilt))
            .position(x: x, y: y + CGFloat(sin(e * 1.5 + phase) * 4))
    }
}

// MARK: 3. Reminder

private struct ReminderScene: View {
    let e: Double
    let m: WelcomeMetrics

    var body: some View {
        let card = appear(e, 0.15, 0.5)
        let chosen = e >= 2.9
        WelcomeCard {
            Eyebrow(text: Text("Reminder"))
            HStack(spacing: 8) {
                MicGlyph()
                TypedText(full: NSLocalizedString("Remind me to call Mum tomorrow.", comment: ""), e: e, start: 0.5, duration: 1.3)
            }
            HStack(spacing: 8) {
                chip(Text("Morning, 10:00"), selected: false, dimmed: chosen, shownAt: 2.0)
                chip(Text("Evening, 19:00"), selected: chosen, dimmed: false, shownAt: 2.2)
            }
            HStack(spacing: 6) {
                Circle().fill(Theme.orangeCue).frame(width: 18, height: 18)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ink))
                Text("Added to Reminders · read back 22:31").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .opacity(appear(e, 3.1, 0.4))
        }
        .offset(y: CGFloat((1 - card) * -20))
        .opacity(card)
    }

    private func chip(_ label: Text, selected: Bool, dimmed: Bool, shownAt: Double) -> some View {
        let pop = appear(e, shownAt, 0.4)
        return HStack(spacing: 5) {
            if selected { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
            label.font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(selected ? Theme.canvas : Theme.ink)
        .background(Capsule().fill(selected ? Theme.ink : Theme.separator.opacity(0.5)))
        .opacity(pop * (dimmed ? 0.35 : 1))
        .scaleEffect(0.8 + 0.2 * pop)
    }
}

// MARK: 4. Plan

private struct PlanScene: View {
    let e: Double
    let m: WelcomeMetrics

    private static let tickTimes: [Double] = [0.8, 1.1, 1.4]

    var body: some View {
        let card = appear(e, 0.15, 0.5)
        let ticked = Self.tickTimes.filter { e >= $0 }.count
        WelcomeCard {
            HStack {
                Eyebrow(text: Text("Tomorrow, if you say so"))
                Spacer(minLength: 8)
                doThese
            }
            row(Text("Leave for the dentist"), Text("Reminder · 12:00"), at: Self.tickTimes[0])
            row(Text("Lunch with Alex"), Text("Calendar · Thu 13:00"), at: Self.tickTimes[1])
            row(Text("Bread for the weekend"), Text("List"), at: Self.tickTimes[2])
        }
        .offset(y: CGFloat((1 - card) * -20))
        .opacity(card)
        .onChange(of: ticked) { old, new in
            // A soft tick as each row ticks, only while the scene plays (not when it resets).
            if new > old && e < 4 { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
    }

    /// "Do these (3)", tapped, then "3 done".
    private var doThese: some View {
        let swap = appear(e, 2.5, 0.3)
        let ripple = WelcomeTimeline.fraction(e, start: 2.3, duration: 0.7)
        return ZStack {
            Text("Do these (3)").opacity(1 - swap)
            Text("3 done").opacity(swap)
            Circle().fill(Theme.canvas.opacity(0.5 * (1 - ripple) * (ripple > 0 ? 1 : 0)))
                .frame(width: 40, height: 40).scaleEffect(0.4 + 1.4 * ripple)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.canvas)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(Theme.ink))
    }

    private func row(_ title: Text, _ detail: Text, at start: Double) -> some View {
        let t = appear(e, start, 0.3)
        return HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Theme.ink.opacity(0.3 * (1 - t)), lineWidth: 1.5)
                Circle().fill(Theme.orangeCue).scaleEffect(t).opacity(t)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ink).opacity(t)
            }
            .frame(width: 18, height: 18)
            title.font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            detail.font(.footnote).foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: 5. Pocket

private struct PocketScene: View {
    let e: Double
    let m: WelcomeMetrics

    var body: some View {
        let grow = appear(e, 0.5, 0.9)
        let content = appear(e, 1.05, 0.35)
        let fullWidth: CGFloat = min(300, m.width - 56)
        let width: CGFloat = 126 + (fullWidth - 126) * CGFloat(grow)
        let height: CGFloat = 37 + 29 * CGFloat(grow)
        ZStack(alignment: .top) {
            // The Dynamic Island's shape, stretching into Doddy's Live Activity.
            Capsule().fill(Color.black)
                .frame(width: width, height: height)
                .overlay {
                    HStack(spacing: 12) {
                        Image(decorative: "WholeDoddy_listening")
                            .resizable()
                            .frame(width: 72, height: 108)
                            .frame(width: 42, height: 42, alignment: .top)
                            .background(Theme.canvas)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Doddy").font(.subheadline.weight(.semibold))
                            Text("Listening").font(.caption).opacity(0.65)
                        }
                        .foregroundStyle(.white)
                        Spacer(minLength: 4)
                        bars
                    }
                    .padding(.leading, 12).padding(.trailing, 18)
                    .frame(width: fullWidth)
                    .opacity(content)
                }
                .clipShape(Capsule())
                .padding(.top, WelcomeMetrics.sceneTop - 44)
            Text("wherever you are")
                .font(Theme.hand(.title3))
                .opacity(appear(e, 1.6, 0.5))
                .padding(.top, WelcomeMetrics.sceneTop + 56)
        }
        .frame(width: m.width)
    }

    private var bars: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(Theme.orangeCue)
                    .frame(width: 3, height: 4 + 16 * abs(sin(e * 7 + Double(i) * 0.9)))
            }
        }
        .frame(height: 20)
    }
}
