import DoddyCore
import SwiftUI

// The pieces of Home › Food (`FoodView`): a place Apple Maps found, the delivery-app tiles, and the card that says
// what Doddy can't do yet. Doddy's colours through `Theme` and the screen kit: orange only as a fill, with
// `Theme.inkOnOrange` on it.

/// A food place near the delivery address: name, how far, what it is, the address, and what to do with it.
struct FoodPlaceCard: View {
    let place: NearbyFoodPlace
    /// "1,2 km", already written for the app's language.
    let distance: String
    /// Copies the name and opens the delivery app (`FoodView.order`).
    let order: (FoodApp) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                DoddyIconBadge(systemName: icon, size: 40)
                details
            }
            actions
        }
        .doddyCard(padding: 14)
        .accessibilityElement(children: .contain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: place.name)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: distance + " · " + kindName)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            if !place.address.isEmpty {
                Text(verbatim: place.address)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One row of small pills, or a column when the text is too large for a row.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                orderMenu
                callButton
                mapsButton
            }
            VStack(alignment: .leading, spacing: 8) {
                orderMenu
                callButton
                mapsButton
            }
        }
    }

    private var orderMenu: some View {
        Menu {
            Section {
                ForEach(FoodApps.all) { app in
                    Button {
                        order(app)
                    } label: {
                        Text(verbatim: app.name)
                    }
                }
            } header: {
                Text(verbatim: String(format: NSLocalizedString("Copies “%@” to paste into the app's search.", comment: "a restaurant's name"), place.name))
            }
        } label: {
            FoodPill(title: "Order in…", systemImage: "bag.fill", filled: true)
        }
        .tint(Theme.ink)
        .accessibilityLabel(String(format: NSLocalizedString("Order from %@ in a delivery app", comment: "a restaurant's name"), place.name))
    }

    @ViewBuilder private var callButton: some View {
        if let url = place.callURL {
            Button {
                openURL(url)
            } label: {
                FoodPill(title: "Call them", systemImage: "phone.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("Call %@", comment: ""), place.name))
        }
    }

    @ViewBuilder private var mapsButton: some View {
        if let url = place.mapsURL {
            Button {
                openURL(url)
            } label: {
                FoodPill(title: "Maps", systemImage: "map.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("Open %@ in Apple Maps", comment: "a restaurant's name"), place.name))
        }
    }

    private var icon: String {
        switch place.kind {
        case .restaurant: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .bakery: "birthday.cake.fill"
        }
    }

    private var kindName: String {
        switch place.kind {
        case .restaurant: NSLocalizedString("Restaurant", comment: "a kind of food place")
        case .cafe: NSLocalizedString("Café", comment: "a kind of food place")
        case .bakery: NSLocalizedString("Bakery", comment: "a kind of food place")
        }
    }
}

/// A small action in Doddy's colours: orange with ink words for the main one, an outline for the others.
struct FoodPill: View {
    let title: LocalizedStringKey
    let systemImage: String
    var filled = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(filled ? Theme.inkOnOrange : Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(filled ? Theme.orangeCue : Theme.canvas, in: Capsule())
            .overlay {
                if !filled {
                    Capsule().strokeBorder(Theme.separator, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
    }
}

/// The delivery apps as tiles, two to a row (one at the largest text sizes).
struct FoodAppGrid: View {
    let open: (FoodApp) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        if typeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(FoodApps.all) { app in
                FoodAppTile(app: app) { open(app) }
            }
        }
    }
}

/// One delivery app: its initial on an orange disc (a decoration, not the brand's logo), its name, and an arrow
/// that says it leaves Doddy.
struct FoodAppTile: View {
    let app: FoodApp
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(verbatim: String(app.name.prefix(1)))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkOnOrange)
                    .frame(width: 40, height: 40)
                    .background(Theme.orangeCue, in: Circle())
                    .accessibilityHidden(true)
                Text(verbatim: app.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .doddyCard(padding: 14)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: NSLocalizedString("Open %@", comment: "a delivery app"), app.name))
        .accessibilityIdentifier("food.\(app.id)")
    }
}

/// What Doddy can't do here yet, said plainly (constitution: no invented prices, never "ordered" or "paid").
struct FoodLimitsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            line(systemImage: "tag", text: Text("Prices and delivery fees are only in the apps. Doddy doesn't see them yet, so he can't say where it's cheapest."))
            line(systemImage: "creditcard", text: Text("Doddy doesn't order or pay. Ordering for you needs a wallet or card in Doddy, and that isn't built yet."))
        }
        .doddyCard(padding: 14, accent: true)
    }

    private func line(systemImage: String, text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            text
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 4)
    }
}
