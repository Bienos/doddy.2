import Foundation
import Observation

/// State behind Settings → Doddy on the web (ADR-579): one sign-in code at a time, and the list of
/// browsers signed in to this account. Everything shown is the server's answer; a browser leaves
/// the list only after the server signed it out (or says it already was).
@MainActor
@Observable
public final class WebSignInModel {
    /// Why something didn't work, for the screen to say in the person's language.
    public enum Problem: Error, Equatable, Sendable {
        /// No Doddy server in this build.
        case notConfigured
        /// The server refused this iPhone's session even after a fresh sign-in.
        case signedOut
        /// Too many codes this hour; try again after about this many minutes.
        case tooMany(minutes: Int)
        case offline
        case unreadable
        case server
    }

    public enum CodeState: Equatable, Sendable {
        case none
        case asking
        case shown(WebLinkCode)
        case failed(Problem)
    }

    public enum BrowsersState: Equatable, Sendable {
        case loading
        case loaded([WebBrowserSession])
        case failed(Problem)
    }

    public private(set) var code: CodeState = .none
    public private(set) var browsers: BrowsersState = .loading
    /// Browsers being signed out right now.
    public private(set) var signingOut: Set<UUID> = []
    /// A sign-out that didn't go through.
    public private(set) var signOutProblem: Problem?

    private let makeClient: @Sendable () async -> (any WebLinkClient)?
    private let renewClient: @Sendable () async -> (any WebLinkClient)?
    private var client: (any WebLinkClient)?

    /// `makeClient` signs the phone in first if needed; `renewClient` gets a fresh session after
    /// the server said this one isn't valid (ADR-563), tried once per action.
    public init(
        makeClient: @escaping @Sendable () async -> (any WebLinkClient)?,
        renewClient: @escaping @Sendable () async -> (any WebLinkClient)?
    ) {
        self.makeClient = makeClient
        self.renewClient = renewClient
    }

    public func getCode() async {
        code = .asking
        switch await perform({ client throws(WebLinkError) in try await client.newCode() }) {
        case .success(let fresh): code = .shown(fresh)
        case .failure(let problem): code = .failed(problem)
        }
    }

    /// The shown code expired: back to the button, so an expired code is never typed.
    public func expireCode(now: Date) {
        if case .shown(let shown) = code, shown.secondsLeft(at: now) == 0 { code = .none }
    }

    public func refreshBrowsers() async {
        if case .loaded = browsers {} else { browsers = .loading }
        switch await perform({ client throws(WebLinkError) in try await client.browsers() }) {
        case .success(let list): browsers = .loaded(list.sorted { $0.lastSeenAt > $1.lastSeenAt })
        case .failure(let problem): browsers = .failed(problem)
        }
    }

    public func signOut(_ id: UUID) async {
        signingOut.insert(id)
        signOutProblem = nil
        defer { signingOut.remove(id) }
        let result: Result<Void, Problem> = await perform { client throws(WebLinkError) in
            do throws(WebLinkError) {
                try await client.signOut(browser: id)
            } catch {
                // Already signed out (it expired, or someone else signed it out): the same outcome.
                if error != .notFound { throw error }
            }
        }
        switch result {
        case .success:
            if case .loaded(let list) = browsers { browsers = .loaded(list.filter { $0.id != id }) }
        case .failure(let problem):
            signOutProblem = problem
        }
    }

    private func perform<T: Sendable>(_ action: (any WebLinkClient) async throws(WebLinkError) -> T) async -> Result<T, Problem> {
        if client == nil { client = await makeClient() }
        guard let current = client else { return .failure(.notConfigured) }
        do throws(WebLinkError) {
            return .success(try await action(current))
        } catch {
            guard error == .unauthenticated else { return .failure(Self.problem(error)) }
        }
        guard let renewed = await renewClient() else { return .failure(.signedOut) }
        client = renewed
        do throws(WebLinkError) {
            return .success(try await action(renewed))
        } catch {
            return .failure(Self.problem(error))
        }
    }

    static func problem(_ error: WebLinkError) -> Problem {
        switch error {
        case .notConfigured: .notConfigured
        case .unauthenticated: .signedOut
        case .rateLimited(let seconds): .tooMany(minutes: max(1, Int((Double(seconds ?? 60) / 60).rounded(.up))))
        case .transport: .offline
        case .unreadable, .notFound: .unreadable
        case .server: .server
        }
    }
}
