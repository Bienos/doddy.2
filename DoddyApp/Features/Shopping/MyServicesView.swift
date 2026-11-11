import DoddyCore
import SwiftUI

/// The user's own list of public booking links. It is local to this iPhone; no Booksy or
/// SimplyBook.me account access, availability polling, booking write, or payment is performed.
struct MyServicesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("connectedServices.bookingLinks") private var stored = "[]"
    @State private var name = ""
    @State private var link = ""
    @State private var issue: String?
    private var items: SavedBookingServices { SavedBookingServices(stored: stored) }
    private let polish = NotificationLanguage.current == .polish

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if items.items.isEmpty {
                        Text(polish ? "Nie masz jeszcze zapisanych usługodawców." : "No saved service providers yet.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(items.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name).font(.headline)
                            Text(item.provider.title).font(.subheadline).foregroundStyle(Theme.secondaryText)
                            if let destination = item.bookingURL {
                                Link(destination: destination) {
                                    Label(polish ? "Otwórz stronę rezerwacji" : "Open booking page",
                                          systemImage: "arrow.up.right.square")
                                        .font(.subheadline)
                                }
                                .accessibilityIdentifier("services.openBooking")
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button(role: .destructive) {
                                stored = items.removing(id: item.id).stored
                            } label: {
                                Label(polish ? "Usuń" : "Remove", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(polish ? "Moje usługi" : "My services")
                } footer: {
                    Text(polish
                         ? "Linki są zapisane na tym iPhonie. DODDY nie ma dostępu do konta ani kalendarza usługodawcy."
                         : "Links stay on this iPhone. Doddy has no access to your provider account or calendar.")
                }

                Section {
                    TextField(polish ? "Nazwa, np. mój barber" : "Name, e.g. my barber", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("services.name")
                    TextField(polish ? "Link Booksy lub SimplyBook.me" : "Booksy or SimplyBook.me link", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("services.link")
                    Button {
                        guard let new = items.adding(name: name, url: link) else {
                            issue = polish
                                ? "Sprawdź nazwę i pełny link HTTPS do usługi na Booksy lub SimplyBook.me. Link nie może być duplikatem."
                                : "Check the name and full HTTPS Booksy or SimplyBook.me service URL. Duplicate links cannot be added."
                            return
                        }
                        stored = new.stored
                        name = ""
                        link = ""
                        issue = nil
                    } label: {
                        Label(polish ? "Dodaj usługodawcę" : "Add service provider", systemImage: "plus.circle.fill")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("services.add")
                    if let issue {
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.error)
                    }
                } header: {
                    Text(polish ? "Dodaj link" : "Add a link")
                } footer: {
                    Text(polish
                         ? "Po otwarciu linku potwierdzasz termin bezpośrednio w Booksy lub SimplyBook.me. DODDY nie może potwierdzić rezerwacji."
                         : "After opening, you choose and confirm the appointment with Booksy or SimplyBook.me. Doddy cannot confirm booking.")
                }
            }
            .navigationTitle(polish ? "Moje usługi" : "My services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(polish ? "Gotowe" : "Done") { dismiss() }
                }
            }
        }
    }
}
