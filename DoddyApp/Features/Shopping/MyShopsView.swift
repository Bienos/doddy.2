import DoddyCore
import SwiftUI

// "My shops" (ADR-663, Cheapest this week): the shops the user goes to, found with an Apple Maps search near them
// (`PlaceLocation`, the same search as a place reminder: the chain names and roughly where the user is go to
// Apple) and judged by `MyShops` in DoddyCore. The picked shops stay on this iPhone (`deals.myShops`); they set
// which chains a check asks for, say which shop to check for "w wybranych sklepach", and open Apple's place card
// for the hours. Location is read once, when the user taps "Find shops near me", While Using only, never kept.

struct MyShopsView: View {
    @AppStorage(PreferenceKey.dealsMyShops) private var stored = "[]"
    @State private var found: [FoundShops] = []
    @State private var searching = false
    @State private var message: String?
    @State private var place = ""
    private let polish = NotificationLanguage.current == .polish

    private var shops: MyShops { MyShops(stored: stored) }

    var body: some View {
        Form {
            Section {
                if shops.shops.isEmpty {
                    Text("No shops yet. Find the ones near you below.").foregroundStyle(Theme.secondaryText)
                }
                ForEach(shops.shops, id: \.self) { shop in
                    ShopRow(shop: shop, distance: nil)
                        .swipeActions {
                            Button(role: .destructive) { stored = shops.removing(shop).stored } label: { Label("Remove", systemImage: "trash") }
                        }
                }
            } header: {
                Text("My shops")
            } footer: {
                Text("A leaflet check asks for these shops' chains. They stay on this iPhone; Doddy's server never gets them.")
            }

            Section {
                Button {
                    Task { await findNearMe() }
                } label: {
                    Label("Find shops near me", systemImage: "location")
                }
                .disabled(searching)
                .accessibilityIdentifier("myShops.nearMe")
                TextField("Or a town or street", text: $place)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .onSubmit { Task { await findNear(place) } }
                Button("Search there") { Task { await findNear(place) } }
                    .disabled(searching || place.trimmingCharacters(in: .whitespaces).isEmpty)
                if searching { ProgressView("Looking in Apple Maps…") }
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.error) }
            } footer: {
                Text("Apple Maps gets the shops' names and roughly where you are, as for a place reminder. Doddy reads your location once, only when you tap.")
            }

            if !found.isEmpty {
                Section("Near you") {
                    ForEach(found) { entry in
                        ForEach(entry.shops, id: \.shop) { nearby in
                            Button {
                                toggle(nearby.shop)
                            } label: {
                                HStack {
                                    ShopRow(shop: nearby.shop, distance: MyShops.distanceText(nearby.kilometres, polish: polish))
                                    Spacer(minLength: 8)
                                    Image(systemName: shops.contains(nearby.shop) ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(Theme.accentText)
                                }
                            }
                            .accessibilityLabel(shops.contains(nearby.shop)
                                ? String(format: NSLocalizedString("Remove %@, %@", comment: "a shop and its address"), nearby.shop.name, nearby.shop.address)
                                : String(format: NSLocalizedString("Add %@, %@", comment: "a shop and its address"), nearby.shop.name, nearby.shop.address))
                        }
                    }
                }
            }
        }
        .navigationTitle("My shops")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ shop: MyShop) {
        stored = shops.contains(shop) ? shops.removing(shop).stored : shops.adding(shop).stored
    }

    private func findNearMe() async {
        message = nil
        searching = true
        defer { searching = false }
        var readiness = await PlaceLocation.shared.readiness()
        if readiness == .notDetermined { readiness = await PlaceLocation.shared.requestWhenInUse() }
        guard readiness == .ready || readiness == .approximateOnly else {
            message = NSLocalizedString("Location is off for Doddy. Type a town or street instead.", comment: "")
            return
        }
        // Shops are kilometres apart: an approximate position is enough.
        guard let here = await PlaceLocation.shared.currentFix(within: 3_000)?.coordinate else {
            message = NSLocalizedString("Your iPhone couldn't tell where you are just now. Type a town or street instead.", comment: "")
            return
        }
        await search(near: here)
    }

    private func findNear(_ text: String) async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        message = nil
        searching = true
        defer { searching = false }
        guard let first = try? await PlaceLocation.shared.search(words, near: nil).first else {
            message = NSLocalizedString("Apple Maps didn't find that place.", comment: "")
            return
        }
        await search(near: first.coordinate)
    }

    /// One Apple Maps search per chain, near `here`; the code keeps each chain's own shops, nearest first.
    private func search(near here: PlaceCoordinate) async {
        var results: [FoundShops] = []
        var failed = false
        for chain in DealsChain.all {
            do {
                let places = try await PlaceLocation.shared.search(chain.name, near: here)
                let nearby = MyShops.nearby(places.map {
                    ShopSearchResult(name: $0.name, address: $0.address, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                }, chain: chain, here: (here.latitude, here.longitude))
                if !nearby.isEmpty { results.append(FoundShops(chain: chain, shops: nearby)) }
            } catch {
                failed = true
            }
        }
        found = results
        if results.isEmpty {
            message = failed
                ? NSLocalizedString("Apple Maps couldn't be reached. Try again when you're online.", comment: "")
                : NSLocalizedString("No shops of these chains within 15 km.", comment: "")
        }
    }
}

/// One chain's shops near the user.
struct FoundShops: Identifiable {
    let chain: DealsChain
    let shops: [NearbyShop]
    var id: String { chain.rawValue }
}

/// A shop: its chain, name, address, how far (when known) and Apple's place card.
struct ShopRow: View {
    let shop: MyShop
    let distance: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(shop.chain.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(distance.map { "\(shop.address) · \($0)" } ?? shop.address).font(.footnote).foregroundStyle(Theme.secondaryText)
            if let url = shop.mapsURL, distance == nil {
                Link("Open in Apple Maps", destination: url).font(.footnote)
            }
        }
    }
}
