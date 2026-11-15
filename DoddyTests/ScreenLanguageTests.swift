import DoddyCore
import SwiftUI
import XCTest
@testable import Doddy

/// Settings › Language shows at once (decision `2026-11-14-language-switch-at-once`): with a language
/// chosen during this run, the app's words come from that language's table (`pl.lproj`), whatever iOS
/// picked when the app started. The test host starts in the simulator's English, so Polish here is the
/// case the owner saw: a choice that changed nothing until Doddy was opened again.
final class ScreenLanguageTests: XCTestCase {
    override func tearDown() {
        ScreenLanguage.use(nil)
        super.tearDown()
    }

    func testTheCodesWordsFollowTheChoiceAtOnce() {
        ScreenLanguage.use("pl")
        XCTAssertEqual(ScreenLanguage.code, "pl")
        XCTAssertEqual(NSLocalizedString("Settings", comment: ""), "Ustawienia")
        XCTAssertEqual(NSLocalizedString("Notifications", comment: ""), "Powiadomienia")
        XCTAssertEqual(String(format: NSLocalizedString("%lld notes", comment: ""), 3), "Notatki: 3")
        // The island's words, the cards that pick Polish themselves and the Polish web pages ask this.
        XCTAssertEqual(Bundle.main.preferredLocalizations, ["pl"])

        ScreenLanguage.use("en")
        XCTAssertEqual(NSLocalizedString("Settings", comment: ""), "Settings")
        XCTAssertEqual(NSLocalizedString("Notifications", comment: ""), "Notifications")
        XCTAssertEqual(Bundle.main.preferredLocalizations, ["en"])
    }

    func testALineWithNoTranslationStaysInEnglish() {
        ScreenLanguage.use("pl")
        XCTAssertEqual(NSLocalizedString("A line that is in no table", comment: ""), "A line that is in no table")
        XCTAssertEqual(Bundle.main.localizedString(forKey: "No such key", value: "Its default", table: nil), "Its default")
    }

    func testNoChoiceGivesBackWhatIOSPicked() {
        let launch = NSLocalizedString("Settings", comment: "")
        ScreenLanguage.use("pl")
        ScreenLanguage.use(nil)
        XCTAssertNil(ScreenLanguage.code)
        XCTAssertNil(ScreenLanguage.locale)
        XCTAssertEqual(NSLocalizedString("Settings", comment: ""), launch)
        XCTAssertEqual(Bundle.main.preferredLocalizations.first, ScreenLanguage.launchLocalization)
    }

    func testALanguageThisBuildHasNoTableForChangesNothing() {
        ScreenLanguage.use("sv")
        XCTAssertNil(ScreenLanguage.code)
    }

    /// SwiftUI gets the chosen language with the iPhone's own region, so dates and numbers keep their shape.
    func testTheLocaleKeepsTheRegion() throws {
        ScreenLanguage.use("pl")
        let locale = try XCTUnwrap(ScreenLanguage.locale)
        XCTAssertEqual(locale.language.languageCode?.identifier, "pl")
        XCTAssertEqual(locale.region, Locale.current.region)
    }

    /// `Text("…")` looks its words up in the chosen language too: drawn, it is the Polish written out.
    @MainActor
    func testSwiftUITextFollowsTheChoice() throws {
        ScreenLanguage.use("pl")
        let locale = try XCTUnwrap(ScreenLanguage.locale)
        for (key, polish) in [("Settings", "Ustawienia"), ("Notifications", "Powiadomienia")] {
            let looked = try XCTUnwrap(png(Text(LocalizedStringKey(key)).environment(\.locale, locale)), key)
            let written = try XCTUnwrap(png(Text(verbatim: polish).environment(\.locale, locale)), polish)
            XCTAssertEqual(looked, written, "Text(\"\(key)\") is drawn as \"\(polish)\"")
        }
    }

    @MainActor
    private func png(_ view: some View) -> Data? {
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = 2
        return renderer.uiImage?.pngData()
    }
}
