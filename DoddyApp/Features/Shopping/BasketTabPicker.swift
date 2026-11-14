import DoddyCore
import SwiftUI

// The leaflet answer's three tabs as one control (decision 2026-11-13-shopping-one-field; the look-and-motion pass of
// 13 Nov 2026): equal segments on a quiet track, each with its name and the total of the plan it shows (from
// `BasketTabs.plan(for:)`, so "One shop 41,94 zł · Two shops 38,70 zł" can be compared before a tap). The picked
// segment sits on an ink pill with cream words (as a picked `DoddyChip` in the redesign pull requests #411 and #416)
// that slides to the next one (`matchedGeometryEffect`); its name turns bold and VoiceOver hears "selected", so colour
// is never the only sign. A segment shrinks a touch while pressed (`ShoppingPressStyle`).
// At the largest text sizes the segments stack one under another, so no name or amount is cut. Under Reduce Motion
// the pill doesn't slide: the picked segment simply changes. The caller animates the change and plays the haptic.
// Identifiers stay `deals.tab.<tab>` (the screens' UI tests tap them).

struct BasketTabPicker: View {
    let tabs: [BasketTabs.Tab]
    let shown: BasketTabs.Tab?
    /// Each tab's total as words ("41,94 zł", "at least 41,94 zł · 5 of 6"); a tab with none shows its name only.
    let totals: [BasketTabs.Tab: String]
    let select: (BasketTabs.Tab) -> Void

    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let stacked = textSize >= .xxxLarge
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            ForEach(tabs, id: \.self) { tab in
                segment(tab, stacked: stacked)
            }
        }
        .padding(4)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.quietSurface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func segment(_ tab: BasketTabs.Tab, stacked: Bool) -> some View {
        let on = tab == shown
        return Button {
            select(tab)
        } label: {
            SegmentLabel(title: title(tab), total: totals[tab], on: on, stacked: stacked)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: stacked ? .leading : .center)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background {
                    if on { TabPill(space: space, slides: !reduceMotion) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(ShoppingPressStyle())
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("deals.tab.\(tab.rawValue)")
    }

    private func title(_ tab: BasketTabs.Tab) -> Text {
        switch tab {
        case .oneShop: Text("One shop")
        case .twoShops: Text("Two shops")
        case .eachItem: Text("Each item separately")
        }
    }
}

/// A segment's name and total: centred under each other, or side by side when the segments are stacked.
private struct SegmentLabel: View {
    let title: Text
    let total: String?
    let on: Bool
    let stacked: Bool

    var body: some View {
        let ink = on ? Theme.canvas : Theme.ink
        let layout = stacked ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                             : AnyLayout(VStackLayout(alignment: .center, spacing: 2))
        return layout {
            title
                .font(.subheadline.weight(on ? .bold : .semibold))
                .foregroundStyle(ink)
                .multilineTextAlignment(stacked ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
            if stacked { Spacer(minLength: 8) }
            if let total {
                Text(verbatim: total)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(on ? Theme.canvas : Theme.secondaryText)
                    .multilineTextAlignment(stacked ? .trailing : .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }
        }
    }
}

/// The ink pill under the picked segment; it slides between segments unless Reduce Motion is on.
private struct TabPill: View {
    let space: Namespace.ID
    let slides: Bool

    var body: some View {
        if slides {
            pill.matchedGeometryEffect(id: "basket.tab.pill", in: space)
        } else {
            pill
        }
    }

    private var pill: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.ink)
            .accessibilityHidden(true)
    }
}
