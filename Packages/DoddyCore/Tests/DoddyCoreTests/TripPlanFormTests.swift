import XCTest
@testable import DoddyCore

// The planner's form (TripPlanForm.swift): the form is the brief the server checks, the same rules decide what
// is missing and assumed, and the words on the flight cards come from the server's answer.

final class TripPlanFormTests: XCTestCase {
    private let today = TripDay(year: 2026, month: 11, day: 13)

    private func plan() throws -> PlanResult {
        try JSONDecoder().decode(PlanResult.self, from: Fixtures.data("travel_plan_v1.json"))
    }

    func testAnEmptyFormIsMissingWhatTheServerAsksForInItsOrder() {
        let form = TripPlanForm()
        XCTAssertEqual(form.missing, [.to, .from, .when, .nights], "one adult is on the form, so who is never missing")
        XCTAssertEqual(form.assumptions, [.noCheckedBag, .stopsAllowed, .noChildren])
        XCTAssertNil(form.brief.from, "a blank place is unknown, not an empty string")
    }

    func testACompleteFormIsTheBriefTheServerSearches() {
        var form = TripPlanForm()
        form.from = "  Gdańsk "
        form.to = "Lisbon"
        form.departFrom = TripDay(year: 2027, month: 2, day: 12)
        form.setNights(4)
        form.adults = 2
        form.checkedBag = true
        let b = form.brief
        XCTAssertEqual(form.missing, [])
        XCTAssertEqual(b.from, "Gdańsk")
        XCTAssertEqual(b.departFrom, "2027-02-12")
        XCTAssertEqual(b.departTo, "2027-02-12", "no window is one exact day")
        XCTAssertEqual([b.nightsMin, b.nightsMax], [4, 4])
        XCTAssertEqual(b.adults, 2)
        XCTAssertNil(b.children)
        XCTAssertEqual(b.checkedBagPerAdult, true)
        XCTAssertEqual(form.assumptions, [.stopsAllowed, .noChildren, .exactDay])
    }

    func testTheBriefKeepsTheServersRanges() {
        var form = TripPlanForm()
        form.from = "Kraków"
        form.to = "kraków"
        form.departFrom = TripDay(year: 2027, month: 1, day: 1)
        form.departTo = TripDay(year: 2027, month: 3, day: 1)
        form.nightsMin = 40
        form.adults = 12
        form.children = 20
        form.budget = 0
        let b = form.brief
        XCTAssertNil(b.to, "a trip to where it starts has no destination yet")
        XCTAssertEqual(b.departTo, "2027-02-01", "a window is cut to 31 days")
        XCTAssertEqual([b.nightsMin, b.nightsMax], [30, 30])
        XCTAssertEqual(b.adults, 9)
        XCTAssertEqual(b.children, 8)
        XCTAssertNil(b.budget)

        form.departTo = TripDay(year: 2026, month: 12, day: 1)
        XCTAssertEqual(form.brief.departTo, "2027-01-01", "a window back to front is the first day")
    }

    func testWhatTheServerUnderstoodFillsTheForm() {
        var form = TripPlanForm()
        form.adults = 3
        var b = TripBrief()
        b.to = "Lisbon"
        b.departFrom = "2027-02-09"
        b.departTo = "2027-02-15"
        b.nightsMin = 3
        b.nightsMax = 4
        b.budget = 2000
        form.apply(b)
        XCTAssertEqual(form.to, "Lisbon")
        XCTAssertEqual(form.from, "")
        XCTAssertEqual(form.departTo, TripDay(year: 2027, month: 2, day: 15))
        XCTAssertEqual(form.nights, 4)
        XCTAssertEqual(form.adults, 3, "no number of people in the answer keeps the form's")
        XCTAssertEqual(form.budget, 2000)
        XCTAssertEqual(form.missing, [.from])
    }

    func testTheWindowAroundADayStaysInsideWhatTheServerSearches() {
        let w = TripPlanForm.window(around: TripDay(year: 2026, month: 11, day: 14), flexDays: 3, today: today)
        XCTAssertEqual(w.from, today, "never before today")
        XCTAssertEqual(w.to, TripDay(year: 2026, month: 11, day: 17))
        let exact = TripPlanForm.window(around: TripDay(year: 2027, month: 2, day: 12), flexDays: 0, today: today)
        XCTAssertEqual(exact.from, exact.to)
        let far = TripPlanForm.window(around: today.adding(days: 330), flexDays: 7, today: today)
        XCTAssertEqual(far.to, today.adding(days: 330))
    }

