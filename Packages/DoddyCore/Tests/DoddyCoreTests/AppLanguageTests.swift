import XCTest
@testable import DoddyCore

final class AppLanguageTests: XCTestCase {
    func testPolishIsTheDefault() {
        // Owner, 21 Oct 2026 (ADR-572): "it should be Polish".
        XCTAssertEqual(AppLanguage.default, .polish)
        XCTAssertEqual(AppLanguage(stored: nil), .polish)
        XCTAssertEqual(AppLanguage(stored: "klingon"), .polish)
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
        XCTAssertEqual(AppLanguage.chosen(stored: nil, appLanguages: nil), .polish)
        XCTAssertEqual(AppLanguage.chosen(stored: "fr", appLanguages: nil), .french)
        // A choice made in Doddy wins over what the app's setting says.
        XCTAssertEqual(AppLanguage.chosen(stored: "fr", appLanguages: ["de"]), .french)
        // No choice in Doddy: a language picked in iOS Settings is shown.
        XCTAssertEqual(AppLanguage.chosen(stored: nil, appLanguages: ["es-ES"]), .spanish)
        // A language Doddy doesn't have: the default.
        XCTAssertEqual(AppLanguage.chosen(stored: nil, appLanguages: ["sv"]), .polish)
        XCTAssertEqual(AppLanguage.chosen(stored: "system", appLanguages: nil), .followPhone)
    }

    func testLaunchWritesPolishOnAFreshInstall() {
        XCTAssertEqual(AppLanguage.launchAction(stored: nil, appLanguages: nil), .set(["pl"]))
        XCTAssertEqual(AppLanguage.launchAction(stored: nil, appLanguages: nil, polishDefaultApplied: false), .set(["pl"]))
    }

    func testLaunchKeepsALanguageSetInIOSSettings() {
        XCTAssertEqual(AppLanguage.launchAction(stored: nil, appLanguages: ["de"]), .leave)
        XCTAssertEqual(AppLanguage.launchAction(stored: nil, appLanguages: ["de"], polishDefaultApplied: false), .leave)
        // After the one-time switch, English set again in iOS Settings stays.
        XCTAssertEqual(AppLanguage.launchAction(stored: nil, appLanguages: ["en"]), .leave)
    }

    func testTheEnglishOldBuildsWroteBecomesPolishOnce() {
        // Builds before ADR-572 wrote ["en"] on their first launch: replaced once, if no choice was made in Doddy.
        XCTAssertEqual(AppLanguage.launchAction(stored: nil, appLanguages: ["en"], polishDefaultApplied: false), .set(["pl"]))
        // English picked in Doddy itself is a choice and stays.
        XCTAssertEqual(AppLanguage.launchAction(stored: "en", appLanguages: ["en"], polishDefaultApplied: false), .leave)
        // Several languages is not what the old default wrote.
        XCTAssertEqual(AppLanguage.launchAction(stored: nil, appLanguages: ["en", "pl"], polishDefaultApplied: false), .leave)
    }

    func testLaunchAppliesAChoiceMadeInDoddy() {
        XCTAssertEqual(AppLanguage.launchAction(stored: "ja", appLanguages: nil), .set(["ja"]))
        XCTAssertEqual(AppLanguage.launchAction(stored: "ja", appLanguages: ["en"]), .set(["ja"]))
        XCTAssertEqual(AppLanguage.launchAction(stored: "ja", appLanguages: ["ja"]), .leave)
        XCTAssertEqual(AppLanguage.launchAction(stored: "pt-BR", appLanguages: ["pt-BR"]), .leave)
        // A saved value that is not a language is the default, not a crash.
        XCTAssertEqual(AppLanguage.launchAction(stored: "klingon", appLanguages: ["de"]), .set(["pl"]))
    }

    func testFollowThePhoneRemovesTheSetting() {
        XCTAssertEqual(AppLanguage.launchAction(stored: "system", appLanguages: ["en"]), .remove)
        XCTAssertEqual(AppLanguage.launchAction(stored: "system", appLanguages: nil), .leave)
    }

    func testPolishKeepsTheOwnersLanguageWhenChosen() {
        XCTAssertEqual(AppLanguage.launchAction(stored: "pl", appLanguages: ["en"]), .set(["pl"]))
    }
}
