import Foundation
import XCTest
@testable import DoddyCore

/// The ask cards are drawn as they are, so with the app in Polish their words must be Polish
/// (owner, 9 Nov 2026: "ta aplikacja dalej pokazuje angielskie jakieś wyrazy"). The rule itself
/// (what needs a tap, what runs at once) must not change with the language.
///
/// Since decision 2026-11-11-asked-for-runs-at-once most of those cards are gone: looking at the
/// user's own things and Doddy's own small actions run at once. The cards that are left, and are
/// checked here, are the ones for taking something away and for handing a task over.
final class AskFirstPolishTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }

    private let list = ListVoiceRequest(list: "Zakupy", items: ["mleko"])

    private func card(_ need: AskFirst.Need) -> AskCard? {
        switch need {
        case .yesFirst(let card), .tapFirst(let card): card
        default: nil
        }
    }

    /// Requests whose card text is still chosen in AskFirst (and its helpers), one per kind of card.
    private func requests() -> [VoiceToolRequest] {
        [
            .parkingSpot(.clear),
            .removeFromList(list),
            .handOverErrand(ErrandDraft(words: "znajdź lot", brief: "Lot do Rzymu", title: "Rzym")),
        ]
    }

    /// Requests that had a card until 11 Nov 2026 and now run at once, with no card in any language.
    private func requestsThatRunAtOnce() -> [VoiceToolRequest] {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        return [
            .searchMemories(query: "klucze"),
            .readCalendar(VoiceTimeRange(start: day, end: day.addingTimeInterval(3600))),
            .lookupContact(name: "Ania"),
            .upcomingBirthdays(days: 7),
            .findPhotos(PhotoSearchRequest(firstDay: day, days: 3)!),
            .readSteps(StepDay(daysAgo: 1)!),
            .readHealthWeek,
            .listAlarms,
            .startStopwatch(label: nil),
            .stopStopwatch,
            .checkStopwatch,
            .startFocus(minutes: 25, label: nil),
            .stopFocus,
            .checkFocus,
            .startWindDown(minutes: 10),
            .stopWindDown,
            .readList(name: "Zakupy"),
            .parkingSpot(.find),
            .addToList(list),
            .checkOff(list),
            .noteCapabilityGap(.sendMessage),
            .checkErrands(about: nil),
            .lookAtScreen(question: "Co mam jej odpisać?"),
            .findDeals(DealsRequest(items: ["masło"])),
            .followNews(.topic(id: "poland")),
        ]
    }

    func testTheRemoveAndForgetCardsArePolish() {
        guard case .yesFirst(let remove) = AskFirst.need(for: .removeFromList(list), polish: true) else {
            return XCTFail("removing from a list still shows its card")
        }
        XCTAssertEqual(remove.title, "Usunąć z listy „Zakupy”?")
        XCTAssertEqual(remove.lines, ["mleko"], "exactly what goes, as the user said it")
        XCTAssertEqual(remove.confirmLabel, "Usuń")
        guard case .yesFirst(let forget) = AskFirst.need(for: .parkingSpot(.clear), polish: true) else {
            return XCTFail("forgetting the parking spot still shows its card")
        }
        XCTAssertEqual(forget.title, "Zapomnieć miejsce parkowania?")
        XCTAssertEqual(forget.lines, ["Jedyne miejsce zapisane na tym iPhonie zostanie usunięte."])
        XCTAssertEqual(forget.confirmLabel, "Zapomnij")
    }

    func testEnglishStaysAsItWas() {
        guard case .yesFirst(let remove) = AskFirst.need(for: .removeFromList(list)) else { return XCTFail() }
        XCTAssertEqual(remove.title, "Remove from Zakupy?")
        XCTAssertEqual(remove.lines, ["mleko"])
        XCTAssertEqual(remove.confirmLabel, "Remove")
        guard case .yesFirst(let forget) = AskFirst.need(for: .parkingSpot(.clear)) else { return XCTFail() }
        XCTAssertEqual(forget.title, "Forget your parking spot?")
        XCTAssertEqual(forget.lines, ["The one spot kept on this iPhone is removed."])
        XCTAssertEqual(forget.confirmLabel, "Forget it")
    }

    func testEveryCardChangesLanguageButNotHowItAsks() {
        for request in requests() {
            let english = AskFirst.need(for: request, calendar: calendar)
            let polish = AskFirst.need(for: request, calendar: calendar, polish: true)
            XCTAssertNotNil(card(english), "\(request) still shows a card")
            XCTAssertEqual(AskFirst.needsTap(english), AskFirst.needsTap(polish), "\(request)")
            guard let en = card(english), let pl = card(polish) else { XCTFail("no card for \(request)"); continue }
            XCTAssertNotEqual(en.title, pl.title, "\(request) has an English title in Polish")
            XCTAssertNotEqual(en.confirmLabel, pl.confirmLabel, "\(request) has an English button in Polish")
            XCTAssertEqual(en.lines.count, pl.lines.count, "\(request)")
        }
    }

    func testPolishCardsHaveNoEnglishWords() {
        let english = ["Yes", "Search", "Read", "Check", "Look", "Note", "Add", "Remove", "Tick", "Forget", "From ",
                       "Today", "Yesterday", "Kept on", "Your words", "Name:", "List:", "For:"]
        for request in requests() {
            guard let pl = card(AskFirst.need(for: request, calendar: calendar, polish: true)) else { XCTFail("no card for \(request)"); continue }
            let text = ([pl.title, pl.confirmLabel] + pl.lines).joined(separator: "\n")
            for word in english {
                XCTAssertFalse(text.contains(word), "“\(word)” in the Polish card for \(request): \(text)")
            }
        }
    }

    /// Decision 2026-11-11-asked-for-runs-at-once: these have no card to translate any more. In either
    /// language the request runs at once, with no tap and no spoken question.
    func testWhatRunsAtOnceHasNoCardInEitherLanguage() {
        for request in requestsThatRunAtOnce() {
            for polish in [false, true] {
                let need = AskFirst.need(for: request, calendar: calendar, polish: polish)
                XCTAssertEqual(need, .runsNow, "\(request), polish: \(polish)")
                XCTAssertNil(card(need), "\(request), polish: \(polish)")
                XCTAssertFalse(AskFirst.needsTap(need), "\(request), polish: \(polish)")
            }
        }
    }

    func testTheLeaveByAndPlanCardsArePolish() {
        let arrive = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 18))!
        let leave = LeaveByAsk.card(LeaveByRequest(place: "Dworzec", arriveBy: arrive, mode: .walking, bufferMinutes: 10), calendar: calendar, polish: true)
        XCTAssertEqual(leave.title, "Obliczyć, kiedy wyjść?")
        XCTAssertEqual(leave.lines[0], "Dokąd: Dworzec")
        XCTAssertEqual(leave.lines[2], "Pieszo, z zapasem 10 min")
        XCTAssertEqual(leave.confirmLabel, "Oblicz")

        let plan = PlanAsk(goal: .firstFiveK, daysPerWeek: 3, minutesPerSession: 30)
        XCTAssertEqual(plan.cardLines(polish: true), ["Cel: Pierwsze 5 km", "Dni w tygodniu: 3, 30 min na trening", "Na pytania o bezpieczeństwo odpowiesz na ekranie."])
        XCTAssertEqual(plan.cardLines, ["Goal: First 5 km", "3 days a week, 30 min a session", "You answer the safety questions yourself, on screen."])
    }
}