    func testABudgetIsReadFromDigitsOnly() {
        XCTAssertEqual(TripPlanForm.budget(fromText: "1 500 zł"), 1500)
        XCTAssertNil(TripPlanForm.budget(fromText: ""))
        XCTAssertNil(TripPlanForm.budget(fromText: "0"))
        XCTAssertEqual(TripPlanForm.budget(fromText: "99999999"), TripPlanForm.maxBudget)
    }

    func testTheCardsWordsComeFromTheAnswer() throws {
        let o = try plan().options[0]
        XCTAssertEqual(TripPlanText.money(o, polish: true), "742 zł")
        XCTAssertEqual(TripPlanText.money(o, polish: false), "742 PLN")
        XCTAssertEqual(TripPlanText.party(o, people: 5, polish: true), "za 5 osób, bez walizki")
        XCTAssertEqual(TripPlanText.party(o, people: 3, polish: true), "za 3 osoby, bez walizki")
        XCTAssertEqual(TripPlanText.price(o, adults: 2, polish: true), "742 zł za 2 osoby, bez walizki", "the old words are unchanged")
        XCTAssertEqual(TripPlanText.duration(minutes: 530, polish: false), "8 h 50 min")
        XCTAssertEqual(TripPlanText.duration(minutes: 120, polish: true), "2 godz.")
        XCTAssertEqual(TripPlanText.duration(minutes: 45, polish: true), "45 min")
        XCTAssertEqual(TripPlanText.stops(0, polish: false), "direct")
        XCTAssertEqual(o.checkInDay, TripDay(year: 2027, month: 2, day: 12))
        XCTAssertEqual(o.checkOutDay, TripDay(year: 2027, month: 2, day: 16))
        XCTAssertEqual(o.outbound.arrivalDayShift, 0)
    }

    func testTheSummaryWords() throws {
        XCTAssertEqual(TripPlanText.nights(min: 4, max: 4, polish: true), "4 noce")
        XCTAssertEqual(TripPlanText.nights(min: 5, max: 5, polish: true), "5 nocy")
        XCTAssertEqual(TripPlanText.nights(min: 1, max: 1, polish: false), "1 night")
        XCTAssertEqual(TripPlanText.nights(min: 3, max: 4, polish: false), "3–4 nights")
        XCTAssertEqual(TripPlanText.people(adults: 2, children: 1, polish: true), "2 dorosłych, 1 dziecko")
        XCTAssertEqual(TripPlanText.people(adults: 1, children: 0, polish: false), "1 adult")
        let feb9 = TripDay(year: 2027, month: 2, day: 9), feb15 = TripDay(year: 2027, month: 2, day: 15)
        XCTAssertEqual(TripPlanText.window(from: feb9, to: feb15, polish: true), "9–15 lutego")
        XCTAssertEqual(TripPlanText.window(from: feb9, to: feb9, polish: false), "9 February")
        XCTAssertEqual(TripPlanText.window(from: TripDay(year: 2027, month: 2, day: 28), to: TripDay(year: 2027, month: 3, day: 3), polish: false),
                       "28 February – 3 March")
        let searched = TripPlanText.searched(try plan().brief, polish: true)
        XCTAssertEqual(searched, ["Gdańsk → Lisbon", "12 lutego", "4 noce", "2 dorosłych", "Walizka na osobę", "Przesiadki OK"])
    }

    func testAFailedSearchIsNeverCalledAGmailProblem() {
        let kiwi = OnlineAccountsError.server(code: "provider_unavailable", message: "Kiwi.com couldn't be reached.", retryAfterSeconds: nil, receipt: nil)
        XCTAssertEqual(TripPlanProblem(kiwi, searching: true), .flightsUnavailable)
        XCTAssertFalse(TripPlanProblem(kiwi, searching: true).text(polish: false).contains("Gmail"))
        XCTAssertEqual(TripPlanProblem(kiwi, searching: false), .wordsUnavailable)
        XCTAssertEqual(TripPlanProblem(.notConfigured, searching: true), .notSetUp)
        let incomplete = OnlineAccountsError.server(code: "invalid_request", message: "", retryAfterSeconds: nil, receipt: nil)
        XCTAssertEqual(TripPlanProblem(incomplete, searching: true), .incomplete)
    }
}
