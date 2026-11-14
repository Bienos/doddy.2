import DoddyCore
import SwiftUI

// "Near you" on Home › Food (decision `2026-11-13-food-search-nearby`; owner, 13 Nov 2026: "chcę burgera i to mi
// pokazuje burgery … najbliżej mnie"). Once the person has said what they feel like (`FoodView.looking`), they can
// type a delivery address and Apple Maps lists the restaurants, cafés and bakeries for it nearby, nearest first
// (`PlaceLocation.foodPlaces` in Connections, judged by `FoodSearch` in DoddyCore). Each place can be taken to a
// delivery app (its front page, with the place's name copied to paste into the app's search, because no app
// publishes a search address), opened in Apple Maps, or rung when Apple Maps lists a number.
//
// Honest limits, said on the screen: Doddy sees no price, menu or delivery fee, so it never says where it's
// cheapest; it never orders or pays. The dish and the address go to Apple Maps only; the address is kept on this
// iPhone (`food.deliveryAddress`) until the person clears it. No location permission is asked for.

struct FoodNearbySection: View {
    /// What the person is looking for, as `FoodView` holds it; nil until they asked.
    let dish: String?
    @Environment(\.openURL) private var openURL
    /// The delivery address as typed: on this iPhone only, never sent to Doddy's server, until cleared here.
    @AppStorage("food.deliveryAddress") private var address = ""
    @State private var searching = false
    @State private var problem: String?
    @State private var located: LocatedAddress?
    @State private var outcome: Outcome?
    @FocusState private var addressFocused: Bool

    private var polish: Bool { NotificationLanguage.current == .polish }

    var body: some View {
        if let dish {
            VStack(alignment: .leading, spacing: 12) {
                DoddySectionTitle(title: "Near you")
                addressCard(for: dish)
                status
                results
                DoddyFootnote(text: NSLocalizedString("The dish and the address go to Apple Maps for the search; nothing goes to Doddy's server. The address stays on this iPhone until you clear it.", comment: ""),
                              systemImage: "lock")
            }
            .onChange(of: dish) { _, _ in
                // A new dish: the places listed are for the old one.
                outcome = nil
                problem = nil
            }
        }
    }

    // MARK: The address

