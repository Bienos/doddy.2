#if DEBUG
import DoddyCore
import XCTest
@testable import Doddy

/// The one owner of the audio session (ADR-695), with fake parts of Doddy registered in place of the
/// real ones. App-target tests: hosted Mac job only (no Xcode where they were written).
final class AudioSessionOwnerTests: XCTestCase {
    @MainActor
    func testAPlayerIsStoppedForSomethingThatListens() {
        let owner = AudioSessionOwner(watchesConversationAndCapture: false)
        let player = FakeUser(), dictation = FakeUser()
        owner.register(player, as: .memoPlayback, isUsing: { $0.using }, stop: { $0.stopped() })
        owner.register(dictation, as: .dictation, isUsing: { $0.using })
        player.using = true

        XCTAssertEqual(owner.claim(.dictation, by: dictation), .go(stopping: [.memoPlayback]))
        XCTAssertEqual(player.stops, 1)
        XCTAssertFalse(player.using)
    }

    @MainActor
    func testNothingIsStartedOverSomethingThatListens() {
        let owner = AudioSessionOwner(watchesConversationAndCapture: false)
        let recorder = FakeUser(), player = FakeUser()
        owner.register(recorder, as: .memoRecording, isUsing: { $0.using })
        owner.register(player, as: .readAloud, isUsing: { $0.using }, stop: { $0.stopped() })
        recorder.using = true

        XCTAssertEqual(owner.claim(.readAloud, by: player), .refused(by: .memoRecording))
        XCTAssertEqual(owner.claim(.conversation), .refused(by: .memoRecording))
        XCTAssertTrue(owner.microphoneInUse)
        XCTAssertTrue(recorder.using, "a part that listens is never stopped")
    }

    @MainActor
    func testTheAskerIsNotCountedAgainstItself() {
        let owner = AudioSessionOwner(watchesConversationAndCapture: false)
        let dictation = FakeUser()
        owner.register(dictation, as: .dictation, isUsing: { $0.using })
        dictation.using = true
        XCTAssertEqual(owner.claim(.dictation, by: dictation), .go(stopping: []))
    }

    @MainActor
    func testTheSessionStaysOnWhileSomethingElseUsesIt() {
        let owner = AudioSessionOwner(watchesConversationAndCapture: false)
        let conversation = FakeUser(), dictation = FakeUser()
        owner.register(conversation, as: .conversation, isUsing: { $0.using })
        owner.register(dictation, as: .dictation, isUsing: { $0.using })
        conversation.using = true

        // Dictation stopping while a conversation runs: the review's bug. The session stays on.
        XCTAssertFalse(owner.release(.dictation, by: dictation))
        conversation.using = false
        XCTAssertTrue(owner.release(.dictation, by: dictation))
    }

    @MainActor
    func testAPlayerStoppedForAClaimLeavesTheSessionOnForIt() {
        let owner = AudioSessionOwner(watchesConversationAndCapture: false)
        let player = FakeUser(), recorder = FakeUser()
        owner.register(recorder, as: .memoRecording, isUsing: { $0.using })
        // The player lets go as soon as it is stopped, as the real ones do, before the recorder runs.
        owner.register(player, as: .voicePreview, isUsing: { $0.using }, stop: { user in
            user.stopped()
            user.releasedTheSession = owner.release(.voicePreview, by: user)
        })
        player.using = true

        XCTAssertEqual(owner.claim(.memoRecording, by: recorder), .go(stopping: [.voicePreview]))
        XCTAssertEqual(player.releasedTheSession, false, "the recorder's start was under way")
    }

    @MainActor
    func testAPartThatIsGoneNoLongerCounts() {
        let owner = AudioSessionOwner(watchesConversationAndCapture: false)
        var recorder: FakeUser? = FakeUser()
        recorder?.using = true
        owner.register(recorder!, as: .memoRecording, isUsing: { $0.using })
        XCTAssertTrue(owner.microphoneInUse)
        recorder = nil
        XCTAssertFalse(owner.microphoneInUse)
        XCTAssertEqual(owner.claim(.dictation), .go(stopping: []))
    }
}

@MainActor
private final class FakeUser {
    var using = false
    private(set) var stops = 0
    var releasedTheSession: Bool?

    func stopped() {
        stops += 1
        using = false
    }
}
#endif
