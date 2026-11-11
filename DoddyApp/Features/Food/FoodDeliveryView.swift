import DoddyCore
import MapKit
import SwiftUI

/// Live, external food ordering. Providers control their real menus, addresses, prices,
/// payments and receipts. Doddy does not pretend that opening a provider means ordering.
struct FoodDeliveryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchTerm = ""
    @State private var city = "Warszawa"
    @State private var searching = false
    @State private var didSearch = false
    @State private var searchError: String?
    @State private var places: [MKMapItem] = []

    private var polish: Bool { NotificationLanguage.current == .polish }
    private func copy(_ pl: String, _ en: String) -> String { polish ? pl : en }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(copy(
                        "Otwórz prawdziwą platformę dostawczą. Wybór dań, adres, płatność i potwierdzenie zamówienia odbywają się u dostawcy.",
                        "Open a real delivery service. Choose items, enter your address, pay and confirm the order with the provider."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                }

                Section {
                    ForEach(FoodDeliveryProvider.allCases) { provider in
                        Link(destination: provider.orderURL) {
                            HStack(spacing: 12) {
                                Image(systemName: "bag")
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(provider.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text(provider.showsWarsawListing
                                         ? copy("Restauracje w Warszawie", "Warsaw restaurant listings")
                                         : copy("Wybierz adres u dostawcy", "Choose your address with the provider"))
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("food.provider.\(provider.id)")
                    }
                } header: {
                    Text(copy("Zamów u dostawcy", "Order with a provider"))
                }

                Section {
                    Text(copy(
                        "To są rzeczywiste miejsca z Map Apple. Doddy nie sprawdza tutaj, czy dana restauracja oferuje dostawę przez którąkolwiek platformę.",
                        "These are real places from Apple Maps. Doddy does not verify whether a restaurant offers delivery through any provider."
                    ))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                    TextField(copy("Co chcesz zjeść? (np. pizza)", "What would you like? (e.g. pizza)"), text: $searchTerm)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("food.search.term")
                    TextField(copy("Miasto", "City"), text: $city)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("food.search.city")

                    Button {
                        Task { await searchRealPlaces() }
                    } label: {
                        Label(copy("Szukaj prawdziwych restauracji", "Find real restaurants"), systemImage: "magnifyingglass")
                    }
                    .disabled(searching || searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("food.search.submit")

                    if searching {
                        ProgressView()
                    } else if let searchError {
                        Text(searchError).foregroundStyle(Theme.error)
                    } else if didSearch && places.isEmpty {
                        Text(copy("Nie znaleziono miejsc. Zmień zapytanie.", "No places found. Try another search."))
                            .foregroundStyle(Theme.secondaryText)
                    }

                    ForEach(places.indices, id: \.self) { index in
                        let place = places[index]
                        Button {
                            place.openInMaps()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name ?? copy("Restauracja", "Restaurant"))
                                    .foregroundStyle(Theme.ink)
                                    .font(.body.weight(.medium))
                                if let address = place.placemark.title {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                        }
                    }
                } header: {
                    Text(copy("Szukaj w Mapach Apple", "Search Apple Maps"))
                } footer: {
                    Text(copy(
                        "Wyszukiwanie obsługują Mapy Apple, zgodnie z zasadami prywatności Apple. Doddy nie prosi o dostęp do dokładnej lokalizacji urządzenia.",
                        "Searches use Apple Maps under Apple's privacy policy. Doddy does not request access to the device's precise location."
                    ))
                }

                Section {
                    Text(copy(
                        "Doddy nie ma jeszcze uprawnienia do dodawania produktów do koszyków Uber Eats, Glovo, Wolt, Pyszne.pl ani Bolt Food. Nie pobiera tu cen ani nie śledzi zamówień. Nic nie zostało kupione przez otwarcie linku.",
                        "Doddy does not yet have permission to build carts in Uber Eats, Glovo, Wolt, Pyszne.pl or Bolt Food. It cannot retrieve provider prices or track orders here. Opening a link does not buy anything."
                    ))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle(copy("Zamów jedzenie", "Order food"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("Zamknij", "Close")) { dismiss() }
                }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    @MainActor
    private func searchRealPlaces() async {
        let dish = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let town = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dish.isEmpty, !town.isEmpty, !searching else { return }
        guard dish.count <= 80, town.count <= 80 else {
            places = []
            didSearch = true
            searchError = copy("Skróć nazwę dania lub miasta.", "Please shorten the dish or city name.")
            return
        }
        searching = true
        didSearch = false
        searchError = nil
        places = []
        defer { searching = false; didSearch = true }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(dish) restauracja \(town)"
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            places = Array(response.mapItems.prefix(12))
        } catch {
            searchError = copy(
                "Mapy Apple nie odpowiadają. Sprawdź połączenie i spróbuj ponownie.",
                "Apple Maps is unavailable. Check your connection and try again."
            )
        }
    }
}
