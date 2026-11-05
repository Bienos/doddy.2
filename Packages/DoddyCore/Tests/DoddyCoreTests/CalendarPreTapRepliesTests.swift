import XCTest
@testable import DoddyCore

/// ADR-725: changing or deleting an event or a reminder starts by looking for exactly one match. What the
/// agent hears when that fails is said before the user taps anything, so it must not depend on what is in
/// the calendar or in Reminders: nothing found and several found read the same (the controller uses one constant
/// for both), and name nothing.
final class CalendarPreTapRepliesTests: XCTestCase {
    private let secret = "Oncology follow-up with Dr Kowalski"
    private let list = "Private health list"

    func testTheRepliesNameNothingFromTheCalendarOrReminders() {
        for text in [VoiceToolReply.eventNotPrepared, VoiceToolReply.reminderNotPrepared] {
            XCTAssertFalse(text.contains(secret))
            XCTAssertFalse(text.contains(list))
            XCTAssertFalse(text.contains("<<<DATA"), "no data block: nothing private is quoted")
            XCTAssertFalse(text.contains("- \""), "no listed matches")
        }
    }

    func testTheAgentIsToldWhatToDoNext() {
        XCTAssertTrue(VoiceToolReply.eventNotPrepared.contains("read_calendar"))
        XCTAssertTrue(VoiceToolReply.eventNotPrepared.contains("asks the user first"))
        XCTAssertTrue(VoiceToolReply.reminderNotPrepared.contains("exact name"))
    }

    func testTheActivityLogFilesThemAsNothingChanged() {
        XCTAssertTrue(VoiceToolReply.nothingChangedPrefixes.contains { VoiceToolReply.eventNotPrepared.hasPrefix($0) })
        XCTAssertTrue(VoiceToolReply.nothingChangedPrefixes.contains { VoiceToolReply.reminderNotPrepared.hasPrefix($0) })
    }
}
