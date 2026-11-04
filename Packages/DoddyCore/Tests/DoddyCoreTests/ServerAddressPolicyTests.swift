import XCTest
@testable import DoddyCore

/// ADR-720: the address the phone signs in to. The device ID goes to whatever address this lets through,
/// so a shipped build uses the built-in one and nothing typed.
final class ServerAddressPolicyTests: XCTestCase {
    private let builtIn = "https://doddy.example.test"

    private func url(_ text: String) throws -> URL { try XCTUnwrap(URL(string: text), text) }

    // MARK: accepts

    func testHttpsIsAcceptedEverywhere() throws {
        for debug in [false, true] {
            XCTAssertTrue(ServerAddressPolicy.accepts(try url("https://doddy.example.test"), debug: debug))
            XCTAssertTrue(ServerAddressPolicy.accepts(try url("https://doddy.example.test:8443/api"), debug: debug))
            XCTAssertTrue(ServerAddressPolicy.accepts(try url("HTTPS://Doddy.Example.Test"), debug: debug), "the scheme's case doesn't matter")
        }
    }

    func testPlainHttpIsAcceptedOnlyToThisComputerAndOnlyInADevelopmentBuild() throws {
        for address in ["http://localhost", "http://localhost:3000", "http://127.0.0.1:8080", "http://[::1]:8080", "http://LOCALHOST:3000"] {
            XCTAssertTrue(ServerAddressPolicy.accepts(try url(address), debug: true), address)
            XCTAssertFalse(ServerAddressPolicy.accepts(try url(address), debug: false), "\(address) in a shipped build")
        }
        for address in ["http://doddy.example.test", "http://192.168.1.20:3000", "http://10.0.0.5", "http://localhost.evil.example",
                        "http://127.0.0.1.evil.example", "http://0.0.0.0", "http://127.0.0.2", "http://evil.example/localhost"] {
            XCTAssertFalse(ServerAddressPolicy.accepts(try url(address), debug: true), "\(address) even in a development build")
            XCTAssertFalse(ServerAddressPolicy.accepts(try url(address), debug: false), address)
        }
    }

    func testOtherSchemesAndAddressesWithoutAHostAreRefused() throws {
        for address in ["ftp://doddy.example.test", "file:///etc/passwd", "javascript:alert(1)", "doddy://home", "wss://doddy.example.test",
                        "https://", "https:///path", "doddy.example.test", "/v1/session/device"] {
            guard let parsed = URL(string: address) else { continue }
            for debug in [false, true] { XCTAssertFalse(ServerAddressPolicy.accepts(parsed, debug: debug), "\(address) debug=\(debug)") }
        }
    }

    /// In `https://trusted.example@other.example` the host is `other.example`; the part before the `@` is a
    /// user name. Never accepted, so a pasted lookalike can't pass as the real address.
    func testAnAddressWithAUserNameOrPasswordIsRefused() throws {
        for address in ["https://doddy.example.test@evil.example", "https://user:secret@doddy.example.test",
                        "https://doddy.example.test:443@evil.example/", "http://localhost@evil.example"] {
            let parsed = try url(address)
            for debug in [false, true] { XCTAssertFalse(ServerAddressPolicy.accepts(parsed, debug: debug), "\(address) debug=\(debug)") }
        }
    }

    // MARK: resolve

    /// The finding: a shipped build sent the device ID to whatever was typed in Settings › Advanced.
    func testAShippedBuildIgnoresWhatWasTyped() throws {
        let resolved = ServerAddressPolicy.resolve(typed: "https://evil.example", builtIn: builtIn, debug: false)
        XCTAssertEqual(resolved, try url(builtIn))
        XCTAssertEqual(ServerAddressPolicy.resolve(typed: "http://localhost:3000", builtIn: builtIn, debug: false), try url(builtIn))
        XCTAssertEqual(ServerAddressPolicy.resolve(typed: "   \n", builtIn: builtIn, debug: false), try url(builtIn))
        XCTAssertEqual(ServerAddressPolicy.resolve(typed: nil, builtIn: " \(builtIn) ", debug: false), try url(builtIn), "spaces around the built-in address are trimmed")
    }

    func testAShippedBuildWithoutAUsableBuiltInAddressHasNoServer() {
        XCTAssertNil(ServerAddressPolicy.resolve(typed: "https://evil.example", builtIn: nil, debug: false))
        XCTAssertNil(ServerAddressPolicy.resolve(typed: nil, builtIn: "", debug: false))
        XCTAssertNil(ServerAddressPolicy.resolve(typed: nil, builtIn: "http://doddy.example.test", debug: false), "the built-in address must be https too")
        XCTAssertNil(ServerAddressPolicy.resolve(typed: nil, builtIn: "http://localhost:3000", debug: false), "no plain http in a shipped build, even to localhost")
        XCTAssertNil(ServerAddressPolicy.resolve(typed: nil, builtIn: "not a url", debug: false))
    }

    func testADevelopmentBuildUsesTheTypedAddressWhenItPassesAndTheBuiltInOneWhenNothingWasTyped() throws {
        XCTAssertEqual(ServerAddressPolicy.resolve(typed: "https://dev.example.test", builtIn: builtIn, debug: true), try url("https://dev.example.test"))
        XCTAssertEqual(ServerAddressPolicy.resolve(typed: "  http://localhost:3000 ", builtIn: builtIn, debug: true), try url("http://localhost:3000"))
        XCTAssertEqual(ServerAddressPolicy.resolve(typed: "http://[::1]:3000", builtIn: builtIn, debug: true), try url("http://[::1]:3000"))
        XCTAssertEqual(ServerAddressPolicy.resolve(typed: "", builtIn: builtIn, debug: true), try url(builtIn))
        XCTAssertEqual(ServerAddressPolicy.resolve(typed: nil, builtIn: builtIn, debug: true), try url(builtIn))
    }

    /// A typed address that is refused gives no server, not a quiet fall back to the built-in one: the
    /// developer is told "not set up" instead of testing against the wrong server.
    func testADevelopmentBuildDoesNotFallBackWhenTheTypedAddressIsRefused() {
        XCTAssertNil(ServerAddressPolicy.resolve(typed: "http://dev.example.test", builtIn: builtIn, debug: true))
        XCTAssertNil(ServerAddressPolicy.resolve(typed: "http://192.168.1.20:3000", builtIn: builtIn, debug: true))
        XCTAssertNil(ServerAddressPolicy.resolve(typed: "ftp://dev.example.test", builtIn: builtIn, debug: true))
        XCTAssertNil(ServerAddressPolicy.resolve(typed: "https://doddy.example.test@evil.example", builtIn: builtIn, debug: true))
        XCTAssertNil(ServerAddressPolicy.resolve(typed: "dev.example.test", builtIn: builtIn, debug: true))
    }
}
