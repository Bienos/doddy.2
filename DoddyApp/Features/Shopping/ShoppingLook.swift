import DoddyCore
import SwiftUI

// The Shopping screens' small pieces (owner, 13 Nov 2026: "graficznie i animacyjnie, kreatywnie, ale tak, żeby to
// było łatwe do ogarnięcia"): shop badges, condition chips, the cheapest price with an orange marker under it, and
// the dashed "Missing" note. Colours are `Theme`'s (Brand Guidelines V2.2,
// ADR-556): orange only as decoration and action emphasis, never as text; ink on orange where text sits on it. Every
// state is said in words or an icon as well as a colour. Motion follows the guide's "animate a reason, settle with
// restraint" (p.31): a price is marked once when it appears, rows arrive once, nothing loops. Under Reduce Motion
// nothing slides or springs: things are simply there, or fade. The motion itself is in ShoppingMotion.swift.
// The shapes follow the redesign pull requests' shared pieces (#411, #416, `DoddyScreenKit`) where they overlap: a
// shop tag is a capsule on a faint orange like `DoddyTag`, a picked segment is ink like a picked `DoddyChip`.
// Every amount drawn here comes in as text the caller made from `BasketSolver`'s sums; nothing here prices anything.

// MARK: The cheapest price

/// A price in heavy ink with an orange marker stroke under it (never behind the digits, so the contrast is ink's in
/// both appearances). The marker draws from the left once when the price appears; under Reduce Motion it is simply
/// there. A long price wraps rather than truncates.
struct PriceMark: View {
    let text: String
    var font: Font = .title3.weight(.heavy)
    /// The orange marker: on for the cheapest, off for a plain amount.
    var marked = true
    /// Waits this long before drawing, so a price marked after its row has arrived.
    var delay: Double = 0.18
    /// How wrapped lines line up: trailing beside a name, leading on a line of its own.
    var alignment: TextAlignment = .trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var markHeight: CGFloat = 5
    @State private var drawn = false

    var body: some View {
        Text(verbatim: text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, marked ? markHeight * 0.9 : 0)
            .background(alignment: .bottomLeading) {
                if marked {
                    Capsule()
                        .fill(Theme.orangeCue)
                        .frame(height: markHeight)
                        .scaleEffect(x: drawn || reduceMotion ? 1 : 0.001, y: 1, anchor: .leading)
                        .accessibilityHidden(true)
                }
            }
            .onAppear {
                guard marked, !drawn, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.45).delay(delay)) { drawn = true }
            }
    }
}

// MARK: Shops and conditions

/// A shop's name as a small badge. No shop logos or brand colours: two token styles, so the two shops of a pair
/// can be told apart, and the name is always written (never colour alone).
struct ShopBadge: View {
    let name: String
    /// 0: orange-tinted (the first shop of a plan); 1: ink outline (the second).
    var style = 0
    /// A plan's own shops, at the top of its card: a size up.
    var large = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "storefront").imageScale(.small).accessibilityHidden(true)
            Text(verbatim: name)
        }
        .font(large ? Font.subheadline.weight(.bold) : Font.caption.weight(.bold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(style == 0 ? Theme.orangeCue.opacity(0.16) : Theme.canvas))
        .overlay(Capsule().strokeBorder(style == 0 ? Color.clear : Theme.ink.opacity(0.55), lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A small outlined chip: an icon and words, which wrap at large text sizes.
struct ShoppingChip: View {
    let text: String
    let symbol: String
    var tint: Color = Theme.accentText
    var dashed = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol).imageScale(.small).accessibilityHidden(true)
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : [])))
    }
}

/// One leaflet condition or the line's day (`DealChip`, DoddyCore): the server's words, or the day in the app's words.
struct DealChipView: View {
    let chip: DealChip

    var body: some View {
        ShoppingChip(text: Self.words(chip), symbol: Self.symbol(chip.kind),
                     tint: chip.kind == .until ? Theme.secondaryText : Theme.accentText)
    }

    static func words(_ chip: DealChip) -> String {
        let day = chip.day.map { DealDayText.text($0) } ?? ""
        switch chip.kind {
        case .startsOn: return String(format: NSLocalizedString("not on until %@", comment: ""), day)
        case .lastDay: return NSLocalizedString("today is the last day", comment: "")
        case .buyBy: return String(format: NSLocalizedString("buy by %@", comment: "a leaflet price whose last day the shops are closed"), day)
        case .until: return String(format: NSLocalizedString("Until %@", comment: "leaflet offer end date"), day)
        default: return chip.text ?? ""
        }
    }

    static func symbol(_ kind: DealChip.Kind) -> String {
        switch kind {
        case .app: "iphone"
        case .card: "creditcard"
        case .multiBuy: "plus.square.on.square"
        case .minimum: "number"
        case .limit: "hand.raised"
        case .deposit: "arrow.3.trianglepath"
        case .stock: "shippingbox"
        case .someShops: "mappin.and.ellipse"
        case .other: "info.circle"
        case .startsOn: "calendar.badge.clock"
        case .lastDay: "hourglass"
        case .buyBy: "calendar.badge.exclamationmark"
        case .until: "calendar"
        }
    }
}

/// "Missing: X" in a dashed box: a gap in the list, said plainly, not an error.
struct MissingNote: View {
    let items: [String]

    var body: some View {
        Label {
            Text(String(format: NSLocalizedString("Missing: %@", comment: "items no shop in this plan has"), items.joined(separator: ", ")))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "circle.dashed").foregroundStyle(Theme.secondaryText)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.secondaryText.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .combine)
    }
}
