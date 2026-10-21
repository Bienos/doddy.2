import Foundation
import XCTest
@testable import DoddyCore

/// find_photos and open_camera (ADR-569): which days, the 31-day bound, what the agent hears
/// (counts and times, never what the pictures show) and how each asks first.
final class PhotosAndCameraTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    /// Tuesday 20 October 2026, 14:05 in Warsaw.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 14, minute: 5))! }
    private func day(_ d: Int, _ m: Int = 10) -> Date { calendar.date(from: DateComponents(year: 2026, month: m, day: d))! }

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.findPhotos, parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    func testDaysAndSpans() {
        XCTAssertEqual(parse("{}"), .findPhotos(PhotoSearchRequest(firstDay: day(20), days: 1)!))
        XCTAssertEqual(parse(#"{"day":"yesterday"}"#), .findPhotos(PhotoSearchRequest(firstDay: day(19), days: 1)!))
        XCTAssertEqual(parse(#"{"day":"2026-10-18"}"#), .findPhotos(PhotoSearchRequest(firstDay: day(18), days: 1)!))
        XCTAssertEqual(parse(#"{"from":"2026-10-12","to":"2026-10-18"}"#), .findPhotos(PhotoSearchRequest(firstDay: day(12), days: 7)!))
        XCTAssertEqual(parse(#"{"from":"2026-10-12"}"#), .findPhotos(PhotoSearchRequest(firstDay: day(12), days: 1)!), "a from alone is that day")
        XCTAssertEqual(parse(#"{"from":"2026-09-20","to":"today"}"#), .findPhotos(PhotoSearchRequest(firstDay: day(20, 9), days: 31)!))
    }

    func testRefusedNeverGuessed() {
        let name = VoiceToolName.findPhotos
        XCTAssertEqual(parse(#"{"from":"2026-09-19","to":"2026-10-20"}"#), .invalid(name: name, reason: "at most 31 days at a time"))
        XCTAssertEqual(parse(#"{"day":"2026-10-21"}"#), .invalid(name: name, reason: "a day in the future has no photos"))
        XCTAssertEqual(parse(#"{"from":"2026-10-18","to":"2026-10-12"}"#), .invalid(name: name, reason: "from must not be after to"))
        XCTAssertEqual(parse(#"{"day":"last summer"}"#), .invalid(name: name, reason: "day must be today, yesterday or a date written YYYY-MM-DD"))
        XCTAssertEqual(parse(#"{"from":"soon"}"#), .invalid(name: name, reason: "from and to must be dates written YYYY-MM-DD"))
        XCTAssertNil(PhotoSearchRequest(firstDay: now, days: 0))
        XCTAssertNil(PhotoSearchRequest(firstDay: now, days: 32))
    }

    func testRangeEndsNowForToday() {
        let today = PhotoSearchRequest(firstDay: day(20), days: 1)!.range(now: now, calendar: calendar)
        XCTAssertEqual(today.start, day(20))
        XCTAssertEqual(today.end, now)
        let week = PhotoSearchRequest(firstDay: day(12), days: 7)!.range(now: now, calendar: calendar)
        XCTAssertEqual(week.end, day(19))
        XCTAssertEqual(PhotoSearchRequest(firstDay: day(12), days: 7)!.text(calendar: calendar), "2026-10-12 to 2026-10-18")
    }

    func testTheAgentHearsCountsAndTimesOnly() {
        let request = PhotoSearchRequest(firstDay: day(18), days: 1)!
        let first = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9, minute: 12))!
        let last = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 21, minute: 40))!
        let reply = VoiceToolReply.photosFound(
            PhotoSearchSummary(photos: 23, videos: 1, first: first, last: last, limited: false), request: request, calendar: calendar)
        XCTAssertTrue(reply.hasPrefix("Found 23 photos and 1 video in the user's photo library for 2026-10-18."))
        XCTAssertTrue(reply.contains("The first was taken 2026-10-18 09:12, the last 2026-10-18 21:40."))
        XCTAssertTrue(reply.contains("never describe what is in them"))
        XCTAssertFalse(reply.contains("only some"))

        let none = VoiceToolReply.photosFound(PhotoSearchSummary(photos: 0, videos: 0, first: nil, last: nil, limited: true), request: request, calendar: calendar)
        XCTAssertTrue(none.hasPrefix("No photos or videos"))
        XCTAssertTrue(none.contains("only some of their photos"), "limited access is said, so a zero isn't taken as the whole library")
    }

    func testRules() {
        let find = VoiceToolRequest.findPhotos(PhotoSearchRequest(firstDay: day(18), days: 1)!)
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.findPhotos), .photos)
        guard case .yesFirst(let card) = AskFirst.need(for: find, calendar: calendar) else { return XCTFail("a read asks first (ASK-01)") }
        XCTAssertEqual(card.lines.first, "2026-10-18")
        XCTAssertTrue(ConnectionPause.applies(to: find))
        XCTAssertEqual(CarProfile.decision(for: find), .run)
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.findPhotos)?.effect, .lookup)
        XCTAssertEqual(ActivityRequest.describe(find, calendar: calendar)?.app, .photos)

        let camera = VoiceToolRequest.parse(name: VoiceToolName.openCamera, parametersJSON: Data("{}".utf8))
        XCTAssertEqual(camera, .openCamera)
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.openCamera), .camera)
        XCTAssertEqual(AskFirst.need(for: camera), .ownPayloadCard, "the camera opens only from its card's tap")
        XCTAssertTrue(ConnectionPause.applies(to: camera))
        if case .refuse = CarProfile.decision(for: camera) {} else { XCTFail("not while driving") }
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.openCamera)?.approval, .card)
        XCTAssertTrue(VoiceToolReply.cameraOpened.contains("Never say a photo was taken or saved"))
    }
}
