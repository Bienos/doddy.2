import XCTest
@testable import DoddyCore

/// "Remind me when to leave" (ADR-335).
final class LeaveByTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
    }

    func testLeaveTimeIsArrivalMinusTravelAndSpareRoundedDown() throws {
        let request = LeaveByRequest(place: "Dentist", arriveBy: at(15), mode: .driving, bufferMinutes: 10)
        let plan = try LeaveBy.plan(request, placeName: "Dental Clinic", placeAddress: "Marszałkowska 1", travelSeconds: 22 * 60 + 30, now: at(9)).get()
        // 15:00 − 22.5 min − 10 min = 14:27:30, rounded down to 14:27.
        XCTAssertEqual(plan.leaveAt, at(14, 27))
        XCTAssertEqual(plan.travelMinutes, 23)
        let reply = VoiceToolReply.leaveBySet(plan, calendar: calendar)
        XCTAssertTrue(reply.hasPrefix("added: a reminder to leave at 14:27 on 2027-01-14 for Dental Clinic, to arrive by 15:00"), reply)
        XCTAssertTrue(reply.contains("traffic can change"))
        let note = LeaveBy.notification(plan, calendar: calendar)
        XCTAssertEqual(note.title, "Time to leave")
        XCTAssertTrue(note.body.contains("to be there by 15:00") && note.body.contains("about 23 min by car") == false)
        XCTAssertTrue(note.body.contains("About 23 min by car"))
    }

    func testTooLateAndTooFar() {
        let request = LeaveByRequest(place: "Airport", arriveBy: at(10), mode: .driving, bufferMinutes: 10)
        guard case .failure(.tooLate(let leaveAt)) = LeaveBy.plan(request, placeName: "WAW", placeAddress: "", travelSeconds: 40 * 60, now: at(9, 30)) else {
            return XCTFail("should be too late")
        }
        XCTAssertEqual(leaveAt, at(9, 10))
        XCTAssertEqual(LeaveBy.plan(request, placeName: "x", placeAddress: "", travelSeconds: 13 * 3600, now: at(1)), .failure(.tooFar))
        XCTAssertEqual(LeaveBy.plan(request, placeName: "x", placeAddress: "", travelSeconds: 0, now: at(1)), .failure(.tooFar))
    }

    func testParsing() {
        func parse(_ json: String) -> VoiceToolRequest {
            VoiceToolRequest.parse(name: "remind_when_to_leave", parametersJSON: Data(json.utf8), now: at(9), calendar: calendar)
        }
        XCTAssertEqual(parse(#"{"place": "Dentist on Marszałkowska", "arrive_by": "2027-01-14T15:00", "mode": "transit", "buffer_minutes": 5}"#),
                       .leaveBy(LeaveByRequest(place: "Dentist on Marszałkowska", arriveBy: at(15), mode: .transit, bufferMinutes: 5)))
        XCTAssertEqual(parse(#"{"place": "Gym", "arrive_by": "2027-01-14T18:00"}"#),
                       .leaveBy(LeaveByRequest(place: "Gym", arriveBy: at(18))))
        guard case .invalid = parse(#"{"place": "Gym", "arrive_by": "2027-01-14"}"#) else { return XCTFail("needs a time") }
        guard case .invalid = parse(#"{"place": "Gym", "arrive_by": "2027-01-14T18:00", "mode": "bike"}"#) else { return XCTFail("mode") }
        guard case .invalid = parse(#"{"place": "Gym", "arrive_by": "2027-01-14T18:00", "buffer_minutes": 90}"#) else { return XCTFail("buffer") }
        guard case .needsClarification = parse(#"{"place": "Gym", "arrive_by": "2027-01-13T18:00"}"#) else { return XCTFail("past") }
        XCTAssertEqual(CarProfile.decision(for: parse(#"{"place": "Gym", "arrive_by": "2027-01-14T18:00"}"#)),
                       .refuse(reason: "This needs a tap on a card on the iPhone, so it waits until the user isn't driving."))
    }
}

extension LeaveByTests {
    func testPolishNotification() throws {
        let request = LeaveByRequest(place: "Dentysta", arriveBy: at(15), mode: .transit, bufferMinutes: 0)
        let plan = try LeaveBy.plan(request, placeName: "Klinika", placeAddress: "", travelSeconds: 30 * 60, now: at(9)).get()
        let note = LeaveBy.notification(plan, calendar: calendar, language: .polish)
        XCTAssertEqual(note.title, "Czas wychodzić")
        XCTAssertTrue(note.body.contains("Około 30 min komunikacją miejską"))
    }
}

/// The leave-by countdown (ADR-347).
final class LeaveByCountdownTests: XCTestCase {
    func testOnlyWithinEightHoursAndEndsAtArrival() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func plan(leaveIn: TimeInterval) -> LeaveByPlan {
            let request = LeaveByRequest(place: "Dentist", arriveBy: now.addingTimeInterval(leaveIn + 1800), bufferMinutes: 0)
            guard case .success(let plan) = LeaveBy.plan(request, placeName: "Dentist", placeAddress: "", travelSeconds: 1800, now: now) else {
                fatalError("plan")
            }
            return plan
        }
        XCTAssertTrue(LeaveByCountdown.isAvailable(plan(leaveIn: 3600), now: now))
        XCTAssertFalse(LeaveByCountdown.isAvailable(plan(leaveIn: 9 * 3600), now: now))
        XCTAssertFalse(LeaveByCountdown.isOver(arriveBy: now.addingTimeInterval(60), now: now))
        XCTAssertTrue(LeaveByCountdown.isOver(arriveBy: now, now: now))
    }
}
