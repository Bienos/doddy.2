import XCTest
@testable import DoddyCore

final class AppLanguageTests: XCTestCase {
    func testEnglishIsTheDefault() {
        XCTAssertEqual(AppLanguage.default, .english)
        XCTAssertEqual(AppLanguage(stored: nil), .english)
        XCTAssertEqual(AppLanguage(stored: "klingon"), .english)
        XCTAssertEqual(AppLanguage(stored: "de"), .german)
        XCTAssertEqual(AppLanguage(stored: "system"), .followPhone)
    }

    func testEveryChoiceHasACodeAndAName() {
        for language in AppLanguage.allCases where language != .followPhone {
            XCTAssertEqual(language.code, language.rawValue)
            XCTAssertFalse(language.nativeName?.isEmpty ?? true, "\(language) needs its own name")
        }
        XCTAssertNil(AppLanguage.followPhone.code)
        XCTAssertNil(AppLanguage.followPhone.nativeName)
        // Followed by "same as this iPhone" last, English first.
        XCTAssertEqual(AppLanguage.allCases.first, .english)
        XCTAssertEqual(AppLanguage.allCases.last, .followPhone)
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)).count, AppLanguage.allCases.count)
    }

    func testMatchingAnAppleLanguagesEntry() {
        XCTAssertEqual(AppLanguage.matching("en-US"), .english)
        XCTAssertEqual(AppLanguage.matching("de-DE"), .german)
        XCTAssertEqual(AppLanguage.matching("pt-BR"), .portugueseBrazil)
        XCTAssertEqual(AppLanguage.matching("pt-PT"), .portugueseBrazil)
        XCTAssertEqual(AppLanguage.matching("zh-Hans-CN"), .chineseSimplified)
        XCTAssertEqual(AppLanguage.matching("zh-Hans"), .chineseSimplified)
        XCTAssertEqual(AppLanguage.matching("JA"), .japanese)
        XCTAssertNil(AppLanguage.matching("zh-Hant-TW"))
        XCTAssertNil(AppLanguage.matching("sv-SE"))
        XCTAssertNil(AppLanguage.matching(""))
    }

    func testWhatThePickerShows() {
        XCTAssertEqual(AppLanguage.chosen(stored: nil, appLanguages: nil), .english)
        XCTAssertEqual(AppLanguage.chosen(stored: "fr", appLanguages: nil), .french)
        // A choice made in Doddy wins over what the app's setting says.
        XCTAssertEqual(AppLanguage.chosen(stored: "fr", appLanguages: ["de"]), .french)
        // No choice in Doddy: a language picked in iOS Settings is shown.
        XCTAssertEqual(AppLanguage.chosen(stored: nil, appLanguages: ["es-ES"]), .spanish)
        // A language Doddy doesn't have: English, which is what iOS falls back to.
        XCTAssertEqual(AppLanguage.chosen(stored: nil, appLanguages: ["sv"]), .english)
        XCTAssertEqual(AppLanguage.chosen(stored: "system", appLanguages: nil), .followPhone)
    }

    func testLaunchWritesEnglishOnAFreshInstall() {
        XCTAssertEqual(AppLanguage.launchAction(stored: nil, appLanguages: nil), .set(["en"]))
    }

    func testLaunchKeepsALanguageSetInIOSSettings() {
        XCTAssertEqual(AppLanguage.launchAction(stored: nil, appLanguages: ["de"]), .leave)
        // The English written at an earlier launch is such a setting: nothing to rewrite.
        XCTAssertEqual(AppLanguage.launchAction(stored: nil, appLanguages: ["en"]), .leave)
    }

    func testLaunchAppliesAChoiceMadeInDoddy() {
        XCTAssertEqual(AppLanguage.launchAction(stored: "ja", appLanguages: nil), .set(["ja"]))
        XCTAssertEqual(AppLanguage.launchAction(stored: "ja", appLanguages: ["en"]), .set(["ja"]))
        XCTAssertEqual(AppLanguage.launchAction(stored: "ja", appLanguages: ["ja"]), .leave)
        XCTAssertEqual(AppLanguage.launchAction(stored: "pt-BR", appLanguages: ["pt-BR"]), .leave)
        // A saved value that is not a language is the default, not a crash.
        XCTAssertEqual(AppLanguage.launchAction(stored: "klingon", appLanguages: ["de"]), .set(["en"]))
    }

    func testFollowThePhoneRemovesTheSetting() {
        XCTAssertEqual(AppLanguage.launchAction(stored: "system", appLanguages: ["en"]), .remove)
        XCTAssertEqual(AppLanguage.launchAction(stored: "system", appLanguages: nil), .leave)
    }

    func testPolishKeepsTheOwnersLanguageWhenChosen() {
        XCTAssertEqual(AppLanguage.launchAction(stored: "pl", appLanguages: ["en"]), .set(["pl"]))
    }
}
