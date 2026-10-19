import DoddyCore
import SwiftUI

// THROWAWAY DIAGNOSTIC BRANCH (not for merge): the same API with no PassKit, to test whether linking
// PassKit empties the capture keyboard's toolbar.

enum ApplePaySupport {
    static var merchantIdentifier: String? { nil }
    @MainActor static var isAvailable: Bool { false }
}

struct ApplePayButton: View {
    let action: () -> Void
    var body: some View { Button("Apple Pay", action: action) }
}

enum ApplePayOutcome: Equatable, Sendable {
    case notShown, cancelled, authorized
}

@MainActor
final class ApplePayPresenter {
    typealias Authorize = @MainActor @Sendable (ApplePayTokenData) async -> Bool
    func present(_ sheet: ApplePaySheet, authorize: @escaping Authorize) async -> ApplePayOutcome { .notShown }
}
