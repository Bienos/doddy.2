import DoddyCore
import SwiftUI

/// A page per person (ADR-341): the notes that mention "@Name", newest first, and the birthday on
/// the matching contact card only when Contacts is on and exactly one card matches. Nothing here
/// is stored about the person; the page is read from the notes each time.
struct PersonNotesView: View {
    @Environment(MemoryStore.self) private var store
    let person: String
    @State private var birthday: BirthdayContact?
    @State private var addingNote = false

    private var notes: [MemoryRecord] {
        // A private note shows here only after Face ID (ADR-310).
        let visible = AppLock.shared.privateUnlocked ? store.memories : PrivateNotesStore.current().shareable(store.memories)
        return NotePeople.notes(visible, about: person)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(verbatim: "@\(person)").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                if let birthday {
                    Label(birthdayText(birthday), systemImage: "gift")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("person.birthday")
                }
                Button { addingNote = true } label: {
                    Label(String(format: NSLocalizedString("New note about %@", comment: "Person page"), person), systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!store.isStorageAvailable)
                .accessibilityIdentifier("person.addNote")
                if notes.isEmpty {
                    Text("No note mentions this person any more.").foregroundStyle(Theme.secondaryText)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(notes) { record in
                            NavigationLink(value: MemoryNavigationRoute.note(record.id)) {
                                MemoryLinkCard(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("People are names you write with @ in a note, like @Marta. Doddy only reads them from your notes.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .padding(24)
        }
        .background(Theme.canvas).foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingNote) { CaptureView(startingText: NotePeople.newNoteText(about: person)) }
        .task { loadBirthday() }
    }

    /// Read on this iPhone only when the Contacts switch is on and iOS allows it.
    private func loadBirthday() {
        guard UserDefaults.standard.bool(forKey: VoiceConnection.contacts.preferenceKey),
              let contacts = DeviceConnections().birthdays() else { return }
        birthday = NotePeople.birthday(for: person, in: contacts)
    }

    private func birthdayText(_ contact: BirthdayContact) -> String {
        var parts = DateComponents()
        parts.month = contact.month
        parts.day = contact.day
        parts.year = 2000
        let day = Calendar(identifier: .gregorian).date(from: parts)?
            .formatted(.dateTime.day().month(.wide)) ?? "\(contact.day).\(contact.month)"
        return String(format: NSLocalizedString("Birthday: %@ (from %@ in Contacts)", comment: "Person page"), day, contact.name)
    }
}

/// People mentioned with @ (ADR-341), most mentioned first. Each chip opens the person's page.
struct MemoryPeopleRow: View {
    let people: [NotePerson]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(people) { person in
                    NavigationLink(value: MemoryNavigationRoute.person(person.name)) {
                        Text(verbatim: "@\(person.name) \(person.count)")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Theme.quietSurface, in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: NSLocalizedString("%@, %lld notes", comment: "Person chip"), person.name, person.count))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("People in your notes", comment: ""))
        .accessibilityIdentifier("memories.people")
    }
}
