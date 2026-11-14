@testable import DoddyCore
import XCTest

/// What the price-alerts screen says: Polish plurals, the lines on one alert, and refusals that never claim a save or a
/// delete the server didn't confirm.
final class DealWatchWordsTests: XCTestCase {
    private func watch(maxPriceMinor: Int? = nil, chains: [DealsChain]? = nil, endsAt: String = "2026-12-01T10:00:00.000Z", found: Int = 0) -> DealWatch {
        DealWatch(id: "0b1c8f4e-3d1a-4f7e-9a55-2c6f1e8a7b10", item: "masło", maxPriceMinor: maxPriceMinor, chains: chains, language: "pl",
                  createdAt: "2026-11-14T10:00:00.000Z", endsAt: endsAt, found: found)
    }

    func testPolishCountsOffersTheWayPolishDoes() {
        let expected: [(Int, String)] = [
            (1, "1 oferta"), (2, "2 oferty"), (4, "4 oferty"), (5, "5 ofert"), (11, "11 ofert"), (12, "12 ofert"), (14, "14 ofert"),
            (21, "21 ofert"), (22, "22 oferty"), (25, "25 ofert"), (112, "112 ofert"), (122, "122 oferty"),
        ]
        for (n, text) in expected { XCTAssertEqual(DealWatchWords.offersCount(n, .polish), text, "\(n)") }
        XCTAssertEqual(DealWatchWords.offersCount(1, .english), "1 offer")
        XCTAssertEqual(DealWatchWords.offersCount(3, .english), "3 offers")
    }

    func testNewOffersAreCountedInWordsAndNothingIsClaimedWhenThereAreNone() {
        XCTAssertEqual(DealWatchWords.foundLine(watch(found: 0), .polish), "Nic nowego jeszcze nie znalazłem")
        XCTAssertEqual(DealWatchWords.foundLine(watch(found: 0), .english), "Nothing new found yet")
        XCTAssertEqual(DealWatchWords.foundLine(watch(found: 1), .polish), "1 nowa oferta")
        XCTAssertEqual(DealWatchWords.foundLine(watch(found: 3), .polish), "3 nowe oferty")
        XCTAssertEqual(DealWatchWords.foundLine(watch(found: 5), .polish), "5 nowych ofert")
        XCTAssertEqual(DealWatchWords.foundLine(watch(found: 1), .english), "1 new offer")
        XCTAssertEqual(DealWatchWords.foundLine(watch(found: 4), .english), "4 new offers")
    }

    func testThePriceLineSaysTheNumberTheServerKeptOrAnyPrice() {
        XCTAssertEqual(DealWatchWords.priceLine(watch(maxPriceMinor: 500), .polish), "Do \(Money(minor: 500).text(.polish))")
        XCTAssertEqual(DealWatchWords.priceLine(watch(maxPriceMinor: 500), .english), "Up to \(Money(minor: 500).text(.english))")
        XCTAssertEqual(DealWatchWords.priceLine(watch(), .polish), "Każda cena")
        XCTAssertEqual(DealWatchWords.priceLine(watch(), .english), "Any price")
    }

    func testTheShopsLineNamesThePickedShopsAndSaysAllWhenItIsAll() {
        XCTAssertEqual(DealWatchWords.shopsLine(watch(), .english), "All shops with leaflets")
        XCTAssertEqual(DealWatchWords.shopsLine(watch(chains: []), .polish), "Wszystkie sklepy z gazetkami")
        XCTAssertEqual(DealWatchWords.shopsLine(watch(chains: DealWatchRequest.catalogued.reversed()), .english), "All shops with leaflets",
                       "the whole list in another order is still all of them")
        XCTAssertEqual(DealWatchWords.shopsLine(watch(chains: [.biedronka, .lidl]), .english), "\(DealsChain.biedronka.name), \(DealsChain.lidl.name)")
    }

    func testTheEndLineCountsDaysAndGuessesNothing() throws {
        let now = try XCTUnwrap(ServerDates.parse("2026-11-14T10:00:00.000Z"))
        XCTAssertEqual(DealWatchWords.endsLine(watch(), now: now, .polish), "Kończy się za 17 dni")
        XCTAssertEqual(DealWatchWords.endsLine(watch(), now: now, .english), "Ends in 17 days")
        let late = try XCTUnwrap(ServerDates.parse("2026-12-01T00:00:00.000Z"))
        XCTAssertEqual(DealWatchWords.endsLine(watch(), now: late, .english), "Ends within a day")
        XCTAssertNil(DealWatchWords.endsLine(watch(endsAt: "soon"), now: now, .english), "a date that doesn't read says nothing")
    }

