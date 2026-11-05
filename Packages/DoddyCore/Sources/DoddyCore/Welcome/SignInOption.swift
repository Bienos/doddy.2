import Foundation

// Sign-in for the welcome (ADR-595). The screens exist; the sign-in does not. Every option goes
// through this protocol, and the only implementation today says "not connected yet". The real
// sign-in (passkey and Face ID, Google, email) is a later milestone with its own approvals and
// App Review check. Doddy's real identity today is still the device session (ADR-563).

/// The ways the sign-in sheet offers.
public enum SignInOption: String, CaseIterable, Sendable {
    case faceID, google, email
}

/// What a sign-in attempt came to.
public enum SignInOutcome: Equatable, Sendable {
    /// Nothing is connected: the button did nothing but say so. The only outcome today.
    case notConnectedYet
    /// Reserved for the sign-in milestone. Nothing returns it yet, and a test keeps it that way.
    case signedIn
}

public protocol SignInProviding: Sendable {
    func signIn(with option: SignInOption) async -> SignInOutcome
}

/// Today's only provider: no backend, no SDK, no account. It never reports success.
public struct UnconnectedSignIn: SignInProviding {
    public init() {}

    public func signIn(with option: SignInOption) async -> SignInOutcome {
        .notConnectedYet
    }
}
