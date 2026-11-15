import DoddyCore
import Foundation
import UIKit

/// Asks for the messaging token to be renewed whenever Doddy comes to the front (launch is `DoddyAccountServers.catchUp`).
/// Whether anything is due, once a day and one at a time are `MessagingTokenRenewal`'s rules (DoddyCore); this only listens.
@MainActor
enum MessagingRenewalTrigger {
    private static var observer: NSObjectProtocol?

    /// Once; later calls do nothing.
    static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await DoddyAccountServers.renewMessagingToken() }
        }
    }
}
