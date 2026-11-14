import DoddyCore
import SwiftUI

// "Where it goes", said before the tap (decision 2026-11-13-shopping-one-field; the look-and-motion pass of 13 Nov
// 2026): `ShoppingRoute`'s decision as a small orange chip with an icon per place (this week's leaflets, online shops,
// both, a product link), one plain line under it on what happens next, and, for both, the things that go on to online
// shops. The Shopping screen changes the chip only once the words have settled (`settlesRoute`, ShoppingMotion.swift),
// so it doesn't flicker on every key; its icon swaps with the system's symbol transition and the chip resizes with a
// short spring. Under Reduce Motion it simply changes. The words, the icon and VoiceOver all say the place: the orange
// is never the only sign, and the chip's words are ink on orange (Brand Guidelines V2.2 p.21).

struct ShoppingRouteChip: View {
    let place: ShoppingRoute.Place
    /// The things for online shops, named under the chip when the place is both.
    var online: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: Self.symbol(place))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                title
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.inkOnOrange)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.orangeCue))
            detail
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if place == .both, !online.isEmpty {
                Label(String(format: NSLocalizedString("Then online shops: %@", comment: "the things a shopping search offers to online shops after the leaflets"),
                             online.joined(separator: ", ")), systemImage: "arrow.turn.down.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ place: ShoppingRoute.Place) -> String {
        switch place {
        case .leaflets: "newspaper"
        case .online: "bag"
        case .both: "arrow.triangle.branch"
        case .link: "link"
        case .nothing: "questionmark"
        }
    }

    @ViewBuilder
    private var title: some View {
        switch place {
        case .leaflets: Text("This week's leaflets")
        case .online: Text("Online shops")
        case .both: Text("Leaflets, then online shops")
        case .link: Text("Check this")
        case .nothing: EmptyView()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch place {
        case .leaflets: Text("Prices come back in seconds.")
        case .online: Text("Doddy compares offers in the background, after your yes.")
        case .both: Text("Leaflet prices now; online shops after your yes, if you want.")
        case .link: Text("Doddy can read its price after your tap.")
        case .nothing: EmptyView()
        }
    }
}
