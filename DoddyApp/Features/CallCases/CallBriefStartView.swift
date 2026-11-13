import DoddyCore
import SwiftUI

/// The first screen of a new call (decision 2026-11-13-calls-one-field-brief): one field, "who and why", and the
/// contact pick as an option. Doddy's server asks a model to propose the brief from it and checks every field in
/// code; the existing editor then opens filled in for review, with the details folded away, and the card made from
/// what the editor sends is what the user approves (DOD-07). Nothing is dialled from here. "Fill in every field
/// myself" opens the full editor as before. Not compiled or run on a device yet.
struct CallBriefStartView: View {
    let list: CallCasesModel
    /// The empty brief with the user's first name from About you.
    let base: CallBriefDraft
    let onPrepared: (StoredCallCase) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var contact: CallBriefContact?
    @State private var pickingContact = false
    @State private var isDrafting = false
    @State private var message: String?
    @State private var review: CallBriefReview?

    init(list: CallCasesModel, base: CallBriefDraft, onPrepared: @escaping (StoredCallCase) -> Void) {
        self.list = list
        self.base = base
        self.onPrepared = onPrepared
    }

    var body: some View {
        Form {
            Section {
                TextField("Who and why", text: $text,
                          prompt: Text("For example: call the hairdresser Anna on Długa, 600 100 200, and ask if they have a free slot on Saturday"),
                          axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("callBrief.oneField")
                if let contact {
                    HStack {
                        Label(contact.name.isEmpty ? contact.number : contact.name, systemImage: "person.crop.circle.badge.checkmark")
                        Spacer()
                        Button("Remove", role: .destructive) { self.contact = nil }
                            .buttonStyle(.borderless)
                    }
                }
                Button {
                    pickingContact = true
                } label: {
                    Label("Pick from Contacts", systemImage: "person.crop.circle")
                }
            } header: {
                Text("Who and why")
            } footer: {
                Text("Write who Doddy calls and what to ask, with their number unless you pick a contact. Doddy fills in the rest; you check every field next, and nothing is dialled until you approve the card.")
            }

            Section {
                Button("Fill in every field myself") {
                    review = CallBriefReview(draft: base, detailsShown: true, notes: [])
                }
                .accessibilityIdentifier("callBrief.fullEditor")
            } footer: {
                Text("Doddy's server sends these words to Claude (Anthropic) to fill in the fields, with phone numbers taken out first, and doesn't keep them. A contact's number stays on this iPhone until you prepare the card.")
            }

            if let message {
                Section { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(Theme.error) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("New call")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { Task { await draft() } }
                    .disabled(!CallBriefDraft.oneFieldReady(text) || isDrafting)
                    .accessibilityIdentifier("callBrief.next")
            }
        }
        .disabled(isDrafting)
        .overlay { if isDrafting { ProgressView("Filling in the fields…") } }
        .navigationDestination(item: $review) { item in
            CallBriefEditorView(list: list, draft: item.draft, replacing: nil, detailsShown: item.detailsShown,
                                notes: item.notes, showsCancel: false, onPrepared: onPrepared)
        }
        .background(ContactNumberPicker(isPresented: $pickingContact) { picked in
            contact = CallBriefContact(name: picked.name, number: picked.number)
        })
    }

    /// Asks the server for a suggestion. Refused words (a PESEL, card or account number) keep the user here; any
    /// other failure opens the editor with their own words, so a call never depends on the model.
    private func draft() async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CallBriefDraft.oneFieldReady(words) else { return }
        message = nil
        guard let client = ServerConfig.client() else {
            review = fallback(words)
            return
        }
        isDrafting = true
        defer { isDrafting = false }
        do {
            let suggestion = try await client.draftCallBrief(text: words, contactName: contact?.name)
            let filled = CallBriefDraft.drafted(from: suggestion, text: words, contact: contact, principalName: base.principalName)
            var notes = [NSLocalizedString("Doddy filled this in from what you wrote. Check every field: the card shows exactly this, and nothing is dialled until you approve it.", comment: "")]
            for dropped in suggestion.dropped {
                // The picked contact's number replaces any number in the words, so a note about those doesn't apply.
                if dropped.field == "callee.phone", contact != nil { continue }
                let note = CallBriefStartText.note(dropped)
                if !notes.contains(note) { notes.append(note) }
            }
            review = CallBriefReview(draft: filled, detailsShown: false, notes: notes)
        } catch CallCaseError.briefRefused(field: "text", reason: let reason) {
            message = CallBriefStartText.refusedWords(reason)
        } catch {
            review = fallback(words)
        }
    }

    private func fallback(_ words: String) -> CallBriefReview {
        CallBriefReview(draft: .ownWords(words, contact: contact, principalName: base.principalName), detailsShown: true,
                        notes: [NSLocalizedString("Doddy couldn't fill this in just now, so most fields are empty. Fill them in yourself; nothing was dialled.", comment: "")])
    }
}

/// The editor opened from the first screen: the draft, whether the details start open, and what Doddy left out.
struct CallBriefReview: Identifiable, Hashable {
    let id = UUID()
    let draft: CallBriefDraft
    let detailsShown: Bool
    let notes: [String]

    static func == (a: CallBriefReview, b: CallBriefReview) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// What the first screen and the editor say about the server's checks.
enum CallBriefStartText {
    static func note(_ dropped: CallBriefSuggestion.Dropped) -> String {
        switch (dropped.field, dropped.reason) {
        case ("callee.phone", "several_numbers"):
            NSLocalizedString("There's more than one phone number in what you wrote. Type the one Doddy should call.", comment: "")
        case ("callee.phone", let reason):
            CallCaseText.destination(reason)
        case ("question", "question_commits"):
            CallCaseText.brief(field: dropped.field, reason: dropped.reason)
        case ("callee.name", "not_from_text"):
            NSLocalizedString("Doddy left out a name you didn't write. Type who Doddy calls.", comment: "")
        default:
            NSLocalizedString("Doddy left out something that can't go on a call card. Check the fields below.", comment: "")
        }
    }

    static func refusedWords(_ reason: String) -> String {
        switch reason {
        case "pesel_not_ticked":
            NSLocalizedString("Leave your PESEL out of this field. If Doddy really needs it, add it on the next screen as a fact marked PESEL.", comment: "")
        default:
            CallCaseText.brief(field: "text", reason: reason)
        }
    }
}
