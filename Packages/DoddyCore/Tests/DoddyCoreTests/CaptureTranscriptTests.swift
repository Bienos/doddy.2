import DoddyCore
import Foundation
import XCTest

/// DODDY Capture (ADR-588): words from a recording, finding the part a question is about, and the
/// "Remember this" note.
final class CaptureTranscriptTests: XCTestCase {
    private func word(_ text: String, _ start: Int, _ duration: Int = 300, confidence: Double? = nil) -> TranscriptWord {
        TranscriptWord(text: text, startMilliseconds: start, durationMilliseconds: duration, confidence: confidence)
    }

    private func segment(_ index: Int, _ start: Int, _ end: Int, _ text: String, confidence: Double? = nil) -> TranscriptSegment {
        TranscriptSegment(index: index, startMilliseconds: start, endMilliseconds: end, text: text, confidence: confidence)
    }

    // MARK: - Grouping words

    func testALongPauseStartsANewLine() {
        let words = [word("Hello", 0), word("there", 400), word("again", 3_000), word("friend", 3_400)]
        let lines = TranscriptSegmenter.group(words)
        XCTAssertEqual(lines.map(\.text), ["Hello there", "again friend"])
        XCTAssertEqual(lines[0].startMilliseconds, 0)
        XCTAssertEqual(lines[0].endMilliseconds, 700)
    }

    func testASentenceEndsALineOnlyOnceThereIsEnoughToRead() {
        let short = [word("Yes.", 0), word("Fine", 400), word("then", 800)]
        XCTAssertEqual(TranscriptSegmenter.group(short).count, 1, "a short sentence stays with its neighbours")
        var words: [TranscriptWord] = []
        for (i, text) in ["We", "met", "on", "Monday", "at", "noon."].enumerated() { words.append(word(text, i * 400)) }
        words += [word("Then", 2_500), word("we", 2_900), word("left", 3_300)]
        XCTAssertEqual(TranscriptSegmenter.group(words).map(\.text), ["We met on Monday at noon.", "Then we left"])
    }

    func testNoLineRunsOnForever() {
        let words = (0..<100).map { word("w\($0)", $0 * 350, 300) }
        let lines = TranscriptSegmenter.group(words)
        XCTAssertGreaterThan(lines.count, 1)
        for line in lines {
            XCTAssertLessThanOrEqual(line.text.split(separator: " ").count, TranscriptSegmenter.maxWords)
            XCTAssertLessThanOrEqual(line.endMilliseconds - line.startMilliseconds, TranscriptSegmenter.maxSpanMilliseconds + 400)
        }
        XCTAssertEqual(lines.flatMap { $0.text.split(separator: " ") }.count, 100, "no word is lost or repeated")
    }

    func testConfidenceIsTheMeanOfWhatWasGivenAndZeroMeansNotGiven() {
        let given = [word("one", 0, confidence: 0.9), word("two", 400, confidence: 0.5), word("three", 800, confidence: 0)]
        XCTAssertEqual(try XCTUnwrap(TranscriptSegmenter.group(given).first?.confidence), 0.7, accuracy: 0.0001)
        let none = [word("one", 0, confidence: 0), word("two", 400)]
        XCTAssertNil(TranscriptSegmenter.group(none).first?.confidence)
    }

    func testEmptyWordsAndUnorderedWordsAreHandled() {
        let words = [word("b", 400), word("  ", 200), word("a", 0)]
        XCTAssertEqual(TranscriptSegmenter.group(words).map(\.text), ["a b"])
        XCTAssertTrue(TranscriptSegmenter.group([]).isEmpty)
    }

    // MARK: - Laying parts end to end

