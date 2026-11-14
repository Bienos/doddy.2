import Foundation
import XCTest
@testable import DoddyCore

/// The voice token client reads an answer only from the host it sent its bearer token to
/// (decision 2026-11-12-local-data-owner); redirects are refused before that in the app's URLSession delegate.
final class BearerHostTests: XCTestCase {
    private let asked = URL(string: "https://voice.example.com/api/voice-token")!

    func testTheSameServerIsRead() {
        XCTAssertTrue(BearerHost.answered(asked, sameAs: asked))
        XCTAssertTrue(BearerHost.answered(URL(string: "https://VOICE.example.com/api/voice-token?x=1"), sameAs: asked))
        XCTAssertTrue(BearerHost.answered(URL(string: "https://voice.example.com:443/api/voice-token"), sameAs: asked))
    }

    func testAnotherHostSchemeOrPortIsNot() {
        XCTAssertFalse(BearerHost.answered(URL(string: "https://elsewhere.example.net/api/voice-token"), sameAs: asked))
        XCTAssertFalse(BearerHost.answered(URL(string: "https://voice.example.com.evil.test/api"), sameAs: asked))
        XCTAssertFalse(BearerHost.answered(URL(string: "http://voice.example.com/api/voice-token"), sameAs: asked))
        XCTAssertFalse(BearerHost.answered(URL(string: "https://voice.example.com:8443/api/voice-token"), sameAs: asked))
    }

    func testNoAddressIsNotTheSameServer() {
        XCTAssertFalse(BearerHost.answered(nil, sameAs: asked))
        XCTAssertFalse(BearerHost.answered(URL(string: "file:///tmp/x"), sameAs: asked))
    }
}
