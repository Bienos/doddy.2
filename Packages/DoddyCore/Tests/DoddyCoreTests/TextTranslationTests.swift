import XCTest
@testable import DoddyCore

/// Translate text without internet (ADR-346): what the app checks before asking iOS.
final class TextTranslationTests: XCTestCase {
    func testTextIsCheckedBeforeTranslating() {
        XCTAssertEqual(TextTranslation.check("  Where is the station? ", from: "en", to: "pl"), .success("Where is the station?"))
        XCTAssertEqual(TextTranslation.check(" ", from: "en", to: "pl"), .failure(.empty))
        XCTAssertEqual(TextTranslation.check("Hi", from: "pl", to: "pl"), .failure(.sameLanguage))
        XCTAssertEqual(TextTranslation.check(String(repeating: "a", count: 2001), from: "en", to: "pl"), .failure(.tooLong))
    }

    func testOwnersLanguageFirstAndADifferentDefault() {
        XCTAssertEqual(TextTranslation.languages(first: "pl").first?.code, "pl")
        XCTAssertEqual(TextTranslation.languages(first: "pl").count, TranslatorLanguages.all.count)
        XCTAssertEqual(TextTranslation.defaultTarget(for: "pl"), "en")
        XCTAssertEqual(TextTranslation.defaultTarget(for: "en"), "pl")
    }
}