    private func addressCard(for dish: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deliver to")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 10) {
                Image(systemName: "house")
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
                TextField("Street, number, city", text: $address)
                    .foregroundStyle(Theme.ink)
                    .textContentType(.fullStreetAddress)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .focused($addressFocused)
                    .onSubmit { startSearch(dish) }
                    .accessibilityLabel("Delivery address")
                    .accessibilityIdentifier("food.address")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1) }
            HStack(alignment: .firstTextBaseline) {
                Text("Kept on this iPhone only.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 8)
                if !address.isEmpty {
                    Button("Clear") { clearAddress() }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Clear the address")
                        .accessibilityIdentifier("food.clearAddress")
                }
            }
            Button {
                startSearch(dish)
            } label: {
                Label("Find places near this address", systemImage: "fork.knife")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DoddyInkButtonStyle())
            .disabled(searching)
            .accessibilityIdentifier("food.search")
        }
        .doddyCard()
    }

    // MARK: What the search found

    @ViewBuilder private var status: some View {
        if searching {
            ProgressView("Looking in Apple Maps…")
                .tint(Theme.ink)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let problem {
            Label { Text(verbatim: problem).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.error)
        }
    }

    @ViewBuilder private var results: some View {
        if let outcome, !searching {
            Text(verbatim: String(format: NSLocalizedString("“%@” near %@, nearest first.", comment: "a dish, then an address"), outcome.dish, outcome.near))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if outcome.places.isEmpty {
                Label {
                    Text(verbatim: String(
                        format: NSLocalizedString("Apple Maps found no restaurants, cafés or bakeries for “%@” within %lld km. Try another word, or a restaurant's name.", comment: ""),
                        outcome.dish, Int(FoodSearch.maxKilometres)))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(outcome.places) { place in
                    placeCard(place)
                }
            }
        }
    }

    private func placeCard(_ place: NearbyFoodPlace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                DoddySymbolTile(systemImage: icon(place.kind))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: place.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: MyShops.distanceText(place.kilometres, polish: polish) + " · " + kindName(place.kind))
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
            // One row of actions, or a column when the text is too large for a row.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions(for: place) }
                VStack(alignment: .leading, spacing: 8) { actions(for: place) }
            }
        }
        .doddyCard(padding: 14)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func actions(for place: NearbyFoodPlace) -> some View {
        Menu {
            Section {
                ForEach(FoodApps.all) { app in
                    Button(app.name) { order(place, in: app) }
                }
            } header: {
                Text(verbatim: String(format: NSLocalizedString("Copies “%@” to paste into the app's search.", comment: "a restaurant's name"), place.name))
            }
        } label: {
            Label("Order in…", systemImage: "bag.fill")
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .foregroundStyle(Theme.canvas)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Theme.ink, in: Capsule())
        }
        .accessibilityLabel(String(format: NSLocalizedString("Order from %@ in a delivery app", comment: "a restaurant's name"), place.name))
        if let url = place.callURL {
            Button {
                openURL(url)
            } label: {
                Label("Call them", systemImage: "phone.fill").lineLimit(1)
            }
            .buttonStyle(DoddyOutlineButtonStyle())
            .accessibilityLabel(String(format: NSLocalizedString("Call %@", comment: ""), place.name))
        }
        if let url = place.mapsURL {
            Button {
                openURL(url)
            } label: {
                Label("Maps", systemImage: "map.fill").lineLimit(1)
            }
            .buttonStyle(DoddyOutlineButtonStyle())
            .accessibilityLabel(String(format: NSLocalizedString("Open %@ in Apple Maps", comment: "a restaurant's name"), place.name))
        }
    }

    private func icon(_ kind: FoodPlaceKind) -> String {
        switch kind {
        case .restaurant: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .bakery: "birthday.cake.fill"
        }
    }

    private func kindName(_ kind: FoodPlaceKind) -> String {
        switch kind {
        case .restaurant: NSLocalizedString("Restaurant", comment: "a kind of food place")
        case .cafe: NSLocalizedString("Café", comment: "a kind of food place")
        case .bakery: NSLocalizedString("Bakery", comment: "a kind of food place")
        }
    }

    // MARK: Actions

    private func startSearch(_ dish: String) {
        guard !searching else { return }
        Task { await search(dish) }
    }

    /// The address is located once per wording, then the dish is searched around it. Every failure says what to
    /// do next; nothing found is said as nothing found.
    private func search(_ typedDish: String) async {
        guard let words = FoodSearch.dish(typedDish) else {
            problem = NSLocalizedString("Keep it to one short line: a dish or a restaurant's name.", comment: "")
            return
        }
        let typedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if typedAddress.isEmpty {
            problem = NSLocalizedString("Type your delivery address first, so Doddy knows where to look.", comment: "")
            addressFocused = true
            return
        }
        guard let place = FoodSearch.address(typedAddress) else {
            problem = NSLocalizedString("That address is too long. Street, number and city are enough.", comment: "")
            addressFocused = true
            return
        }
        addressFocused = false
        problem = nil
        searching = true
        defer { searching = false }
        do {
            guard let near = try await locate(place) else {
                outcome = nil
                problem = NSLocalizedString("Apple Maps didn't find that address. Add the street number and the city.", comment: "")
                return
            }
            let found = try await PlaceLocation.shared.foodPlaces(words, near: near.coordinate)
            outcome = Outcome(
                dish: words, near: near.label,
                places: FoodSearch.nearby(found, here: (near.coordinate.latitude, near.coordinate.longitude)))
        } catch {
            problem = NSLocalizedString("Apple Maps couldn't be reached. Try again when you're online.", comment: "")
        }
    }

    /// The typed address as Apple Maps places it, asked again only when the wording changes.
    private func locate(_ typed: String) async throws -> LocatedAddress? {
        if let located, located.typed == typed { return located }
        guard let found = try await PlaceLocation.shared.foodAddress(typed) else { return nil }
        let label = found.address.isEmpty ? found.name : found.address
        let result = LocatedAddress(typed: typed, label: label, coordinate: found.coordinate)
        located = result
        return result
    }

    private func clearAddress() {
        address = ""
        located = nil
        outcome = nil
        problem = nil
    }

    /// Copies the place's name (this iPhone only, gone after two minutes, ADR-724) and opens the app's front page:
    /// its app when installed, its website otherwise. The person searches, chooses, pays and orders there.
    private func order(_ place: NearbyFoodPlace, in app: FoodApp) {
        NoteClipboard.copy(place.name)
        openURL(app.url)
    }

    // MARK: Values

    /// The typed address, where Apple Maps put it, and how it named it.
    private struct LocatedAddress {
        let typed: String
        let label: String
        let coordinate: PlaceCoordinate
    }

    /// One search's answer: the dish, the place it was searched near, and what Apple Maps found.
    private struct Outcome {
        let dish: String
        let near: String
        let places: [NearbyFoodPlace]
    }
}
