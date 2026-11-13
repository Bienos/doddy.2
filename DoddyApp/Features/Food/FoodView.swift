import DoddyCore
import SwiftUI

/// Home's "Food" screen (owner, 11 Nov 2026, decision `2026-11-11-food-button`; rebuilt 13 Nov 2026, decision
/// `2026-11-13-food-search-nearby`: "to ma być bardziej pole do zamawiania … chcę burgera i to mi pokazuje burgery
/// … najbliżej mnie"). The person types a dish (or taps one) and their delivery address; Apple Maps finds the
/// restaurants, cafés and bakeries for it near that address, nearest first (`PlaceLocation.foodPlaces` in
/// Connections, judged by `FoodSearch` in DoddyCore). Each place can be taken to a delivery app (its front page,
/// with the place's name copied to paste into the app's search, because no app publishes a search address),
/// opened in Apple Maps, or rung when Apple Maps lists a number. Below, the delivery apps themselves.
///
/// Honest limits, said on the screen: Doddy sees no price, menu or delivery fee, so it never says where it's
/// cheapest; it never orders or pays. The dish and the address go to Apple Maps only; the address is kept on this
/// iPhone (`food.deliveryAddress`) until the person clears it. No location permission is asked for.
struct FoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// The delivery address as typed: on this iPhone only, never sent to Doddy's server, until cleared here.
    @AppStorage("food.deliveryAddress") private var address = ""
    @State private var dish = ""
    @State private var searching = false
    @State private var problem: String?
    @State private var located: FoodLocatedAddress?
    @State private var outcome: FoodOutcome?
    @FocusState private var focus: FoodField?

    private var polish: Bool { NotificationLanguage.current == .polish }

    var body: some View {
        NavigationStack {
            DoddyPage {
                DoddyPageHeader(
                    title: "What do you fancy?",
                    subtitle: "Type a dish and your address. Doddy finds matching places nearby in Apple Maps, nearest first.",
                    pose: .leaning)
                searchCard
                statusArea
                resultsArea
                FoodLimitsCard()
                appsSection
                DoddyFinePrint(text: Text("The dish and the address go to Apple Maps for the search; nothing goes to Doddy's server. The address stays on this iPhone until you clear it. In a delivery app, that app's own terms and privacy apply."))
            }
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: The search card

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            dishField
            dishChips
            addressField
            Button {
                startSearch()
            } label: {
                Label("Find places near this address", systemImage: "fork.knife")
            }
            .buttonStyle(DoddyAccentButtonStyle())
            .disabled(searching)
            .accessibilityIdentifier("food.search")
        }
        .doddyCard()
    }

    private var dishField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            TextField("Burger, pho, pierogi…", text: $dish)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focus, equals: .dish)
                .onSubmit { startSearch() }
                .accessibilityLabel("Dish")
                .accessibilityIdentifier("food.dish")
        }
        .doddyField()
    }

    private var dishChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FoodDishChip.all) { chip in
                    DoddyChip(title: LocalizedStringKey(chip.key), isSelected: dish == chip.query) {
                        dish = chip.query
                        startSearch()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    .focused($focus, equals: .address)
                    .onSubmit { startSearch() }
                    .accessibilityLabel("Delivery address")
                    .accessibilityIdentifier("food.address")
            }
            .doddyField()
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
        }
    }

    // MARK: What the search found

    @ViewBuilder private var statusArea: some View {
        if searching {
            ProgressView("Looking in Apple Maps…")
                .tint(Theme.ink)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let problem {
            DoddyNotice(text: Text(verbatim: problem), isProblem: true)
        }
    }

    @ViewBuilder private var resultsArea: some View {
        if let outcome, !searching {
            VStack(alignment: .leading, spacing: 12) {
                DoddySectionTitle(title: "Near you")
                Text(verbatim: String(format: NSLocalizedString("“%@” near %@, nearest first.", comment: "a dish, then an address"), outcome.dish, outcome.near))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if outcome.places.isEmpty {
                    DoddyNotice(text: Text(verbatim: String(
                        format: NSLocalizedString("Apple Maps found no restaurants, cafés or bakeries for “%@” within %lld km. Try another word, or a restaurant's name.", comment: ""),
                        outcome.dish, Int(FoodSearch.maxKilometres))))
                } else {
                    ForEach(outcome.places) { place in
                        FoodPlaceCard(
                            place: place,
                            distance: MyShops.distanceText(place.kilometres, polish: polish),
                            order: { app in order(place, in: app) })
                    }
                }
            }
        }
    }

    // MARK: The delivery apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DoddySectionTitle(title: "Delivery apps")
            Text("Opens the app if you have it, or the website. Doddy doesn't see or place the order.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            FoodAppGrid { app in openURL(app.url) }
        }
    }

    // MARK: Actions

    private func startSearch() {
        guard !searching else { return }
        Task { await search() }
    }

    /// The address is located once per wording, then the dish is searched around it. Every failure says what to
    /// do next; nothing found is said as nothing found.
    private func search() async {
        let typedDish = dish.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if typedDish.isEmpty {
            problem = NSLocalizedString("Type a dish first, or tap one.", comment: "")
            focus = .dish
            return
        }
        guard let words = FoodSearch.dish(typedDish) else {
            problem = NSLocalizedString("Keep it to one short line: a dish or a restaurant's name.", comment: "")
            focus = .dish
            return
        }
        if typedAddress.isEmpty {
            problem = NSLocalizedString("Type your delivery address first, so Doddy knows where to look.", comment: "")
            focus = .address
            return
        }
        guard let place = FoodSearch.address(typedAddress) else {
            problem = NSLocalizedString("That address is too long. Street, number and city are enough.", comment: "")
            focus = .address
            return
        }
        focus = nil
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
            outcome = FoodOutcome(
                dish: words, near: near.label,
                places: FoodSearch.nearby(found, here: (near.coordinate.latitude, near.coordinate.longitude)))
        } catch {
            problem = NSLocalizedString("Apple Maps couldn't be reached. Try again when you're online.", comment: "")
        }
    }

    /// The typed address as Apple Maps places it, asked again only when the wording changes.
    private func locate(_ typed: String) async throws -> FoodLocatedAddress? {
        if let located, located.typed == typed { return located }
        guard let found = try await PlaceLocation.shared.foodAddress(typed) else { return nil }
        let label = found.address.isEmpty ? found.name : found.address
        let result = FoodLocatedAddress(typed: typed, label: label, coordinate: found.coordinate)
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
}

