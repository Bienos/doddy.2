import DoddyCore
import SwiftUI

/// The user can review a Vinted link they explicitly shared and ask for a separate comparison
/// of similar products. Doddy does NOT fetch the Vinted item, inspect its photos, verify the
/// seller, authenticate the item, or buy it. Price and product name are entered by the person.
struct VintedListingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let listing: SharedVintedListing
    @State private var itemName = ""
    @State private var askingPrice = ""
    @State private var message: String?
    @State private var comparison = ""
    @State private var showTasks = false
    private let polish = NotificationLanguage.current == .polish

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Link(destination: listing.url) {
                        Label(polish ? "Otwórz oryginalne ogłoszenie" : "Open original listing",
                              systemImage: "arrow.up.right.square")
                    }
                    Text(polish
                         ? "DODDY nie skanuje automatycznie Vinted. Opis i cenę wpisujesz Ty; dane sprzedawcy nie są weryfikowane."
                         : "Doddy does not automatically scan Vinted. You provide the description and asking price; the seller is not verified.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                } header: {
                    Text(polish ? "Udostępniona oferta Vinted" : "Shared Vinted listing")
                }

                Section {
                    TextField(polish ? "Co to za przedmiot? Model i rozmiar" : "Product name, model and size", text: $itemName, axis: .vertical)
                        .lineLimit(2...3)
                        .accessibilityIdentifier("vinted.product")
                    TextField(polish ? "Cena z ogłoszenia w PLN (opcjonalnie)" : "Listing price in PLN (optional)", text: $askingPrice)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("vinted.price")
                    if let message {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.error)
                    }
                } header: {
                    Text(polish ? "Dane podane przez Ciebie" : "Details you provide")
                }

                Section {
                    Button {
                        guard let prompt = SharedVintedListing.comparisonPrompt(
                            product: itemName, askingPrice: askingPrice, polish: polish
                        ) else {
                            message = polish ? "Wpisz nazwę produktu (3–120 znaków) i opcjonalną cenę liczbową." :
                                "Enter a product name (3–120 characters) and optionally a numeric price."
                            return
                        }
                        comparison = prompt
                        message = nil
                        showTasks = true
                    } label: {
                        Label(polish ? "Porównaj ceny podobnych produktów" : "Research comparable prices",
                              systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("vinted.compare")
                    Text(polish
                         ? "Otworzy się zadanie z uzupełnionym opisem. Nic nie zostanie wysłane bez Twojego zatwierdzenia. Link Vinted nie zostanie przekazany do zadania."
                         : "A task opens with a prepared description. Nothing is sent until you approve. The Vinted URL is not sent to the task.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                Section {
                    Text(polish
                         ? "Przed zakupem sprawdź zdjęcia rzeczywistego przedmiotu, stan, rozmiar, historię sprzedawcy i koszt dostawy. Nie płać poza platformą, jeśli nie rozumiesz ryzyka."
                         : "Before buying, check actual-item photos, condition, size, seller history, and delivery cost. Avoid off-platform payment requests.")
                    Text(polish
                         ? "Porównanie cen nie potwierdza autentyczności ani bezpieczeństwa sprzedawcy."
                         : "A price comparison does not authenticate an item or verify the seller.")
                        .foregroundStyle(Theme.secondaryText)
                } header: {
                    Text(polish ? "Co jeszcze sprawdzić" : "Before you buy")
                }
            }
            .navigationTitle(polish ? "Sprawdź Vinted" : "Review Vinted listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(polish ? "Gotowe" : "Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showTasks) {
                ErrandsView(initialWords: comparison)
            }
        }
    }
}
