@preconcurrency import Contacts
import DoddyCore
import Foundation

/// Contacts on this iPhone. Lookups return names, numbers and addresses for the screen; the voice
/// agent only ever receives names (VoiceToolReply.contacts).
final class SystemContactsGateway: ContactsGateway, @unchecked Sendable {
    private let store = CNContactStore()

    func authorization() -> SystemAuthorization {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .fullAccess
        @unknown default:
            // iOS 18 adds `.limited` (raw value 4): the user shared some contacts, which Doddy
            // may read. Anything newer is treated as no access until reviewed.
            return status.rawValue == 4 ? .fullAccess : .denied
        }
    }

    func requestAccess() async throws -> SystemAuthorization {
        _ = try await store.requestAccess(for: .contacts)
        return authorization()
    }

    func accountCount() async throws -> Int {
        try requireAccess()
        return try store.containers(matching: nil).count
    }

    func lookup(name: String) async throws -> [ContactMatch] {
        try requireAccess()
        let keys: [any CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let contacts = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
        return contacts.prefix(10).map { contact in
            let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            return ContactMatch(
                id: contact.identifier,
                displayName: fullName.isEmpty ? (contact.organizationName.isEmpty ? "No name" : contact.organizationName) : fullName,
                phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue },
                emailAddresses: contact.emailAddresses.map { $0.value as String })
        }
    }

    private func requireAccess() throws {
        guard authorization().allowsReading else { throw ConnectionError.notAuthorized(.contacts) }
    }
}