    func testPartsAreLaidEndToEndOnTheRecordingsOwnTime() {
        let first = AssemblyPart(offsetMilliseconds: 0, durationMilliseconds: 600_000, segments: [
            DraftSegment(startMilliseconds: 1_000, endMilliseconds: 5_000, text: "first line"),
        ])
        let second = AssemblyPart(offsetMilliseconds: 600_000, durationMilliseconds: 120_000, segments: [
            DraftSegment(startMilliseconds: 2_000, endMilliseconds: 6_000, text: "after the rotation", confidence: 0.8),
        ])
        let lines = TranscriptAssembler.assemble([second, first])
        XCTAssertEqual(lines.map(\.index), [0, 1])
        XCTAssertEqual(lines.map(\.text), ["first line", "after the rotation"])
        XCTAssertEqual(lines[1].startMilliseconds, 602_000)
        XCTAssertEqual(lines[1].endMilliseconds, 606_000)
        XCTAssertEqual(lines[1].confidence, 0.8)
        XCTAssertNil(lines[1].speaker, "no speaker is ever guessed")
    }

    func testALineIsKeptInsideItsOwnPartsAudioAndBlankOrPastTheEndIsDropped() {
        let part = AssemblyPart(offsetMilliseconds: 100_000, durationMilliseconds: 10_000, segments: [
            DraftSegment(startMilliseconds: 8_000, endMilliseconds: 15_000, text: "runs past the end"),
            DraftSegment(startMilliseconds: 12_500, endMilliseconds: 13_000, text: "a recognizer making things up"),
            DraftSegment(startMilliseconds: 1_000, endMilliseconds: 2_000, text: "   "),
            DraftSegment(startMilliseconds: -500, endMilliseconds: 1_000, text: "starts early"),
        ])
        let lines = TranscriptAssembler.assemble([part])
        XCTAssertEqual(lines.map(\.text), ["starts early", "runs past the end"])
        XCTAssertEqual(lines[0].startMilliseconds, 100_000)
        XCTAssertEqual(lines[1].endMilliseconds, 110_000, "cut at the end of the audio")
    }

    // MARK: - Quality

    func testNoWordsIsNoSpeech() {
        let quality = TranscriptQuality.assess([], durationMilliseconds: 120_000)
        XCTAssertEqual(quality.verdict, .noSpeech)
        XCTAssertFalse(quality.allowsSummary)
        XCTAssertNotNil(quality.message(.english))
    }

    func testAnAlmostSilentLongRecordingIsPoorButAShortOneIsNotJudgedByRate() {
        let sparse = [segment(0, 0, 3_000, "just a few words here")]
        XCTAssertEqual(TranscriptQuality.assess(sparse, durationMilliseconds: 600_000).verdict, .poor)
        XCTAssertEqual(TranscriptQuality.assess(sparse, durationMilliseconds: 20_000).verdict, .good, "twenty seconds can hold five words")
    }

    func testLowConfidenceIsPoorAndAnythingElseIsGood() {
        let text = String(repeating: "word ", count: 300)
        let unsure = [segment(0, 0, 60_000, text, confidence: 0.2)]
        XCTAssertEqual(TranscriptQuality.assess(unsure, durationMilliseconds: 120_000).verdict, .poor)
        XCTAssertTrue(TranscriptQuality.assess(unsure, durationMilliseconds: 120_000).message(.polish)!.contains("Jakość"))
        let sure = [segment(0, 0, 60_000, text, confidence: 0.9)]
        let good = TranscriptQuality.assess(sure, durationMilliseconds: 120_000)
        XCTAssertEqual(good.verdict, .good)
        XCTAssertTrue(good.allowsSummary)
        XCTAssertNil(good.message(.english))
        let notGiven = [segment(0, 0, 60_000, text)]
        XCTAssertEqual(TranscriptQuality.assess(notGiven, durationMilliseconds: 120_000).verdict, .good, "no confidence is not low confidence")
    }

    // MARK: - Corrections, fingerprint, export

    func testACorrectionIsCleanedAndCannotEmptyALine() {
        XCTAssertEqual(TranscriptEdit.cleaned("  Alex\n sends   the plan\t"), "Alex sends the plan")
        XCTAssertNil(TranscriptEdit.cleaned("  \n "))
        XCTAssertEqual(TranscriptEdit.cleaned(String(repeating: "a", count: 5_000))?.count, TranscriptEdit.maxCharacters)
        var line = segment(0, 0, 1_000, "Alex sent the plan")
        XCTAssertFalse(line.isEdited)
        line.text = "Alex sends the plan"
        XCTAssertTrue(line.isEdited)
        XCTAssertEqual(line.originalText, "Alex sent the plan", "what was recognised is kept beside the correction")
    }

