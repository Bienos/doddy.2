import XCTest
@testable import DoddyCore

/// "What I can do" (decision 2026-11-09-what-i-can-do): which features are listed, and the status each one
/// claims. The costly mistake is claiming something works that hasn't been shown to, so most cases are those.
final class WhatICanDoTests: XCTestCase {
    private let shipping = CapabilityCatalog.shipping(serverConfigured: true)

    func testEveryFeatureIsListedWhenTheBuildShowsEverything() {
        let rows = WhatICanDo.rows(catalog: shipping, scope: .everything, serverConfigured: true)
        XCTAssertEqual(rows.map(\.ability), DoddyAbility.allCases)
    }

    func testEveryFeatureIsListedInTheShippingScope() {
        // Nothing is hidden since 10 Nov 2026 (decision 2026-11-10-no-beta-scope): the shipping list is the full list.
        let rows = WhatICanDo.rows(catalog: shipping, scope: .shipping, serverConfigured: true)
        XCTAssertEqual(rows.map(\.ability), DoddyAbility.allCases)
        for ability in rows.map(\.ability) {
            if let feature = ability.feature { XCTAssertTrue(ReleaseScope.shipping.shows(feature), "\(ability)") }
        }
    }

    func testAScopeThatHidesAFeatureStillDropsItsRow() {
        let rows = WhatICanDo.rows(catalog: shipping, scope: ReleaseScope(hidden: [.translator]), serverConfigured: true)
        XCTAssertFalse(rows.map(\.ability).contains(.translator))
    }

    func testCallsAreNeverClaimedToWork() {
        XCTAssertFalse(WhatICanDo.realCallRecorded, "change only with a recorded real call (S2_CALLS_STATUS)")
        for ability in [DoddyAbility.phoneCalls, .callsForYou] {
            XCTAssertEqual(WhatICanDo.status(of: ability, catalog: shipping, serverConfigured: true), .notTriedOnARealCall)
            XCTAssertEqual(WhatICanDo.status(of: ability, catalog: shipping, serverConfigured: false), .needsServer)
        }
        let calls = WhatICanDo.rows(catalog: shipping, scope: .everything, serverConfigured: true)
            .first { $0.ability == .phoneCalls }
        XCTAssertEqual(calls?.statusText, "Not tried on a real call yet")
    }

    func testOnlyNotesClaimReady() {
        let ready = DoddyAbility.allCases.filter {
            WhatICanDo.status(of: $0, catalog: shipping, serverConfigured: true) == .ready
        }
        XCTAssertEqual(ready, [.notes])
    }

    func testServerFeaturesSayWhenThereIsNoServer() {
        for ability in DoddyAbility.allCases {
            let status = WhatICanDo.status(of: ability, catalog: shipping, serverConfigured: false)
            if ability.needsServer {
                XCTAssertEqual(status, .needsServer, "\(ability)")
            } else {
                XCTAssertNotEqual(status, .needsServer, "\(ability)")
            }
        }
        XCTAssertEqual(WhatICanDo.statusText(.needsServer, .english), "Needs setup · this build isn’t connected to Doddy’s server")
    }

    func testCodeMissingFromTheBuildSaysSo() {
        // The M0 catalog has no voice, memory or reminders.
        for ability in [DoddyAbility.talk, .notes, .lists, .reminders] {
            XCTAssertEqual(WhatICanDo.status(of: ability, catalog: .m0, serverConfigured: true), .notInThisVersion, "\(ability)")
        }
    }

    func testEveryRowHasWordsInBothLanguages() {
        for ability in DoddyAbility.allCases {
            let english = WhatICanDo.text(ability, .english)
            let polish = WhatICanDo.text(ability, .polish)
            for words in [english, polish] {
                XCTAssertFalse(words.title.isEmpty)
                XCTAssertFalse(words.does.isEmpty)
                XCTAssertFalse(words.youControl.isEmpty)
            }
            XCTAssertNotEqual(english.does, polish.does, "\(ability)")
            XCTAssertNotEqual(english.youControl, polish.youControl, "\(ability)")
        }
        let polishRows = WhatICanDo.rows(catalog: shipping, scope: .everything, serverConfigured: true, language: .polish)
        XCTAssertEqual(polishRows.first { $0.ability == .phoneCalls }?.title, "Rozmowy telefoniczne")
        XCTAssertEqual(polishRows.first { $0.ability == .notes }?.statusText, "Gotowe")
    }

    /// BRAND_GUIDELINES §3.2: titles without a full stop, sentences with one, curly apostrophes, no exclamation
    /// marks or em dashes.
    func testWordsFollowTheProductVoice() {
        var texts: [String] = []
        for ability in DoddyAbility.allCases {
            for language in [NotificationLanguage.english, .polish] {
                let words = WhatICanDo.text(ability, language)
                XCTAssertFalse(words.title.hasSuffix("."), words.title)
                XCTAssertTrue(words.does.hasSuffix("."), words.does)
                XCTAssertTrue(words.youControl.hasSuffix(".") || words.youControl.hasSuffix("”."), words.youControl)
                texts += [words.title, words.does, words.youControl]
            }
        }
        for status in [AbilityStatus.ready, .inTesting, .needsServer, .notTriedOnARealCall, .notInThisVersion] {
            texts += [WhatICanDo.statusText(status, .english), WhatICanDo.statusText(status, .polish)]
        }
        for text in texts {
            XCTAssertFalse(text.contains("'"), "straight apostrophe: \(text)")
            XCTAssertFalse(text.contains("!"), text)
            XCTAssertFalse(text.contains("—"), text)
        }
    }

    /// No row claims more than the code does (BRAND_GUIDELINES §3.5).
    func testNoForbiddenClaims() {
        for ability in DoddyAbility.allCases {
            let words = WhatICanDo.text(ability, .english)
            let text = "\(words.title) \(words.does) \(words.youControl)".lowercased()
            for phrase in ["remembers", "knows you", "always listening", "never forgets", "syncs everywhere", "automatically"] {
                XCTAssertFalse(text.contains(phrase), "\(ability): \(phrase)")
            }
        }
    }

    func testEveryFeatureHasAShortExampleInBothLanguages() {
        for ability in DoddyAbility.allCases {
            for language in [NotificationLanguage.english, .polish] {
                let example = WhatICanDo.example(ability, language)
                XCTAssertFalse(example.isEmpty, "\(ability)")
                XCTAssertLessThanOrEqual(example.count, 60, "one short line: \(example)")
                XCTAssertFalse(example.contains("!"), "product voice: no exclamation marks")
            }
        }
        XCTAssertEqual(WhatICanDo.exampleLead(.messages, .polish), "Napisz na przykład", "Messages is typed")
        XCTAssertEqual(WhatICanDo.exampleLead(.talk, .polish), "Powiedz na przykład")
        XCTAssertEqual(WhatICanDo.exampleLead(.translator, .english), "Say, for example")
    }
}
