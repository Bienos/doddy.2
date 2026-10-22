import Foundation
import XCTest
@testable import DoddyCore

final class DeepLinkTests: XCTestCase {
    func testKnownPlaces() {
        XCTAssertEqual(DeepLink(url: URL(string: "doddy://home")!), .home)
        XCTAssertEqual(DeepLink(url: URL(string: "doddy://memories")!), .memories)
        XCTAssertEqual(DeepLink(url: URL(string: "DODDY://Settings")!), .settings)
        XCTAssertEqual(DeepLink(url: URL(string: "doddy://recordings")!), .recordings, "the Live Activity's Open button (ADR-588)")
        XCTAssertEqual(DeepLink(url: URL(string: "doddy://recordings/delete")!), .recordings, "a path is ignored: the link only ever opens the list")
    }

    func testBareSchemeOpensHome() {
        XCTAssertEqual(DeepLink(url: URL(string: "doddy://")!), .home)
    }

    func testRejectsOtherSchemesAndUnknownPlaces() {
        XCTAssertNil(DeepLink(url: URL(string: "https://home")!))
        XCTAssertNil(DeepLink(url: URL(string: "doddy://delete-all")!))
        XCTAssertNil(DeepLink(url: URL(string: "doddy://save?text=hello")!))
    }

    func testRoundTrip() {
        for link in DeepLink.allCases {
            XCTAssertEqual(DeepLink(url: link.url), link)
        }
    }
}
