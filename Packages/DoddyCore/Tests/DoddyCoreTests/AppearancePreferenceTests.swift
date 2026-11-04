import XCTest
@testable import DoddyCore

/// ADR-702: light until the person picks otherwise (install, welcome, sign-in and first use).
final class AppearancePreferenceTests: XCTestCase {
    func testTheDefaultIsLight() {
        XCTAssertEqual(AppearancePreference.default, .light)
    }

    func testStoredValuesStayReadable() {
        // The raw values are what @AppStorage already holds on phones; renaming one would reset them.
        XCTAssertEqual(AppearancePreference(rawValue: "system"), .system)
        XCTAssertEqual(AppearancePreference(rawValue: "light"), .light)
        XCTAssertEqual(AppearancePreference(rawValue: "dark"), .dark)
        XCTAssertNil(AppearancePreference(rawValue: "sepia"))
    }
}
