import AuthenticationServices
import DoddyCore
import UIKit

/// Opens the hosted connection page in the system authentication browser (RFC 8252: no
/// embedded web view, no login form inside Doddy). The session is ephemeral, so Google sign-in
/// cookies are not shared with Safari.
struct SystemWebAuthenticator: WebAuthenticator {
    func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL {
        let result: Result<URL, WebAuthenticationError> = await withCheckedContinuation { continuation in
            Task { @MainActor in
                AuthenticationSessionRunner.shared.start(url: url, scheme: callbackScheme) { continuation.resume(returning: $0) }
            }
        }
        return try result.get()
    }
}

@MainActor
private final class AuthenticationSessionRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthenticationSessionRunner()
    /// Kept alive until the session finishes; ASWebAuthenticationSession is cancelled if released.
    private var session: ASWebAuthenticationSession?

    func start(url: URL, scheme: String, completion: @escaping @MainActor @Sendable (Result<URL, WebAuthenticationError>) -> Void) {
        guard session == nil else { return completion(.failure(.failed)) }
        let handler: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
            Task { @MainActor in
                self?.session = nil
                if let callbackURL {
                    completion(.success(callbackURL))
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    completion(.failure(.canceled))
                } else {
                    completion(.failure(.failed))
                }
            }
        }
        let session: ASWebAuthenticationSession
        if #available(iOS 17.4, *) {
            session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme), completionHandler: handler)
        } else {
            session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme, completionHandler: handler)
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.session = session
        if !session.start() {
            self.session = nil
            completion(.failure(.failed))
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