    func testWhatWasSavedIsSaidOnlyWithWhatTheServerAnswered() {
        XCTAssertTrue(DealWatchWords.saved(offers: 0, .english).contains("isn't in the leaflets now"))
        let some = DealWatchWords.saved(offers: 3, .polish)
        XCTAssertTrue(some.contains("3 oferty"))
        XCTAssertTrue(some.contains("O tych już wiesz"), "what was there already is never pushed, and the words say so")
        XCTAssertTrue(DealWatchWords.saved(offers: 3, .english).contains("You know about these"))
    }

    func testEveryRefusalSaysNothingWasChangedExceptWhereItMayHaveBeen() {
        let nothingSaved: [DealWatchesError] = [.disabled, .tooManyWatches, .serverFull, .invalid(fields: ["item"]), .server(.offline), .server(.rateLimited)]
        for error in nothingSaved {
            XCTAssertTrue(DealWatchWords.refusal(error, .polish).contains("Nic nie zostało"), "\(error)")
            XCTAssertTrue(DealWatchWords.refusal(error, .english).contains("Nothing was"), "\(error)")
            XCTAssertFalse(DealWatchWords.refusal(error, .english).hasPrefix("Saved"), "\(error)")
        }
        let unknown = DealWatchWords.refusal(.outcomeUnknown, .english)
        XCTAssertTrue(unknown.contains("may exist"))
        XCTAssertTrue(unknown.contains("won't add it again by myself"))
        XCTAssertFalse(unknown.contains("Nothing was"), "an unknown outcome must not say nothing happened")
        XCTAssertTrue(DealWatchWords.refusal(.outcomeUnknown, .polish).contains("Nie dodam go sam jeszcze raz"))
        XCTAssertEqual(DealWatchWords.refusal(.notFound, .english), "That alert is gone.")
    }

    func testTheIntroSaysTheAlertOnlyTellsAndWhatTheServerKeeps() {
        for language in [NotificationLanguage.polish, .english] {
            let intro = DealWatchWords.intro(language)
            XCTAssertTrue(intro.contains(language == .polish ? "niczego nie kupuję" : "I don't buy anything"))
            XCTAssertTrue(intro.contains(language == .polish ? "Serwer trzyma Twoje słowa" : "The server keeps your words"))
        }
    }

    func testEveryTextExistsInBothLanguages() {
        let both: [(NotificationLanguage) -> String] = [
            { DealWatchWords.title($0) }, { DealWatchWords.rowSubtitle($0) }, { DealWatchWords.intro($0) }, { DealWatchWords.empty($0) },
            { DealWatchWords.loading($0) }, { DealWatchWords.add($0) }, { DealWatchWords.done($0) }, { DealWatchWords.cancel($0) },
            { DealWatchWords.delete($0) }, { DealWatchWords.deleteAsk($0) }, { DealWatchWords.tryAgain($0) }, { DealWatchWords.itemLabel($0) },
            { DealWatchWords.itemPlaceholder($0) }, { DealWatchWords.itemHint($0) }, { DealWatchWords.priceLabel($0) },
            { DealWatchWords.pricePlaceholder($0) }, { DealWatchWords.priceProblem($0) }, { DealWatchWords.shopsLabel($0) },
            { DealWatchWords.allShops($0) }, { DealWatchWords.pickShops($0) }, { DealWatchWords.save($0) }, { DealWatchWords.saving($0) },
            { DealWatchWords.checkedLabel($0) }, { DealWatchWords.neverChecked($0) }, { DealWatchWords.matchesTitle($0) },
            { DealWatchWords.noMatchesNow($0) }, { DealWatchWords.readInPart($0) }, { DealWatchWords.noServer($0) },
            { DealWatchWords.paused($0) },
        ]
        for text in both {
            XCTAssertFalse(text(.polish).isEmpty)
            XCTAssertFalse(text(.english).isEmpty)
            XCTAssertNotEqual(text(.polish), text(.english))
        }
    }
}