// MARK: - Pieces of the Food screen

private enum FoodField: Hashable {
    case dish, address
}

/// The typed address, where Apple Maps put it, and how it named it.
private struct FoodLocatedAddress {
    let typed: String
    let label: String
    let coordinate: PlaceCoordinate
}

/// One search's answer: the dish, the place it was searched near, and what Apple Maps found.
private struct FoodOutcome {
    let dish: String
    let near: String
    let places: [NearbyFoodPlace]
}

/// A dish to tap. The chip shows the word in the app's language, and that same word goes to Apple Maps
/// ("Sałatki" finds more in Poland than "Salad").
private struct FoodDishChip: Identifiable, Sendable {
    let key: String

    init(title: String) { key = title }

    var id: String { key }
    var query: String { NSLocalizedString(key, comment: "a dish to search for") }

    static let all: [FoodDishChip] = [
        FoodDishChip(title: "Burger"),
        FoodDishChip(title: "Pizza"),
        FoodDishChip(title: "Sushi"),
        FoodDishChip(title: "Kebab"),
        FoodDishChip(title: "Pierogi"),
        FoodDishChip(title: "Ramen"),
        FoodDishChip(title: "Pho"),
        FoodDishChip(title: "Thai"),
        FoodDishChip(title: "Salad"),
    ]
}
