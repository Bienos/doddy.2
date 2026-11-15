import XCTest
@testable import DoddyCore

/// Decision `2026-11-15-quiet-conversations-hang-up`: a conversation nobody speaks in ends by itself.
final class VoiceQuietWatchTests: XCTestCase {
    private let onScreen = VoiceQuietWatch.Situation(busy: false, onScreen: true, translating: false, cardWaiting: false)
    private let background = VoiceQuietWatch.Situation(busy: false, onScreen: false, translating: false, cardWaiting: false)
    private let speaking = VoiceQuietWatch.Situation(busy: true, onScreen: true, translating: false, cardWaiting: false)

    /// Looks the way the app does, each after the delay the last one asked for, until the watch says end
    /// (or `until`). `activity` lists when something happened; `situation` is what the app would see then.
    private func endTime(
        from start: Double = 0, until: Double = 1_000, activity: [Double] = [],
        situation: (Double) -> VoiceQuietWatch.Situation
    ) -> Double? {
        var watch = VoiceQuietWatch(startedAt: start)
        var now = start
        var pending = activity.sorted()
        var delay = VoiceQuietWatch.lookEvery
        while now <= until {
            let next = now + delay
            while let first = pending.first, first <= next {
                watch.activity(at: first)
                pending.removeFirst()
            }
            now = next
            switch watch.look(at: now, situation: situation(now)) {
            case .end: return now
            case .lookAgain(let after):
                XCTAssertGreaterThan(after, 0)
                XCTAssertLessThanOrEqual(after, VoiceQuietWatch.lookEvery, "a change of situation counts within a few seconds")
                delay = after
            }
        }
        return nil
    }

    // MARK: The limits

    func testOnScreenItEndsAfterAMinuteOfQuiet() {
        var watch = VoiceQuietWatch(startedAt: 100)
        XCTAssertEqual(watch.look(at: 159, situation: onScreen), .lookAgain(after: 1))
        XCTAssertEqual(watch.look(at: 160, situation: onScreen), .end(quietFor: 60))
        XCTAssertEqual(endTime(situation: { _ in self.onScreen }), 60)
    }

    func testInTheBackgroundItEndsAfterHalfAMinute() {
        XCTAssertEqual(VoiceQuietWatch.limit(for: background), 30)
        XCTAssertEqual(endTime(situation: { _ in self.background }), 30)
    }

    func testTranslatingOrACardWaitingGetsTwoMinutes() {
        for translating in [true, false] {
            for card in [true, false] where translating || card {
                for screen in [true, false] {
                    let situation = VoiceQuietWatch.Situation(busy: false, onScreen: screen, translating: translating, cardWaiting: card)
                    XCTAssertEqual(VoiceQuietWatch.limit(for: situation), 120, "\(situation)")
                    XCTAssertEqual(endTime(situation: { _ in situation }), 120, "\(situation)")
                }
            }
        }
    }

    // MARK: What starts the clock again

    func testSomeoneSpeakingStartsTheClockAgain() {
        XCTAssertEqual(endTime(activity: [10, 50, 100], situation: { _ in self.onScreen }), 160)
        XCTAssertEqual(endTime(activity: [10, 35], situation: { _ in self.background }), 65)
    }

    func testAnEarlierTimeChangesNothing() {
        var watch = VoiceQuietWatch(startedAt: 0)
        watch.activity(at: 40)
        watch.activity(at: 20)
        XCTAssertEqual(watch.lastActivity, 40)
    }

    func testWhileDoddySpeaksOrWorksTheClockWaits() {
        // Doddy talks (or a tool runs) from 0 to 90 s with no new line: quiet is counted from the last busy look.
        let end = endTime(situation: { $0 <= 90 ? self.speaking : self.onScreen })
        XCTAssertEqual(end, 150, "a minute after the last look that saw him busy")
    }

    func testBusyCannotHoldTheMicrophoneForever() {
        // A state that never ends (a tool that never answers) still ends after the ceiling with nothing else happening.
        XCTAssertEqual(endTime(situation: { _ in self.speaking }), VoiceQuietWatch.busyCeiling)
        // Lines while he speaks keep it going: a long translation or answer is not cut off.
        let lines = stride(from: 20.0, through: 580, by: 20).map { $0 }
        XCTAssertNil(endTime(until: 600, activity: lines, situation: { _ in self.speaking }))
    }

    func testLeavingTheScreenCountsWithinAFewSeconds() {
        // On screen and quiet for 40 s, then Doddy goes to the background: already past its 30 s, so it ends at the next look.
        let end = endTime(situation: { $0 < 40 ? self.onScreen : self.background })
        XCTAssertEqual(end, 40)
    }

    /// The conversation of 14 Nov 2026, 02:19 (`conv_2701m7bt77g9f8e9mwk0vvxre7v3`): the person asked for a map
    /// at 0:02, Doddy opened Apple Maps at 0:16 and spoke his last line at 0:17, the microphone stayed open in the
    /// background, heard a television at 1:20, and ElevenLabs ended it at 4:39. With this rule it ends at 0:47.
    func testTheMapsConversationOf14NovEndsInUnderAMinute() {
        let end = endTime(
            until: 279,
            activity: [2, 12, 16, 17],
            situation: { now in
                let busy = (3...17).contains(now)
                return VoiceQuietWatch.Situation(busy: busy, onScreen: now < 16, translating: false, cardWaiting: false)
            })
        guard let end else { return XCTFail("it never ended: the microphone stayed open until ElevenLabs' cap") }
        XCTAssertLessThan(end, 80, "before the television's words at 1:20")
        XCTAssertEqual(end, 47, "half a minute after Doddy's last line at 0:17, with Doddy in the background")
    }

    // MARK: How it is recorded

    func testAQuietEndIsNotADropAndLogbookCallsItWentQuiet() {
        XCTAssertFalse(VoiceSessionEnd.quiet.isDrop)
        XCTAssertEqual(VoiceSessionEnd.quiet.code, "quiet")
        XCTAssertEqual(LogbookBuilder.ending(VoiceSessionEnd.quiet.code), .quiet)
        XCTAssertEqual(KeptConversation.endedBy(VoiceSessionEnd.quiet.code), "quiet")
        let lines = [ConversationLog.Line(fromUser: true, text: "Open the map to Okocimska 4")]
        XCTAssertNil(SessionRecovery.draft(lines: lines, pendingNote: "Gate code 4821", end: .quiet, endedAt: Date()),
                     "nothing was cut off, so nothing is offered back")
        for language in [NotificationLanguage.english, .polish] {
            XCTAssertNil(SessionRecovery.homeNotice(.quiet, connected: true, language: language), "not \"the connection dropped\"")
        }
    }

    func testTheScreenSaysWhyInEnglishAndPolish() {
        let english = SessionRecovery.status(.quiet, connected: true)
        XCTAssertEqual(english.title, "Conversation ended")
        XCTAssertEqual(english.detail, "Nobody spoke for a while, so Doddy hung up. His microphone is off.")
        let polish = SessionRecovery.status(.quiet, connected: true, language: .polish)
        XCTAssertEqual(polish.title, "Rozmowa zakończona")
        XCTAssertEqual(polish.detail, "Przez chwilę nikt nic nie mówił, więc Doddy się rozłączył. Jego mikrofon jest wyłączony.")
    }
}
