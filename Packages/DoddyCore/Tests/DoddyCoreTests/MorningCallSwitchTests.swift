import Foundation
import XCTest
@testable import DoddyCore

/// The Morning call switch in Settings › Phone calls › Doddy calls you (owner, 15 Nov 2026): the pickers' limits, the
/// days choice, the draft they make (the voice card's, with the same approval), what the switch shows for each answer
/// of Doddy's server, and that the card's tap sends exactly the approved payload to the voice card's endpoint.
final class MorningCallSwitchTests: XCTestCase {
    private let warsaw: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func at(_ text: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    // MARK: The pickers

    func testThePickersMakeTheVoiceCardsDraftAndItsApproval() {
        let draft = MorningCallDraft(pickedTime: at("2026-11-15 08:00", warsaw), days: MorningCallDayChoice(kind: .everyDay), calendar: warsaw)
        XCTAssertEqual(draft, MorningCallDraft(time: "08:00", days: .everyDay, timeZoneID: "Europe/Warsaw"))
        // What the voice card would have from "dzwoń do mnie codziennie o 8", with the same calendar.
        guard case .callMeEveryMorning(let spoken) = VoiceToolRequest.parse(
            name: VoiceToolName.callMeEveryMorning, parametersJSON: Data(#"{"time": "08:00"}"#.utf8), calendar: warsaw)
        else { return XCTFail("parsed") }
        XCTAssertEqual(draft, spoken)
        // The first shared vector (contracts/phone/approval-vectors.json), which the server also checks.
        XCTAssertEqual(draft?.approvalHash(to: "+48500100200", allowQuietHours: false, language: .polish),
                       "c47819f157ecb5527bd7c714a5415ad1588e409592692b5d1ad5c3a43532f3b4")
        let weekdays = MorningCallDraft(pickedTime: at("2026-11-15 07:30", warsaw), days: MorningCallDayChoice(kind: .weekdays), calendar: warsaw)
        XCTAssertEqual(weekdays, MorningCallDraft(time: "07:30", days: .weekdays, timeZoneID: "Europe/Warsaw"))
    }

    func testOnlyAMorningCanBePicked() {
        for (clock, expected) in [("04:59", nil), ("05:00", "05:00"), ("09:05", "09:05"), ("11:59", "11:59"), ("12:00", nil), ("23:30", nil)] {
            XCTAssertEqual(MorningCallTime.text(of: at("2026-11-15 \(clock)", warsaw), calendar: warsaw), expected, clock)
            let draft = MorningCallDraft(pickedTime: at("2026-11-15 \(clock)", warsaw), days: MorningCallDayChoice(kind: .everyDay), calendar: warsaw)
            XCTAssertEqual(draft?.time, expected, "no draft outside the morning: \(clock)")
        }
        // The picker's range is 05:00 to 11:59 on the iPhone's clock, also on the day summer time starts and elsewhere.
        for (day, calendar) in [("2026-11-15", warsaw), ("2026-03-29", warsaw), ("2026-10-25", warsaw), ("2026-03-08", Self.newYork)] {
            let range = MorningCallTime.range(on: at("\(day) 15:00", calendar), calendar: calendar)
            XCTAssertEqual(range.lowerBound, at("\(day) 05:00", calendar), day)
            XCTAssertEqual(range.upperBound, at("\(day) 11:59", calendar), day)
            XCTAssertEqual(MorningCallTime.text(of: range.lowerBound, calendar: calendar), "05:00")
            XCTAssertEqual(MorningCallTime.text(of: range.upperBound, calendar: calendar), "11:59")
        }
        // A New York iPhone's draft is in its own zone.
        let ny = MorningCallDraft(pickedTime: at("2026-11-15 06:45", Self.newYork), days: MorningCallDayChoice(kind: .weekend), calendar: Self.newYork)
        XCTAssertEqual(ny, MorningCallDraft(time: "06:45", days: .weekend, timeZoneID: "America/New_York"))
    }

    func testThePickerStartsAtTheActiveTimeOrAtEight() {
        let day = at("2026-11-15 15:00", warsaw)
        XCTAssertEqual(MorningCallTime.start(nil, on: day, calendar: warsaw), at("2026-11-15 08:00", warsaw))
        XCTAssertEqual(MorningCallTime.start("07:30", on: day, calendar: warsaw), at("2026-11-15 07:30", warsaw))
        XCTAssertEqual(MorningCallTime.start("13:00", on: day, calendar: warsaw), at("2026-11-15 08:00", warsaw), "not a morning")
        XCTAssertEqual(MorningCallTime.start("8", on: day, calendar: warsaw), at("2026-11-15 08:00", warsaw), "not HH:MM")
        XCTAssertFalse(MorningCallDraft(time: MorningCallTime.suggested, days: .everyDay, timeZoneID: "Europe/Warsaw").inQuietHours(.standard),
                       "the suggested time needs no quiet-hours switch")
    }

    func testTheDaysChoiceBindsExactlyTheTickedDays() {
        XCTAssertEqual(MorningCallDayChoice(kind: .everyDay).days, .everyDay)
        XCTAssertEqual(MorningCallDayChoice(kind: .weekdays).days?.digits, "12345")
        XCTAssertEqual(MorningCallDayChoice(kind: .weekend).days?.digits, "67")
        XCTAssertEqual(MorningCallDayChoice(kind: .chosen, chosen: [5, 1, 3]).days?.digits, "135", "ascending, whatever order they were ticked")
        XCTAssertNil(MorningCallDayChoice(kind: .chosen).days, "no day ticked: nothing to book")
        XCTAssertNil(MorningCallDayChoice(kind: .chosen, chosen: [0, 1]).days)
        XCTAssertNil(MorningCallDraft(pickedTime: at("2026-11-15 08:00", warsaw), days: MorningCallDayChoice(kind: .chosen), calendar: warsaw))
        // Ticks are kept while another kind is picked; days out of range are ignored.
        var choice = MorningCallDayChoice(kind: .chosen)
        choice.set(2, true)
        choice.set(4, true)
        choice.set(8, true)
        choice.set(0, true)
        choice.kind = .weekend
        XCTAssertEqual(choice.days, .weekend)
        choice.kind = .chosen
        XCTAssertEqual(choice.days?.digits, "24")
        choice.set(2, false)
        XCTAssertEqual(choice.days?.digits, "4")
        // An active morning call opens the pickers on its own days, for every possible set of days.
        XCTAssertEqual(MorningCallDayChoice(.everyDay).kind, .everyDay)
        XCTAssertEqual(MorningCallDayChoice(.weekdays).kind, .weekdays)
        XCTAssertEqual(MorningCallDayChoice(.weekend).kind, .weekend)
        XCTAssertEqual(MorningCallDayChoice(MorningCallDays(digits: "135")!), MorningCallDayChoice(kind: .chosen, chosen: [1, 3, 5]))
        for mask in 1..<128 {
            let digits = (1...7).filter { mask & (1 << ($0 - 1)) != 0 }.map(String.init).joined()
            let days = MorningCallDays(digits: digits)!
            XCTAssertEqual(MorningCallDayChoice(days).days, days, digits)
        }
    }

    // MARK: What the switch shows

    func testTheSwitchShowsOnlyTheServersState() throws {
        let ready = try settings()
        let none = try status()
        let active = try status(call: true)
        XCTAssertFalse(MorningCallSwitch(settings: ready, status: none).isOn)
        XCTAssertNil(MorningCallSwitch(settings: ready, status: none).blocker)
        XCTAssertTrue(MorningCallSwitch(settings: ready, status: none).isEnabled)
        XCTAssertFalse(MorningCallSwitch(settings: ready, status: none).canChange)
        let on = MorningCallSwitch(settings: ready, status: active)
        XCTAssertTrue(on.isOn)
        XCTAssertTrue(on.isEnabled)
        XCTAssertTrue(on.canChange, "changing the time or days is a new card that replaces it")
        // Only an active morning call reads as on.
        XCTAssertFalse(MorningCallSwitch(settings: ready, status: try status(call: true, state: "stopped")).isOn)
    }

    func testWhatStandsInTheWayAndThatStoppingNeverWaits() throws {
        let cases: [(CallSettings, MorningCallStatus, MorningCallBlocker)] = [
            (try settings(), try status(enabled: false), .serverOff),
            (try settings(), try status(available: false), .lineNotSetUp),
            (try settings(outbound: false), try status(), .lineNotSetUp),
            (try settings(verified: false), try status(), .noVerifiedPhone),
            (try settings(consent: false), try status(), .callsOff),
            // The server's switch is said first: nothing else matters while it is off.
            (try settings(outbound: false, verified: false, consent: false), try status(enabled: false), .serverOff),
            (try settings(verified: false, consent: false), try status(), .noVerifiedPhone),
        ]
        for (s, st, blocker) in cases {
            let off = MorningCallSwitch(settings: s, status: st)
            XCTAssertEqual(off.blocker, blocker)
            XCTAssertFalse(off.isOn)
            XCTAssertFalse(off.isEnabled, "\(blocker): can't be turned on")
            // A morning call still set up can always be switched off, whatever is in the way (DOD-05).
            let stillOn = MorningCallSwitch(settings: s, status: try status(enabled: st.enabled, available: st.available, call: true))
            XCTAssertTrue(stillOn.isOn)
            XCTAssertTrue(stillOn.isEnabled, "\(blocker): stopping is never held back")
            XCTAssertFalse(stillOn.canChange, "\(blocker): no new card while something is in the way")
        }
    }

    func testTheSwitchIsShownWithThePhoneLineOrWhileOneIsSetUp() throws {
        XCTAssertTrue(MorningCallSwitch.isShown(settings: try settings(), status: try status()))
        XCTAssertTrue(MorningCallSwitch.isShown(settings: try settings(), status: try status(enabled: false)), "shown, switched off")
        XCTAssertFalse(MorningCallSwitch.isShown(settings: try settings(outbound: false), status: try status()))
        XCTAssertTrue(MorningCallSwitch.isShown(settings: try settings(outbound: false), status: try status(call: true)), "so it can be stopped")
    }

    // MARK: The check before the card

    func testTheCardGetsTheNumberQuietHoursAndTheCallItReplaces() throws {
        let draft = MorningCallDraft(time: "07:00", days: .weekdays, timeZoneID: "Europe/Warsaw")
        let phone = PhoneStatus(phone: "+48500100200", smsEnabled: true, optedOut: false)
        let active = try status(call: true)
        guard case .ready(let proposal) = MorningCallProposal.check(draft, settings: try settings(), phone: phone, status: active)
        else { return XCTFail("ready") }
        XCTAssertEqual(proposal.to, "+48500100200")
        XCTAssertEqual(proposal.quietHours, .standard)
        XCTAssertEqual(proposal.replaces, active.call, "the card says which one it replaces")
        XCTAssertFalse(proposal.canBook(allowQuietHours: false), "07:00 is in quiet hours: only with the card's switch")
        XCTAssertTrue(proposal.canBook(allowQuietHours: true))
        guard case .ready(let fresh) = MorningCallProposal.check(draft, settings: try settings(), phone: phone, status: try status())
        else { return XCTFail("ready") }
        XCTAssertNil(fresh.replaces)
        XCTAssertEqual(MorningCallProposal.check(draft, settings: try settings(quiet: #"{"start":"23:00","end":"06:30"}"#), phone: phone, status: try status()),
                       .ready(MorningCallProposal(draft: draft, to: "+48500100200", quietHours: CallQuietHours(start: "23:00", end: "06:30"), replaces: nil)))
        // Blocked as the switch is, and with no number on the server although it says verified.
        XCTAssertEqual(MorningCallProposal.check(draft, settings: try settings(), phone: phone, status: try status(enabled: false)), .blocked(.serverOff))
        XCTAssertEqual(MorningCallProposal.check(draft, settings: try settings(consent: false), phone: phone, status: try status()), .blocked(.callsOff))
        XCTAssertEqual(MorningCallProposal.check(draft, settings: try settings(), phone: .none, status: try status()), .blocked(.noVerifiedPhone))
    }

    func testEveryRefusalHasItsOwnText() {
        let codes = ["quiet_hours", "approval_mismatch", "already_active", "already_booked", "already_done", "server_limit",
                     "morning_calls_off", "outbound_not_enabled", "no_verified_phone", "phone_not_allowed", "not_configured", "rate_limited"]
        let refusals = codes.map(MorningCallRefusal.init(code:))
        XCTAssertEqual(Set(refusals.map { "\($0)" }).count, codes.count)
        XCTAssertFalse(refusals.contains(.other))
        XCTAssertEqual(MorningCallRefusal(code: "invalid"), .notAccepted)
        XCTAssertEqual(MorningCallRefusal(code: "idempotency_mismatch"), .notAccepted)
        XCTAssertEqual(MorningCallRefusal(code: "status_418"), .other)
    }

    // MARK: The tap: the voice card's endpoint and approval

    func testTheCardsTapSendsExactlyTheApprovedPayload() async throws {
        let replaced = UUID(uuidString: "6F1C2A3B-0000-4000-8000-000000000001")!
        let transport = MorningScripted([ServerResponse(status: 202, body: Data(#"{"id":"6f1c2a3b-0000-4000-8000-000000000002","state":"active"}"#.utf8))])
        let client = DoddyServerClient(transport: transport, credentials: MorningCredentials())
        let draft = try XCTUnwrap(MorningCallDraft(pickedTime: at("2026-11-15 08:00", warsaw), days: MorningCallDayChoice(kind: .everyDay), calendar: warsaw))
        let outcome = try await client.bookMorningCall(draft, to: "+48500100200", allowQuietHours: false, language: .polish, replaces: replaced)
        XCTAssertEqual(outcome, .booked(id: UUID(uuidString: "6F1C2A3B-0000-4000-8000-000000000002")!))
        let all = await transport.sent
        let sent = try XCTUnwrap(all.first)
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.path, "/v1/calls/morning")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(sent.body)) as? [String: Any])
        XCTAssertEqual(body["time"] as? String, "08:00")
        XCTAssertEqual(body["days"] as? String, "1234567")
        XCTAssertEqual(body["timeZone"] as? String, "Europe/Warsaw")
        XCTAssertEqual(body["allowQuietHours"] as? Bool, false)
        XCTAssertEqual(body["language"] as? String, "pl")
        XCTAssertEqual(body["replaces"] as? String, "6f1c2a3b-0000-4000-8000-000000000001")
        XCTAssertEqual(body["approvalHash"] as? String, "c47819f157ecb5527bd7c714a5415ad1588e409592692b5d1ad5c3a43532f3b4",
                       "bound to the number, time, days, zone, switch and language the card showed")
    }

    func testAStoppedBookingGetsANewKeyButAnUnclearOneKeepsItsKey() async throws {
        let draft = MorningCallDraft(time: "08:00", days: .everyDay, timeZoneID: "Europe/Warsaw")
        // Unclear, then the same tap again: the same key, so the server sets it up at most once.
        let unclear = MorningScripted([ServerResponse(status: 500), ServerResponse(status: 409, body: Data(#"{"error":"already_booked"}"#.utf8))])
        let client = DoddyServerClient(transport: unclear, credentials: MorningCredentials())
        let first = try await client.bookMorningCall(draft, to: "+48500100200", allowQuietHours: false, language: .polish, replaces: nil)
        XCTAssertEqual(first, .unknown)
        let second = try await client.bookMorningCall(draft, to: "+48500100200", allowQuietHours: false, language: .polish, replaces: nil)
        XCTAssertEqual(second, .refused("already_booked"))
        let unclearSent = await unclear.sent
        let keys = try unclearSent.map(Self.key)
        XCTAssertEqual(keys[0], keys[1])
        // The server says that booking is over (stopped since): the next card of the same schedule is a new booking.
        let over = MorningScripted([
            ServerResponse(status: 409, body: Data(#"{"error":"already_done","id":"6f1c2a3b-0000-4000-8000-000000000001","state":"stopped"}"#.utf8)),
            ServerResponse(status: 202, body: Data(#"{"id":"6f1c2a3b-0000-4000-8000-000000000003","state":"active"}"#.utf8)),
        ])
        let again = DoddyServerClient(transport: over, credentials: MorningCredentials())
        let done = try await again.bookMorningCall(draft, to: "+48500100200", allowQuietHours: false, language: .polish, replaces: nil)
        XCTAssertEqual(done, .refused("already_done"))
        XCTAssertEqual(MorningCallRefusal(code: "already_done"), .stoppedSince)
        let booked = try await again.bookMorningCall(draft, to: "+48500100200", allowQuietHours: false, language: .polish, replaces: nil)
        XCTAssertEqual(booked, .booked(id: UUID(uuidString: "6F1C2A3B-0000-4000-8000-000000000003")!))
        let overSent = await over.sent
        let overKeys = try overSent.map(Self.key)
        XCTAssertNotEqual(overKeys[0], overKeys[1])
    }

    func testTurningOffIsOneStopRequest() async throws {
        let transport = MorningScripted([ServerResponse(status: 200, body: Data(#"{"stopped":true,"calling":true}"#.utf8)),
                                         ServerResponse(status: 200, body: Data(#"{"stopped":false,"calling":false}"#.utf8)),
                                         ServerResponse(status: 502)])
        let client = DoddyServerClient(transport: transport, credentials: MorningCredentials())
        let stopped = try await client.stopMorningCalls()
        XCTAssertEqual(stopped, .stopped(calling: true))
        let none = try await client.stopMorningCalls()
        XCTAssertEqual(none, .noneActive)
        let unclear = try await client.stopMorningCalls()
        XCTAssertEqual(unclear, .unknown, "a gateway error is never read as stopped")
        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.method), [.delete, .delete, .delete])
        XCTAssertEqual(Set(sent.map(\.path)), ["/v1/calls/morning"])
    }

    // MARK: Helpers

    private static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private static func key(_ request: ServerRequest) throws -> String {
        let body = try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
        return try XCTUnwrap(body?["idempotencyKey"] as? String)
    }

    private func settings(outbound: Bool = true, verified: Bool = true, consent: Bool = true, quiet: String? = nil) throws -> CallSettings {
        let quietJSON = quiet.map { #","quietHours":\#($0)"# } ?? ""
        let json = #"{"available":{"inbound":true,"outbound":\#(outbound)},"doddyNumber":"+48221234567","phoneVerified":\#(verified),"inboundEnabled":false,"pinSet":false,"pinLocked":false,"outboundConsent":\#(consent),"memoryCopy":{"enabled":false,"count":0}\#(quietJSON)}"#
        return try JSONDecoder().decode(CallSettings.self, from: Data(json.utf8))
    }

    private func status(enabled: Bool = true, available: Bool = true, call: Bool = false, state: String = "active") throws -> MorningCallStatus {
        let callJSON = call
            ? #"{"id":"6f1c2a3b-0000-4000-8000-000000000001","time":"08:00","days":"12345","timeZone":"Europe/Warsaw","allowQuietHours":false,"language":"pl","state":"\#(state)","stopCode":null,"nextCallAt":"2026-11-16T07:00:00.000Z","createdAt":"2026-11-15T10:00:00.000Z"}"#
            : "null"
        let json = #"{"enabled":\#(enabled),"available":\#(available),"call":\#(callJSON),"recent":[]}"#
        return try JSONDecoder().decode(MorningCallStatus.self, from: Data(json.utf8))
    }
}

private actor MorningScripted: ServerTransport {
    private var responses: [ServerResponse]
    private(set) var sent: [ServerRequest] = []
    init(_ responses: [ServerResponse]) { self.responses = responses }
    func send(_ request: ServerRequest) async throws -> ServerResponse {
        sent.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return responses.removeFirst()
    }
}

private final class MorningCredentials: ServerCredentialStore, @unchecked Sendable {
    func load() throws -> String? { "t" }
    func save(_ token: String) throws {}
    func delete() throws {}
}
