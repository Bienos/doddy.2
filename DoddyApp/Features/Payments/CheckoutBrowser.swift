import SwiftUI

// THROWAWAY DIAGNOSTIC BRANCH (not for merge): no SafariServices.
struct CheckoutBrowser: View {
    let url: URL
    let onClose: @MainActor () -> Void
    var body: some View { Button("Close") { onClose() } }
}
