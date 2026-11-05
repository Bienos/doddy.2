import Contacts
import ContactsUI
import SwiftUI

/// One phone number picked with Apple's contact picker, for a call brief (ADR-501).
struct PickedPhoneNumber: Equatable, Sendable {
    /// The contact's name as Contacts shows it; the card says the number came from this contact.
    let name: String
    let number: String
}

/// Apple's contact picker, limited to one phone number (ADR-501). It runs outside Doddy: the app
/// gets only the number the user tapped and that contact's name, and needs no Contacts permission.
/// Presented from a hidden host, since the picker misbehaves when wrapped in a SwiftUI sheet.
/// Not run on a device yet.
struct ContactNumberPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (PickedPhoneNumber) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, !context.coordinator.presenting, host.presentedViewController == nil else { return }
        context.coordinator.presenting = true
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        // A contact can't be picked as a whole: the user taps one of its numbers.
        picker.predicateForSelectionOfContact = NSPredicate(value: false)
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == %@", CNContactPhoneNumbersKey)
        DispatchQueue.main.async { host.present(picker, animated: true) }
    }

    @MainActor
    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactNumberPicker
        /// Set while a picker is up, so a second update doesn't build another.
        var presenting = false

        init(_ parent: ContactNumberPicker) {
            self.parent = parent
        }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            let number = (contactProperty.value as? CNPhoneNumber)?.stringValue
            let name = CNContactFormatter.string(from: contactProperty.contact, style: .fullName) ?? ""
            MainActor.assumeIsolated {
                presenting = false
                parent.isPresented = false
                if let number { parent.onPick(PickedPhoneNumber(name: name, number: number)) }
            }
        }

        nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            MainActor.assumeIsolated {
                presenting = false
                parent.isPresented = false
            }
        }
    }
}
