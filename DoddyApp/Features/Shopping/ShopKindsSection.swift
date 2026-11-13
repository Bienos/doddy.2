import DoddyCore
import SwiftUI

// Shopping by kind of shop (owner, 13 Nov 2026: "jedzeniowe oddzielnie, ciuchowe oddzielnie, inne oddzielnie, i one
// powinny mieć bardziej rozbudowane, co można zrobić"). Under the Shopping screen's one field (decision
// 2026-11-13-shopping-one-field) five tiles open a kind's page (`ShoppingCategoryView`): the shops Doddy works with
// there, what it does at each, and a search scoped to the kind. The kinds and their shops are `ShopCategory` and
// `ShopDirectory` in DoddyCore; nothing here is a new capability.

struct ShopKindsSection: View {
    @Environment(\.dynamicTypeSize) private var textSize

    private var columns: [GridItem] {
        textSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DoddySectionTitle(title: "Shops by kind")
            Text("Groceries, fashion, electronics, home and the rest: each kind lists the shops Doddy works with there.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ShopCategory.allCases) { category in
                    NavigationLink {
                        ShoppingCategoryView(category: category)
                    } label: {
                        tile(category)
                    }
                    .buttonStyle(DoddyTapStyle())
                    .accessibilityIdentifier("shopping.kind.\(category.rawValue)")
                }
            }
        }
    }

    private func tile(_ category: ShopCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DoddySymbolTile(systemImage: category.symbol)
            Text(verbatim: category.title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: category.line)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .doddyCard(padding: 14)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Words for the kinds

extension ShopCategory {
    /// The kind's name on the screen.
    var title: String {
        switch self {
        case .groceries: NSLocalizedString("Groceries & household", comment: "a kind of shop")
        case .fashion: NSLocalizedString("Fashion & shoes", comment: "a kind of shop")
        case .electronics: NSLocalizedString("Electronics", comment: "a kind of shop")
        case .home: NSLocalizedString("Home & garden", comment: "a kind of shop")
        case .other: NSLocalizedString("Other", comment: "a kind of shop")
        }
    }

    /// What the kind covers, on its tile.
    var line: String {
        switch self {
        case .groceries: NSLocalizedString("Food, drugstore and cleaning", comment: "a kind of shop's tile")
        case .fashion: NSLocalizedString("Clothes, shoes and accessories", comment: "a kind of shop's tile")
        case .electronics: NSLocalizedString("Phones, laptops, TV and audio", comment: "a kind of shop's tile")
        case .home: NSLocalizedString("Furniture, decor, tools and garden", comment: "a kind of shop's tile")
        case .other: NSLocalizedString("Pets, toys, sport and the rest", comment: "a kind of shop's tile")
        }
    }

    /// A line of what one might type on the kind's page.
    var example: String {
        switch self {
        case .groceries: NSLocalizedString("Milk, butter, coffee", comment: "an example on a kind's page")
        case .fashion: NSLocalizedString("White sneakers, size 42, under 300 zł", comment: "an example on a kind's page")
        case .electronics: NSLocalizedString("Noise-cancelling headphones under 800 zł", comment: "an example on a kind's page")
        case .home: NSLocalizedString("A 140 cm sofa bed under 2500 zł", comment: "an example on a kind's page")
        case .other: NSLocalizedString("A child's bike helmet", comment: "an example on a kind's page")
        }
    }

    var symbol: String {
        switch self {
        case .groceries: "cart"
        case .fashion: "tshirt"
        case .electronics: "headphones"
        case .home: "house"
        case .other: "square.grid.2x2"
        }
    }
}

extension ShopCapability {
    /// Under a shop's name: what Doddy does there.
    var words: String {
        switch self {
        case .leaflet: NSLocalizedString("leaflet", comment: "what Doddy does at a shop")
        case .onlyItsKind: NSLocalizedString("for its kind of items", comment: "what Doddy does at a shop")
        case .leafletLink: NSLocalizedString("link to its leaflet", comment: "what Doddy does at a shop")
        case .searchAndCart: NSLocalizedString("search & cart", comment: "what Doddy does at a shop")
        }
    }
}
