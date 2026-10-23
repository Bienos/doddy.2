import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// DODDY Capture (ADR-588): recordings on real SQLite. The row is written before the audio, every
/// write is read back, a kill leaves something to recover, and deleting means deleting.
final class SQLiteRecordingRepositoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func make() throws -> (SQLiteRecordingRepository, DoddyDatabase) {
        let database = try DoddyDatabase.inMemory()
        return (SQLiteRecordingRepository(database: database), database)
    }

    /// A finished recording of `lengthSeconds` with one part, ready for words.
    @discardableResult
    private func saved(_ repo: SQLiteRecordingRepository, id: UUID = UUID(), start: TimeInterval = 0, length: Int = 120) async throws -> UUID {
        _ = try await repo.begin(id: id, origin: .app, languageCode: "pl-PL", startedAt: at(start))
        _ = try await repo.openPart(recordingID: id, index: 1, startOffsetMilliseconds: 0)
        try await repo.closePart(recordingID: id, index: 1, durationMilliseconds: length * 1000)
        _ = try await repo.finish(recordingID: id, phase: .saved, endedAt: at(start + Double(length)), endReason: .userStopped,
                                  parts: [ClosedPart(index: 1, durationMilliseconds: length * 1000)], gaps: [])
        return id
    }

    private func lines(_ texts: [String]) -> [TranscriptSegment] {
        texts.enumerated().map { TranscriptSegment(index: $0.offset, startMilliseconds: $0.offset * 10_000, endMilliseconds: $0.offset * 10_000 + 8_000, text: $0.element, confidence: 0.9) }
    }

    // MARK: - Before the audio, and after a kill

    func testTheRowExistsBeforeTheAudioDoes() async throws {
        let (repo, _) = try make()
        let id = UUID()
        let recording = try await repo.begin(id: id, origin: .control, languageCode: "en-GB", startedAt: at(0))
        XCTAssertEqual(recording.phase, .recording)
        XCTAssertNil(recording.endedAt)
        XCTAssertEqual(recording.origin, .control)
        let unfinished = try await repo.unfinished()
        XCTAssertEqual(unfinished.map(\.id), [id], "a start that is killed straight away is still found")
        do { _ = try await repo.begin(id: id, origin: .app, languageCode: "en-GB", startedAt: at(1)); XCTFail("one row per recording") }
        catch RecordingStoreError.alreadyExists {}
    }

    func testPartsFollowEachOtherAndStartWhereTheLastEnded() async throws {
        let (repo, _) = try make()
        let id = UUID()
        _ = try await repo.begin(id: id, origin: .app, languageCode: "pl-PL", startedAt: at(0))
        let first = try await repo.openPart(recordingID: id, index: 1, startOffsetMilliseconds: 0)
        XCTAssertEqual(first.fileName, "part-0001.caf")
        XCTAssertNil(first.durationMilliseconds)

        do { _ = try await repo.openPart(recordingID: id, index: 2, startOffsetMilliseconds: 0); XCTFail("the first part is still open") }
        catch RecordingStoreError.badPart {}
        let same = try await repo.openPart(recordingID: id, index: 1, startOffsetMilliseconds: 0)
        XCTAssertEqual(same, first, "the open part again is the same part, not a second one")
        try await repo.closePart(recordingID: id, index: 1, durationMilliseconds: 600_400)
        do { try await repo.closePart(recordingID: id, index: 1, durationMilliseconds: 5); XCTFail("a part closes once") }
        catch RecordingStoreError.badPart {}
        do { _ = try await repo.openPart(recordingID: id, index: 2, startOffsetMilliseconds: 600_000); XCTFail("must start where the last ended") }
        catch RecordingStoreError.badPart {}
        do { _ = try await repo.openPart(recordingID: id, index: 3, startOffsetMilliseconds: 600_400); XCTFail("no skipped parts") }
        catch RecordingStoreError.badPart {}
        let second = try await repo.openPart(recordingID: id, index: 2, startOffsetMilliseconds: 600_400)
        XCTAssertEqual(second.startOffsetMilliseconds, 600_400)
        let all = try await repo.parts(recordingID: id)
        XCTAssertEqual(all.map(\.index), [1, 2])
        XCTAssertEqual(all[0].durationMilliseconds, 600_400)
        XCTAssertNil(all[1].durationMilliseconds)
    }

    func testReopeningTheOpenPartAtTheSamePlaceReturnsItSoARetryIsNotRefused() async throws {
        let (repo, _) = try make()
        let id = UUID()
        _ = try await repo.begin(id: id, origin: .app, languageCode: "pl-PL", startedAt: at(0))
        _ = try await repo.openPart(recordingID: id, index: 1, startOffsetMilliseconds: 0)
        try await repo.closePart(recordingID: id, index: 1, durationMilliseconds: 5_000)
        let first = try await repo.openPart(recordingID: id, index: 2, startOffsetMilliseconds: 5_000)
        // The recorder for part 2 failed to start; the user taps Resume again.
        let again = try await repo.openPart(recordingID: id, index: 2, startOffsetMilliseconds: 5_000)
        XCTAssertEqual(first, again)
        let parts = try await repo.parts(recordingID: id)
        XCTAssertEqual(parts.count, 2, "no second row")
        do { _ = try await repo.openPart(recordingID: id, index: 2, startOffsetMilliseconds: 4_000); XCTFail("a different place is still refused") }
        catch RecordingStoreError.badPart {}
    }

    func testEveryRecordingIDIsListed() async throws {
        let (repo, _) = try make()
        let a = try await saved(repo, start: 0)
        let b = UUID()
        _ = try await repo.begin(id: b, origin: .app, languageCode: "pl-PL", startedAt: at(5))
        let ids = try await repo.allIDs()
        XCTAssertEqual(ids, [a, b])
        _ = try await repo.delete(id: a)
        let after = try await repo.allIDs()
        XCTAssertEqual(after, [b])
    }

    func testFinishingCountsOnlyTheListedPartsAndLaysThemEndToEnd() async throws {
        let (repo, _) = try make()
        let id = UUID()
        _ = try await repo.begin(id: id, origin: .app, languageCode: "pl-PL", startedAt: at(0))
        _ = try await repo.openPart(recordingID: id, index: 1, startOffsetMilliseconds: 0)
        try await repo.closePart(recordingID: id, index: 1, durationMilliseconds: 600_000)
        _ = try await repo.openPart(recordingID: id, index: 2, startOffsetMilliseconds: 600_000)
        try await repo.closePart(recordingID: id, index: 2, durationMilliseconds: 600_000)
        _ = try await repo.openPart(recordingID: id, index: 3, startOffsetMilliseconds: 1_200_000)

        let gap = CaptureGap(atMilliseconds: 600_000, wallMilliseconds: 50, reason: .segmentRotation)
        let done = try await repo.finish(recordingID: id, phase: .recovered, endedAt: at(2000), endReason: .recovered,
                                         parts: [ClosedPart(index: 1, durationMilliseconds: 600_000), ClosedPart(index: 3, durationMilliseconds: 95_000)],
                                         gaps: [gap])
        XCTAssertEqual(done.removedFileNames, ["part-0002.caf"], "the unreadable part's file is for the app to delete")
        XCTAssertEqual(done.recording.durationMilliseconds, 695_000)
        XCTAssertEqual(done.recording.phase, .recovered)
        XCTAssertEqual(done.recording.endReason, .recovered)
        XCTAssertEqual(done.recording.gaps, [gap])
        let parts = try await repo.parts(recordingID: id)
        XCTAssertEqual(parts.map(\.index), [1, 3])
        XCTAssertEqual(parts.map(\.startOffsetMilliseconds), [0, 600_000], "no hole where the lost part was")
        let unfinished = try await repo.unfinished()
        XCTAssertTrue(unfinished.isEmpty)
    }

    func testFinishingTwiceOrWithAPartThatIsNotThereIsRefused() async throws {
        let (repo, _) = try make()
        let id = try await saved(repo)
        do {
            _ = try await repo.finish(recordingID: id, phase: .saved, endedAt: at(500), endReason: .userStopped, parts: [ClosedPart(index: 1, durationMilliseconds: 1)], gaps: [])
            XCTFail("already finished")
        } catch RecordingStoreError.notFinished {}

        let other = UUID()
        _ = try await repo.begin(id: other, origin: .app, languageCode: "pl-PL", startedAt: at(0))
        _ = try await repo.openPart(recordingID: other, index: 1, startOffsetMilliseconds: 0)
        do {
            _ = try await repo.finish(recordingID: other, phase: .saved, endedAt: at(5), endReason: .userStopped, parts: [ClosedPart(index: 7, durationMilliseconds: 1)], gaps: [])
            XCTFail("no such part")
        } catch RecordingStoreError.badPart {}
        do {
            _ = try await repo.finish(recordingID: other, phase: .recording, endedAt: at(5), endReason: .userStopped, parts: [], gaps: [])
            XCTFail("finishing is not recording")
        } catch RecordingStoreError.badPart {}
        let still = try await repo.recording(id: other)
        XCTAssertEqual(still?.phase, .recording, "a refused finish changed nothing")
    }

    func testAClockSetBackNeverBreaksTheEndTime() async throws {
        let (repo, _) = try make()
        let id = UUID()
        _ = try await repo.begin(id: id, origin: .app, languageCode: "pl-PL", startedAt: at(1000))
        _ = try await repo.openPart(recordingID: id, index: 1, startOffsetMilliseconds: 0)
        let done = try await repo.finish(recordingID: id, phase: .saved, endedAt: at(0), endReason: .userStopped, parts: [ClosedPart(index: 1, durationMilliseconds: 5_000)], gaps: [])
        XCTAssertEqual(done.recording.endedAt, at(1000), "never before it started")
    }

    func testARecordingWithNothingUsableIsKeptAsLostNotSilentlyDeleted() async throws {
        let (repo, _) = try make()
        let id = UUID()
        _ = try await repo.begin(id: id, origin: .app, languageCode: "pl-PL", startedAt: at(0))
        try await repo.markLost(recordingID: id, endedAt: at(30))
        let list = try await repo.recordings(category: .all, limit: 10, offset: 0)
        XCTAssertEqual(list.first?.recording.phase, .lost)
        XCTAssertEqual(list.first?.recording.durationMilliseconds, 0)
        let unfinished = try await repo.unfinished()
        XCTAssertTrue(unfinished.isEmpty)
    }

    func testDiscardingTakesTheRowAndReportsTheFilesToDelete() async throws {
        let (repo, _) = try make()
        let id = UUID()
        _ = try await repo.begin(id: id, origin: .app, languageCode: "pl-PL", startedAt: at(0))
        _ = try await repo.openPart(recordingID: id, index: 1, startOffsetMilliseconds: 0)
        let files = try await repo.discard(recordingID: id)
        XCTAssertEqual(files, ["part-0001.caf"])
        let gone = try await repo.recording(id: id)
        XCTAssertNil(gone)
        let again = try await repo.discard(recordingID: id)
        XCTAssertEqual(again, [])
    }

    /// The real thing: a file on disk, the process "killed" (the database closed with the recording
    /// still open), and the file opened again.
    func testAKillLeavesARecordingThatCanBeRecovered() async throws {
        let path = NSTemporaryDirectory() + "doddy-capture-\(UUID().uuidString).sqlite"
        defer { for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let id = UUID()
        do {
            let repo = SQLiteRecordingRepository(database: try DoddyDatabase(path: path))
            _ = try await repo.begin(id: id, origin: .intent, languageCode: "pl-PL", startedAt: at(0))
            _ = try await repo.openPart(recordingID: id, index: 1, startOffsetMilliseconds: 0)
            try await repo.closePart(recordingID: id, index: 1, durationMilliseconds: 600_000)
            _ = try await repo.openPart(recordingID: id, index: 2, startOffsetMilliseconds: 600_000)
            try await repo.checkpoint(recordingID: id, gaps: [CaptureGap(atMilliseconds: 600_000, wallMilliseconds: 40, reason: .segmentRotation)])
        }
        // A new launch.
        let repo = SQLiteRecordingRepository(database: try DoddyDatabase(path: path))
        let unfinished = try await repo.unfinished()
        XCTAssertEqual(unfinished.count, 1)
        let record = try XCTUnwrap(unfinished.first)
        XCTAssertEqual(record.parts.map(\.index), [1, 2])
        XCTAssertEqual(record.gaps.count, 1, "the checkpointed gap survived")

        // The app reads the files, then the planner decides, then the store is told.
        let plan = CaptureRecovery.plan(UnfinishedRecording(
            id: record.id, startedAt: record.startedAt,
            parts: record.parts.map { UnfinishedPart(index: $0.index, fileName: $0.fileName, recordedMilliseconds: $0.durationMilliseconds, probedMilliseconds: $0.index == 1 ? 600_100 : 72_000) },
            gaps: record.gaps))
        guard case .recover(let recovered) = plan else { return XCTFail("expected recovery") }
        let done = try await repo.finish(recordingID: recovered.id, phase: .recovered, endedAt: recovered.endedAt, endReason: .recovered,
                                         parts: recovered.kept, gaps: recovered.gaps)
        XCTAssertEqual(done.recording.durationMilliseconds, 672_000)
        XCTAssertEqual(done.recording.phase, .recovered)
        XCTAssertEqual(done.recording.origin, .intent)
    }

    // MARK: - Words

    func testWordsAreSavedWholeAndReadBackInOrderAndInPages() async throws {
        let (repo, _) = try make()
        let id = try await saved(repo)
        try await repo.saveTranscript(recordingID: id, segments: lines((0..<25).map { "line \($0)" }), status: .done)
        let count = try await repo.segmentCount(recordingID: id)
        XCTAssertEqual(count, 25)
        let page = try await repo.segments(recordingID: id, offset: 10, limit: 5)
        XCTAssertEqual(page.map(\.index), [10, 11, 12, 13, 14])
        XCTAssertEqual(page[0].text, "line 10")
        XCTAssertEqual(page[0].confidence, 0.9)
        let recording = try await repo.recording(id: id)
        XCTAssertEqual(recording?.transcription, .done)

        try await repo.saveTranscript(recordingID: id, segments: lines(["only", "two"]), status: .done)
        let replaced = try await repo.segmentCount(recordingID: id)
        XCTAssertEqual(replaced, 2, "a second write replaces, never mixes")
    }

    func testBadWordsAreRefusedAndChangeNothing() async throws {
        let (repo, _) = try make()
        let id = try await saved(repo)
        try await repo.saveTranscript(recordingID: id, segments: lines(["keep me"]), status: .done)
        var gappy = lines(["a", "b"]); gappy[1] = TranscriptSegment(index: 5, startMilliseconds: 0, endMilliseconds: 1, text: "b")
        let bad: [([TranscriptSegment], TranscriptionStatus)] = [
            (gappy, .done),
            (lines(["fine", "  "]), .done),
            ([], .done),
        ]
        for (segments, status) in bad {
            do { try await repo.saveTranscript(recordingID: id, segments: segments, status: status); XCTFail("should be refused") }
            catch RecordingStoreError.badTranscript {}
        }
        let kept = try await repo.segments(recordingID: id, offset: 0, limit: 10)
        XCTAssertEqual(kept.map(\.text), ["keep me"])

        try await repo.saveTranscript(recordingID: id, segments: [], status: .noSpeech)
        let none = try await repo.segmentCount(recordingID: id)
        XCTAssertEqual(none, 0, "no speech is a result, with no lines")
        let recording = try await repo.recording(id: id)
        XCTAssertEqual(recording?.transcription, .noSpeech)
    }

    func testNoWordsForARecordingThatIsStillBeingMade() async throws {
        let (repo, _) = try make()
        let id = UUID()
        _ = try await repo.begin(id: id, origin: .app, languageCode: "pl-PL", startedAt: at(0))
        do { try await repo.saveTranscript(recordingID: id, segments: lines(["x"]), status: .done); XCTFail("not finished") }
        catch RecordingStoreError.notFinished {}
        do { try await repo.saveTranscript(recordingID: UUID(), segments: lines(["x"]), status: .done); XCTFail("no such recording") }
        catch RecordingStoreError.notFound {}
    }

    func testACorrectionKeepsWhatWasRecognisedAndMovesTheSearch() async throws {
        let (repo, _) = try make()
        let id = try await saved(repo)
        try await repo.saveTranscript(recordingID: id, segments: lines(["Alex sent the plan to Maria", "see you Friday"]), status: .done)
        let edited = try await repo.editSegment(recordingID: id, index: 0, text: "  Alex sent the plan to Marta \n")
        XCTAssertEqual(edited.text, "Alex sent the plan to Marta")
        XCTAssertEqual(edited.originalText, "Alex sent the plan to Maria")
        XCTAssertTrue(edited.isEdited)
        let old = try await repo.search("Maria", in: id, limit: 5)
        let new = try await repo.search("Marta", in: id, limit: 5)
        XCTAssertTrue(old.isEmpty, "the old word is no longer found")
        XCTAssertEqual(new.map(\.segmentIndex), [0])
        do { _ = try await repo.editSegment(recordingID: id, index: 0, text: "   "); XCTFail("a line is corrected, not deleted") }
        catch RecordingStoreError.badTranscript {}
        do { _ = try await repo.editSegment(recordingID: id, index: 9, text: "x"); XCTFail("no such line") }
        catch RecordingStoreError.notFound {}
    }

    func testSearchFindsThePartAndItsTimeAcrossLanguages() async throws {
        let (repo, _) = try make()
        let id = try await saved(repo)
        try await repo.saveTranscript(recordingID: id, segments: lines([
            "Okay so let's talk about the website launch",
            "The initial budget could be five thousand pounds",
            "Ania powiedziała że spotkanie klienta jest w czwartek",
            "Potrzebujemy lepszej żółci do logo",
        ]), status: .done)
        let budget = try await repo.search("What did we say about the budget?", in: id, limit: 5)
        XCTAssertEqual(budget.first?.segmentIndex, 1)
        XCTAssertEqual(budget.first?.startMilliseconds, 10_000)
        let polish = try await repo.search("Kiedy jest spotkanie klienta", in: id, limit: 5)
        XCTAssertEqual(polish.first?.segmentIndex, 2)
        let folded = try await repo.search("zolci", in: id, limit: 5)
        XCTAssertEqual(folded.first?.segmentIndex, 3, "typed without diacritics, found with them")
        let nothing = try await repo.search("what did the", in: id, limit: 5)
        XCTAssertTrue(nothing.isEmpty, "only filler words: nothing to look for")
        let limited = try await repo.search("the", in: id, limit: 0)
        XCTAssertTrue(limited.isEmpty)
    }

    func testSearchStaysInsideTheRecordingAskedAboutUnlessAskedEverywhere() async throws {
        let (repo, _) = try make()
        let a = try await saved(repo, start: 0)
        let b = try await saved(repo, start: 1000)
        try await repo.saveTranscript(recordingID: a, segments: lines(["the pricing was discussed here"]), status: .done)
        try await repo.saveTranscript(recordingID: b, segments: lines(["pricing again in the other one"]), status: .done)
        let inA = try await repo.search("pricing", in: a, limit: 10)
        XCTAssertEqual(inA.map(\.recordingID), [a])
        let everywhere = try await repo.search("pricing", in: nil, limit: 10)
        XCTAssertEqual(Set(everywhere.map(\.recordingID)), [a, b])
    }

    func testTheLineBeingSaidAtATime() async throws {
        let (repo, _) = try make()
        let id = try await saved(repo)
        try await repo.saveTranscript(recordingID: id, segments: lines(["a", "b", "c"]), status: .done)
        let before = try await repo.segmentIndex(recordingID: id, atMilliseconds: 0)
        let middle = try await repo.segmentIndex(recordingID: id, atMilliseconds: 15_000)
        let after = try await repo.segmentIndex(recordingID: id, atMilliseconds: 99_000)
        XCTAssertEqual([before, middle, after], [0, 1, 2])
        let empty = try await repo.segmentIndex(recordingID: UUID(), atMilliseconds: 0)
        XCTAssertNil(empty)
    }

    // MARK: - The library

    func testTheLibraryIsNewestFirstFilteredAndPaged() async throws {
        let (repo, _) = try make()
        let oldMeeting = try await saved(repo, start: 0)
        let chat = try await saved(repo, start: 100)
        let idea = try await saved(repo, start: 200)
        _ = try await repo.setKind(id: oldMeeting, kind: .meeting)
        _ = try await repo.setKind(id: chat, kind: .conversation)
        _ = try await repo.setKind(id: idea, kind: .personal)
        try await repo.saveTranscript(recordingID: chat, segments: lines(["First words of the chat and then much more"]), status: .done)

        let all = try await repo.recordings(category: .all, limit: 10, offset: 0)
        XCTAssertEqual(all.map(\.recording.id), [idea, chat, oldMeeting])
        let meetings = try await repo.recordings(category: .meetings, limit: 10, offset: 0)
        XCTAssertEqual(meetings.map(\.recording.id), [oldMeeting])
        let ideas = try await repo.recordings(category: .ideas, limit: 10, offset: 0)
        XCTAssertEqual(ideas.map(\.recording.id), [idea])
        let page = try await repo.recordings(category: .all, limit: 1, offset: 1)
        XCTAssertEqual(page.map(\.recording.id), [chat])
        XCTAssertEqual(page.first?.preview, "First words of the chat and then much more")
        XCTAssertNil(all.first { $0.recording.id == idea }?.preview, "no words, no preview")
    }

    func testAPreviewIsCutAtAWord() async throws {
        let (repo, _) = try make()
        let id = try await saved(repo)
        try await repo.saveTranscript(recordingID: id, segments: lines([String(repeating: "wordy ", count: 60)]), status: .done)
        let preview = try await repo.recordings(category: .all, limit: 1, offset: 0).first?.preview
        XCTAssertTrue(preview!.hasSuffix("wordy…"))
        XCTAssertLessThanOrEqual(preview!.count, 141)
    }

    func testTheLanguageCanBeChangedToWriteTheWordsOutAgainAndOnlyToARealCode() async throws {
        let (repo, _) = try make()
        let id = try await saved(repo)
        let changed = try await repo.setLanguage(id: id, languageCode: "en-GB")
        XCTAssertEqual(changed.languageCode, "en-GB")
        for bad in ["", "x", "pl PL", "pl;DROP", String(repeating: "a", count: 40)] {
            do { _ = try await repo.setLanguage(id: id, languageCode: bad); XCTFail("refused: \(bad)") }
            catch RecordingStoreError.badTranscript {}
        }
        do { _ = try await repo.setLanguage(id: UUID(), languageCode: "pl-PL"); XCTFail("no such recording") }
        catch RecordingStoreError.notFound {}
    }

    func testRenamingCleansTheTitleAndEmptyGoesBackToTheDefault() async throws {
        let (repo, _) = try make()
        let id = try await saved(repo)
        let renamed = try await repo.rename(id: id, title: "  Budget \n call ")
        XCTAssertEqual(renamed.title, "Budget call")
        let reset = try await repo.rename(id: id, title: "   ")
        XCTAssertEqual(reset.title, "")
        do { _ = try await repo.rename(id: UUID(), title: "x"); XCTFail("no such recording") } catch RecordingStoreError.notFound {}
    }

    // MARK: - Memory the user chose

    func testANoteFromARecordingKeepsItsSourceAndSurvivesTheRecording() async throws {
        let (repo, database) = try make()
        let memories = SQLiteMemoryRepository(database: database)
        let id = try await saved(repo)
        let note = try await memories.save(try CaptureMemory.newMemory(text: "Alex runs the launch", kind: .actionItem, savedAt: at(5)))
        try await repo.linkMemory(memoryID: note.id, recordingID: id, atMilliseconds: 872_000, recordingTitle: "Budget call", linkedAt: at(6))

        let link = try await repo.provenance(forMemory: note.id)
        XCTAssertEqual(link?.recordingID, id)
        XCTAssertEqual(link?.atMilliseconds, 872_000)
        let forRecording = try await repo.memoryLinks(forRecording: id)
        XCTAssertEqual(forRecording.map(\.memoryID), [note.id])

        _ = try await repo.delete(id: id)
        let after = try await repo.provenance(forMemory: note.id)
        XCTAssertNil(after?.recordingID, "the link is cleared…")
        XCTAssertEqual(after?.recordingTitle, "Budget call", "…but the note still says where it came from")
        let stillThere = try await memories.list(limit: nil)
        XCTAssertEqual(stillThere.map(\.id), [note.id], "deleting a recording does not delete what the user chose to remember")

        try await memories.delete(id: note.id)
        let gone = try await repo.provenance(forMemory: note.id)
        XCTAssertNil(gone, "deleting the note takes its link")
    }

    func testARecordingIsNotMemoryUntilTheUserSaysSo() async throws {
        let (repo, database) = try make()
        let memories = SQLiteMemoryRepository(database: database)
        let id = try await saved(repo)
        try await repo.saveTranscript(recordingID: id, segments: lines(["Alex is responsible for the website launch"]), status: .done)
        let notes = try await memories.list(limit: nil)
        XCTAssertTrue(notes.isEmpty, "recording and transcribing add nothing to what Doddy remembers")
        let found = try await memories.query("website launch", limit: 5)
        XCTAssertTrue(found.isEmpty, "and recall does not read transcripts")
    }

    // MARK: - Delete means delete

    func testDeletingTakesTheWordsTheIndexAndTheParts() async throws {
        let (repo, _) = try make()
        let id = try await saved(repo)
        try await repo.saveTranscript(recordingID: id, segments: lines(["secret pricing details"]), status: .done)
        let files = try await repo.delete(id: id)
        XCTAssertEqual(files, ["part-0001.caf"])
        let gone = try await repo.recording(id: id)
        XCTAssertNil(gone)
        let words = try await repo.segmentCount(recordingID: id)
        XCTAssertEqual(words, 0)
        let found = try await repo.search("pricing", in: nil, limit: 5)
        XCTAssertTrue(found.isEmpty, "the search index lets go too")
        let parts = try await repo.parts(recordingID: id)
        XCTAssertTrue(parts.isEmpty)
    }

    func testDeleteAllLeavesNoRecordingNoWordsAndNoSearchIndex() async throws {
        let (repo, database) = try make()
        let memories = SQLiteMemoryRepository(database: database)
        let a = try await saved(repo, start: 0)
        let b = try await saved(repo, start: 500)
        let open = UUID()
        _ = try await repo.begin(id: open, origin: .app, languageCode: "pl-PL", startedAt: at(900))
        _ = try await repo.openPart(recordingID: open, index: 1, startOffsetMilliseconds: 0)
        try await repo.saveTranscript(recordingID: a, segments: lines(["first words about pricing"]), status: .done)
        try await repo.saveTranscript(recordingID: b, segments: lines(["more words about pricing"]), status: .done)
        let note = try await memories.save(try CaptureMemory.newMemory(text: "Alex runs the launch", kind: .actionItem, savedAt: at(5)))
        try await repo.linkMemory(memoryID: note.id, recordingID: a, atMilliseconds: 1_000, recordingTitle: "A", linkedAt: at(6))

        try await repo.deleteAll()

        let list = try await repo.recordings(category: .all, limit: 10, offset: 0)
        XCTAssertTrue(list.isEmpty)
        let ids = try await repo.allIDs()
        XCTAssertTrue(ids.isEmpty)
        let found = try await repo.search("pricing", in: nil, limit: 5)
        XCTAssertTrue(found.isEmpty)
        let unfinished = try await repo.unfinished()
        XCTAssertTrue(unfinished.isEmpty, "a recording still being made goes too")
        let parts = try await repo.parts(recordingID: open)
        XCTAssertTrue(parts.isEmpty)
        let stillThere = try await memories.list(limit: nil)
        XCTAssertEqual(stillThere.map(\.id), [note.id], "notes are not recordings: they go with Delete all memories, not with this")
        let link = try await repo.provenance(forMemory: note.id)
        XCTAssertNil(link?.recordingID, "the note says where it came from but no longer points at anything")
    }

    func testDeleteAllLeavesNoWordsInTheDatabaseFile() async throws {
        let path = NSTemporaryDirectory() + "doddy-capture-wipeall-\(UUID().uuidString).sqlite"
        defer { for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let marker = "qzxvwipeallword"
        do {
            let repo = SQLiteRecordingRepository(database: try DoddyDatabase(path: path))
            let id = try await saved(repo)
            try await repo.saveTranscript(recordingID: id, segments: lines(["the \(marker) was said"]), status: .done)
            let found = try await repo.search(marker, in: nil, limit: 1)
            XCTAssertEqual(found.count, 1)
            try await repo.deleteAll()
        }
        var bytes = Data()
        for suffix in ["", "-wal"] { if let data = FileManager.default.contents(atPath: path + suffix) { bytes.append(data) } }
        XCTAssertNil(bytes.range(of: Data(marker.utf8)), "Delete everything takes the words out of the file too")
    }

    /// Not just gone from the queries: gone from the file on the iPhone.
    func testDeletedWordsAreNotLeftInTheDatabaseFile() async throws {
        let path = NSTemporaryDirectory() + "doddy-capture-wipe-\(UUID().uuidString).sqlite"
        defer { for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let marker = "qzxvmarkerword"
        let id = UUID()
        do {
            let repo = SQLiteRecordingRepository(database: try DoddyDatabase(path: path))
            _ = try await saved(repo, id: id)
            try await repo.saveTranscript(recordingID: id, segments: lines(["the \(marker) was said in a meeting"]), status: .done)
            let found = try await repo.search(marker, in: id, limit: 1)
            XCTAssertEqual(found.count, 1, "the marker was really indexed")
            _ = try await repo.delete(id: id)
        }
        var bytes = Data()
        for suffix in ["", "-wal"] { if let data = FileManager.default.contents(atPath: path + suffix) { bytes.append(data) } }
        XCTAssertFalse(bytes.isEmpty)
        XCTAssertNil(bytes.range(of: Data(marker.utf8)), "a deleted recording's words are overwritten in the file")
    }

    /// The same for a word the user corrected away, and for words replaced by a second write-out.
    func testCorrectedAndReplacedWordsAreNotLeftInTheDatabaseFile() async throws {
        let path = NSTemporaryDirectory() + "doddy-capture-edit-\(UUID().uuidString).sqlite"
        defer { for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let misheard = "qzxvmisheardword", replaced = "qzxvreplacedword"
        let repo = SQLiteRecordingRepository(database: try DoddyDatabase(path: path))
        let id = try await saved(repo)
        try await repo.saveTranscript(recordingID: id, segments: lines(["we said \(misheard) here", "and \(replaced) there"]), status: .done)
        _ = try await repo.editSegment(recordingID: id, index: 0, text: "we said something else here")
        try await repo.saveTranscript(recordingID: id, segments: lines(["we said something else here", "and another thing"]), status: .done)
        var bytes = Data()
        for suffix in ["", "-wal"] { if let data = FileManager.default.contents(atPath: path + suffix) { bytes.append(data) } }
        XCTAssertNil(bytes.range(of: Data(misheard.utf8)), "a corrected word does not linger")
        XCTAssertNil(bytes.range(of: Data(replaced.utf8)), "a replaced line does not linger")
    }
}