    func testTheFingerprintFollowsTheWords() {
        let a = [segment(0, 0, 1_000, "one"), segment(1, 1_000, 2_000, "two")]
        var b = a
        XCTAssertEqual(TranscriptFormat.fingerprint(a), TranscriptFormat.fingerprint(b))
        XCTAssertEqual(TranscriptFormat.fingerprint(a).count, 16)
        b[1].text = "three"
        XCTAssertNotEqual(TranscriptFormat.fingerprint(a), TranscriptFormat.fingerprint(b), "a correction makes a summary out of date")
        XCTAssertNotEqual(TranscriptFormat.fingerprint([]), TranscriptFormat.fingerprint(a))
    }

    func testTheExportMarksQuietStretchesWhereTheyHappened() {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let lines = [segment(0, 0, 4_000, "before the call"), segment(1, 60_000, 64_000, "after the call")]
        let gaps = [CaptureGap(atMilliseconds: 30_000, wallMilliseconds: 192_000, reason: .interruption),
                    CaptureGap(atMilliseconds: 40_000, wallMilliseconds: 40, reason: .segmentRotation)]
        let text = TranscriptFormat.markdown(title: "Budget call", startedAt: Date(timeIntervalSince1970: 1_792_677_780), durationMilliseconds: 64_000,
                                             languageCode: "en-GB", segments: lines, gaps: gaps, .english, calendar: utc)
        let rows = text.components(separatedBy: "\n")
        let gapRow = try? XCTUnwrap(rows.firstIndex { $0.contains("interrupted (3:12)") })
        let afterRow = rows.firstIndex { $0.contains("after the call") }
        let beforeRow = rows.firstIndex { $0.contains("before the call") }
        XCTAssertNotNil(gapRow)
        XCTAssertTrue(beforeRow! < gapRow! && gapRow! < afterRow!, "the interruption sits between the two lines")
        XCTAssertFalse(text.contains("technical gap"), "a rotation's milliseconds are not mentioned")
        XCTAssertTrue(text.contains("may contain mistakes"))
        XCTAssertTrue(text.hasPrefix("# Budget call"))
    }

    // MARK: - Cutting and finding

    private func transcript(_ count: Int) -> [TranscriptSegment] {
        (0..<count).map { segment($0, $0 * 5_000, $0 * 5_000 + 4_000, "line number \($0) of the talk about topic \($0)") }
    }

    func testChunksCoverEveryLineAndOverlapByOne() {
        let lines = transcript(60)
        let chunks = TranscriptChunker.chunks(lines, maxCharacters: 400, overlapSegments: 1)
        XCTAssertGreaterThan(chunks.count, 3)
        XCTAssertEqual(chunks.first?.firstSegment, 0)
        XCTAssertEqual(chunks.last?.lastSegment, 59)
        for (a, b) in zip(chunks, chunks.dropFirst()) {
            XCTAssertEqual(b.firstSegment, a.lastSegment, "the last line of one starts the next")
            XCTAssertGreaterThan(b.firstSegment, a.firstSegment, "it always moves on")
        }
        for chunk in chunks { XCTAssertLessThanOrEqual(chunk.text.count, 400 + 80) }
        XCTAssertTrue(chunks[0].text.hasPrefix("[0:00] line number 0"))
        XCTAssertEqual(chunks[0].startMilliseconds, 0)
    }

    func testOneHugeLineIsItsOwnChunkAndNothingLoops() {
        let lines = [segment(0, 0, 1_000, String(repeating: "x", count: 5_000)), segment(1, 1_000, 2_000, "after")]
        let chunks = TranscriptChunker.chunks(lines, maxCharacters: 300, overlapSegments: 1)
        XCTAssertEqual(chunks.first?.firstSegment, 0)
        XCTAssertEqual(chunks.last?.lastSegment, 1)
        XCTAssertTrue(TranscriptChunker.chunks([]).isEmpty)
    }

