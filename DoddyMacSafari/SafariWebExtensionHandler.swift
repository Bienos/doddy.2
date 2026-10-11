import DoddyCore
import Foundation
import SafariServices

/// The native side of "Save to Doddy" in Safari on the Mac (ADR-353). The popup sends the page's
/// title, address and the text the user had selected, and only after the user pressed "Send to
/// Doddy". This handler builds a `WebClip`, turns it into a note's words and leaves it in the Mac
/// clip inbox in the App Group (ADR-352). The Mac app lists it and saves it only when the user
/// presses Save there.
///
/// Privacy rules: this extension saves no note, opens no database and makes no network request.
/// It reads nothing from the page itself (the popup reads the title, address and selection once,
/// on the user's click). It never logs the clip's text or address, and it replies with a status
/// only: sent, full, not_set_up, nothing or failed. Only "sent" means the clip is waiting in Doddy
/// (the file was written and read back); everything else means nothing was kept.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let status = Self.status(forMessage: request?.userInfo?[SFExtensionMessageKey])

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["status": status]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    /// The reply for one message from the popup. Never throws; a problem is "failed".
    static func status(forMessage raw: Any?) -> String {
        guard let message = unwrapped(raw), let clip = WebClip(message: message) else { return "nothing" }
        guard ClipInboxLocation.isAvailable, let inbox = ClipInboxLocation.inbox else { return "not_set_up" }
        guard let item = clip.item(sharedAt: .now) else { return "nothing" }
        do {
            switch try inbox.add(item) {
            case .added: return "sent"
            case .full: return "full"
            }
        } catch {
            return "failed"
        }
    }

    /// Safari hands the message either as the dictionary itself or wrapped as `["message": [...]]`,
    /// depending on the macOS version.
    static func unwrapped(_ raw: Any?) -> [String: Any]? {
        guard let dictionary = raw as? [String: Any] else { return nil }
        if dictionary["title"] == nil, dictionary["url"] == nil, dictionary["selection"] == nil,
           let inner = dictionary["message"] as? [String: Any] {
            return inner
        }
        return dictionary
    }
}
