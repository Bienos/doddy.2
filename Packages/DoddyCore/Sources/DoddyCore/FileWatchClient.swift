import Foundation

// The app's side of the file-ready push (owner, 9 Nov 2026; server/messaging `POST /v1/file-watches`). When Doddy's
// backend starts making a file (`make_document`), the app hands the file's signed link to the messaging server, which
// asks that link whether the file is done and sends one push with no words. Best effort: this only decides whether a
// notification comes. Nothing about the file itself is reported as ready here; the files list and the push say that.

/// What the server answered to "tell me when this file is ready".
public enum FileWatchOutcome: Equatable, Sendable {
    /// The server will send one push when the file is ready or failed.
    case watching
    /// The server isn't set up for it (503): no push will come, and nothing is wrong with the file.
    case notAvailable
    /// The server refused the link or the request (400), or this account has its open files at the limit (409).
    case refused
    /// Any other answer. No push is promised.
    case unknown(status: Int)
}

private struct FileWatchBody: Encodable {
    let url: String
    let language: String
}

extension DoddyServerClient {
    /// Registers the file's link. `language` is "pl" or "en", the language the push is written in. Throws only for a
    /// transport or sign-in failure; every answer the server gave is a `FileWatchOutcome`.
    public func watchFile(link: URL, language: String) async throws -> FileWatchOutcome {
        let body = try JSONEncoder().encode(FileWatchBody(url: link.absoluteString, language: language == "pl" ? "pl" : "en"))
        let response = try await authorized(.post, "/v1/file-watches", body: body)
        switch response.status {
        case 201: return .watching
        case 503: return .notAvailable
        case 400, 409: return .refused
        default: return .unknown(status: response.status)
        }
    }
}
