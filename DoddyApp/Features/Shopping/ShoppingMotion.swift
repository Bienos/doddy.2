import DoddyCore
import SwiftUI

// How the Shopping screens move (owner, 13 Nov 2026: "graficznie i animacyjnie, kreatywnie, ale tak, żeby to było
// łatwe do ogarnięcia"). Each piece is a modifier or a style, so the screens only call it (`ShoppingHubView` and
// `DealsView` change by a few lines; other pull requests redraw those two files). Brand Guidelines V2.2 p.31:
// motion animates a reason and settles with restraint; nothing here loops or plays while idle. Under Reduce Motion
// nothing slides, springs or scales: a change is instant, or at most a short fade.

enum ShoppingMotion {
    /// A change the person made (a tab, the route chip, a chip picked): a short spring, or none under Reduce Motion.
    static func change(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.32)
    }
}

extension View {
    /// Rows that arrive one after another (`ArrivesInOrder`).
    func arrivesInOrder(_ order: Int) -> some View { modifier(ArrivesInOrder(order: order)) }

    /// The Shopping field's frame: a magnifying glass, the cream fill and an orange edge while typing
    /// (`ShoppingFieldChrome`).
    func shoppingFieldChrome(focused: Bool) -> some View { modifier(ShoppingFieldChrome(focused: focused)) }

    /// Keeps `shown` (what the route chip says) following `place` once the words have settled (`RouteSettling`).
    func settlesRoute(_ place: ShoppingRoute.Place, typing: Bool, shown: Binding<ShoppingRoute.Place>) -> some View {
        modifier(RouteSettling(place: place, typing: typing, shown: shown))
    }

    /// Chips picked or put back: a short spring and a light selection tick (`ChoiceMotion`).
    func choiceMotion<Value: Equatable>(_ value: Value) -> some View { modifier(ChoiceMotion(value: value)) }

    /// A leaflet check starting or answering: its cards fade (`PhaseMotion`).
    func leafletPhaseMotion(_ phase: DealsModel.Phase) -> some View { modifier(PhaseMotion(phase: phase)) }
}

// MARK: Rows that arrive one after another

/// A row fades in and rises a few points once, a little after the one before it (at most eight steps of delay).
/// Under Reduce Motion it only fades, all at once.
private struct ArrivesInOrder: ViewModifier {
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 10)
            .onAppear {
                guard !arrived else { return }
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2)) { arrived = true }
                } else {
                    withAnimation(.easeOut(duration: 0.32).delay(Double(min(order, 8)) * 0.045)) { arrived = true }
                }
            }
    }
}

// MARK: The field

/// The one field's frame: cream, round, a magnifying glass at its first line, and an orange edge while typing (the
/// caret and the keyboard say it too, so the colour is never the only sign). The glass sits in an overlay, so the
/// text field stays the element its identifier names.
private struct ShoppingFieldChrome: ViewModifier {
    let focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var glass: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
            .padding(.leading, 12 + glass + 8)
            .padding(.trailing, 12)
            .overlay(alignment: .topLeading) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(focused ? Theme.accentText : Theme.secondaryText)
                    .frame(width: glass)
                    .padding(.leading, 12)
                    .padding(.top, 13)
                    .accessibilityHidden(true)
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.canvas))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focused ? Theme.orangeCue : Theme.separator, lineWidth: focused ? 2 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: focused)
    }
}

// MARK: Where the words go

/// The route chip follows the words once they have rested for a moment while typing (0.4 s), so it doesn't flicker
/// on every key; a pick under "Change", a list filled in, a cleared field or a closed keyboard show at once. The
/// Shopping screen's button waits for the chip (`canGo`), so the card always says where the words go before the tap.
private struct RouteSettling: ViewModifier {
    let place: ShoppingRoute.Place
    let typing: Bool
    @Binding var shown: ShoppingRoute.Place
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .task(id: place) { await settle(place) }
            .onChange(of: typing) { _, now in
                guard !now, shown != place else { return }
                withAnimation(ShoppingMotion.change(reduceMotion)) { shown = place }
            }
    }

    private func settle(_ new: ShoppingRoute.Place) async {
        guard new != shown else { return }
        if typing, shown != .nothing, new != .nothing {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
        }
        withAnimation(ShoppingMotion.change(reduceMotion)) { shown = new }
    }
}

// MARK: Chips and phases

private struct ChoiceMotion<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(ShoppingMotion.change(reduceMotion), value: value)
            .sensoryFeedback(.selection, trigger: value)
    }
}

private struct PhaseMotion: ViewModifier {
    let phase: DealsModel.Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: phase)
    }
}

// MARK: Pressing

/// A Shopping chip or segment shrinks a touch while pressed, as on Home; not under Reduce Motion. The same as
/// `DoddyTapStyle` in the redesign pull requests (#411, #416), which isn't on this branch's base; one can replace the
/// other once both are merged.
struct ShoppingPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.2), value: configuration.isPressed)
    }
}