    func testExcerptsWidenAHitJoinNeighboursAndStayInTimeOrder() {
        let lines = transcript(40)
        let result = ExcerptBuilder.excerpts(hits: [30, 10, 11], segments: lines, radius: 2, maxCharacters: 5_000, maxExcerpts: 5)
        XCTAssertEqual(result.map { [$0.firstSegment, $0.lastSegment] }, [[8, 13], [28, 32]], "10 and 11 became one stretch")
        XCTAssertTrue(result[0].text.contains("[0:40] line number 8"))
        XCTAssertFalse(result[0].plainText.contains("["), "the plain text has no time stamps to match against")
        XCTAssertEqual(result[1].startMilliseconds, 140_000)
    }

    func testTheMostRelevantHitIsKeptWhenTheBudgetRunsOut() {
        let lines = transcript(40)
        let one = ExcerptBuilder.excerpts(hits: [20], segments: lines, radius: 2, maxCharacters: 10_000)
        let budget = one[0].text.count + 20
        let result = ExcerptBuilder.excerpts(hits: [20, 5, 35], segments: lines, radius: 2, maxCharacters: budget)
        XCTAssertEqual(result.map(\.firstSegment), [18], "the first-ranked hit fills the budget; the others do not fit")
    }

    func testExcerptsIgnoreHitsOutsideTheTranscript() {
        XCTAssertTrue(ExcerptBuilder.excerpts(hits: [99, -1], segments: transcript(5)).isEmpty)
        XCTAssertTrue(ExcerptBuilder.excerpts(hits: [0], segments: []).isEmpty)
    }

    func testAQuestionBecomesTheSameSearchTheNotesUse() throws {
        let pattern = try XCTUnwrap(RecordingSearch.pattern(for: "What did Alex say about the budget?"))
        XCTAssertTrue(pattern.contains("\"alex\"*"))
        XCTAssertTrue(pattern.contains("\"budget\"*"))
        XCTAssertFalse(pattern.contains("\"the\""), "filler words are not searched for")
        XCTAssertNil(RecordingSearch.pattern(for: "what did the"), "nothing left to look for")
        XCTAssertNotNil(RecordingSearch.pattern(for: "Gdzie jest spotkanie klienta?"))
    }

    // MARK: - Remember this

    func testTheNoteSaysWhereItCameFromAndIsNotSavedByDrafting() throws {
        let text = CaptureMemory.draft(item: "Alex is responsible for the website launch", recordingTitle: "Budget call",
                                       atMilliseconds: 872_000, .english)
        XCTAssertEqual(text, "Alex is responsible for the website launch\n\nFrom the recording “Budget call”, 14:32.")
        XCTAssertTrue(CaptureMemory.draft(item: "Alex", recordingTitle: "Rozmowa", atMilliseconds: 5_000, .polish).hasSuffix("Z nagrania „Rozmowa”, 0:05."))
        let memory = try CaptureMemory.newMemory(text: text, kind: .actionItem, savedAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(memory.category, .commitment)
        XCTAssertEqual(memory.source, .explicitText, "a tap on Save is an explicit capture")
        XCTAssertEqual(memory.text, text)
    }

    func testOnlyTheChosenKindsGetATypeAndAnEmptyNoteIsRefused() {
        XCTAssertEqual(CaptureMemory.category(for: .decision), .decision)
        XCTAssertEqual(CaptureMemory.category(for: .fact), .fact)
        XCTAssertEqual(CaptureMemory.category(for: .excerpt), .other)
        XCTAssertThrowsError(try CaptureMemory.newMemory(text: "   ", kind: .fact, savedAt: Date()))
    }

    func testProvenanceSaysWhenTheRecordingIsGone() {
        XCTAssertEqual(CaptureMemory.provenance(recordingTitle: "Budget call", atMilliseconds: 872_000, recordingStillExists: true, .english),
                       "From the recording “Budget call”, 14:32")
        XCTAssertTrue(CaptureMemory.provenance(recordingTitle: "Budget call", atMilliseconds: 872_000, recordingStillExists: false, .english)!.hasSuffix("(the recording was deleted)"))
        XCTAssertNil(CaptureMemory.provenance(recordingTitle: nil, atMilliseconds: 0, recordingStillExists: false, .english), "an ordinary note has no provenance")
    }
}
