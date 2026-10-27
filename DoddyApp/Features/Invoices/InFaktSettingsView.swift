import DoddyCore
import SwiftUI
import UIKit

/// Settings › Invoices (inFakt) (ADR-640): the person's own inFakt key, kept in this iPhone's Keychain,
/// and a look at how an invoice card is laid out. Saving a key sends nothing anywhere, and while
/// `InFaktAPI.createVerified` is false nothing can be sent to inFakt at all: the screen says so.
/// The key is shown masked and never read back out; Save and Remove are confirmed by asking the
/// Keychain again. Not seen on a device in this build (docs/implementation/INFAKT_STATUS.md).
struct InFaktSettingsView: View {
    private let keys = AccountKeyStore.manager(for: .inFakt)
    @State private var state: AccountKeyState = .none
    @State private var pasted = ""
    @State private var message: String?
    @State private var messageIsError = false
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section {
                if !InFaktAPI.createVerified {
                    Text("Sending invoices to inFakt isn't switched on in this build. Until a test with a real inFakt test account has shown exactly how inFakt takes an invoice, nothing is sent and no invoice is issued. You can already save your key and see how an invoice card looks.")
                }
            }

            Section {
                switch state {
                case .none:
                    StatusRow(title: "Key", value: NSLocalizedString("Not saved", comment: ""))
                case .saved(let masked):
                    StatusRow(title: "Key", value: masked)
                        .accessibilityIdentifier("infakt.keyState")
                    Button("Remove key", role: .destructive) { confirmRemove = true }
                        .accessibilityIdentifier("infakt.remove")
                        .confirmationDialog("Remove your inFakt key?", isPresented: $confirmRemove, titleVisibility: .visible) {
                            Button("Remove key", role: .destructive) { remove() }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("The key is deleted from this iPhone's Keychain. Your inFakt account and its invoices are not touched.")
                        }
                case .unavailable:
                    Label("The Keychain couldn't be read, so Doddy can't tell whether a key is saved.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                }
                SecureField("Paste your inFakt key", text: $pasted)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("infakt.paste")
                Button("Paste the key from the clipboard") { pasteKey() }
                    .accessibilityIdentifier("infakt.pasteButton")
                Button(state.isSaved ? NSLocalizedString("Replace key", comment: "") : NSLocalizedString("Save key", comment: "")) { save() }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("infakt.save")
                if let message {
                    Label(message, systemImage: messageIsError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(messageIsError ? Theme.error : Theme.confirmed)
                }
            } header: {
                Text("Your inFakt key")
            } footer: {
                Text("The key stays in this iPhone's Keychain: it isn't synced to iCloud or moved to another iPhone, never goes to Doddy's server and is never put in a message. Make it in inFakt under Settings › API and give it only the rights it needs.")
                    + Text(verbatim: " ")
                    + Text(verbatim: InFaktAPI.neededScopes.joined(separator: ", ") + ".")
            }

            Section {
                NavigationLink {
                    InvoiceExampleView()
                } label: {
                    Text("See how an invoice card looks")
                }
                .accessibilityIdentifier("infakt.example")
            } footer: {
                Text("An example with gaps on purpose. It isn't your invoice.")
            }
        }
        .settingsPage()
        .navigationTitle("Invoices (inFakt)")
        .onAppear { state = keys.state() }
    }

    /// Puts the clipboard into the key field and nothing more: the field is secure, so the key is not
    /// shown, and it is checked and kept only when the person taps Save.
    private func pasteKey() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show(NSLocalizedString("The clipboard has no text.", comment: ""), error: true)
            return
        }
        pasted = text
        message = nil
    }

    private func save() {
        switch keys.save(pasted: pasted) {
        case .saved(let masked):
            pasted = ""
            show(String(format: NSLocalizedString("Key saved in this iPhone's Keychain (%@).", comment: ""), masked), error: false)
        case .notAKey:
            show(NSLocalizedString("That doesn't look like a key. Paste it again without extra lines or spaces.", comment: ""), error: true)
        default:
            show(NSLocalizedString("The key couldn't be saved: the Keychain didn't keep it. Nothing is saved.", comment: ""), error: true)
        }
        state = keys.state()
    }

    private func remove() {
        switch keys.remove() {
        case .removed:
            show(NSLocalizedString("Key removed from this iPhone.", comment: ""), error: false)
        default:
            show(NSLocalizedString("The key couldn't be removed: the Keychain still has it.", comment: ""), error: true)
        }
        state = keys.state()
    }

    private func show(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }
}
