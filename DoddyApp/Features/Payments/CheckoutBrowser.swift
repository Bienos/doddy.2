import SafariServices
import SwiftUI

/// A shop's own checkout page, inside Doddy (ADR-490). Safari's view, not a web view Doddy
/// controls: Doddy can't read or fill the page, can't see what the user types, and Safari keeps
/// its own cookies. Besides the Connected Apps sign-in, the only place the app opens web pages
/// (scripts/check_forbidden_capabilities.sh). The address was checked by Doddy's server first.
struct CheckoutBrowser: UIViewControllerRepresentable {
    let url: URL
    let onClose: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .done
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onClose: @MainActor () -> Void

        init(onClose: @escaping @MainActor () -> Void) {
            self.onClose = onClose
        }

        nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            MainActor.assumeIsolated { onClose() }
        }
    }
}
