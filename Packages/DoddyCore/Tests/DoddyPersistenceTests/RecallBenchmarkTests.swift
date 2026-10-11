import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// Recall benchmark (OP-016 / OP-008, ADR-249). Saves the notes of
/// `docs/quality/evals/recall_golden_v1.json` into the real SQLite store, asks every question
/// through `RepositoryRecallService` with the app's limit, and scores the answers against the
/// labels. Nothing is mocked: the numbers are what the shipping word rules do.
///
/// - Normal run (CI): fails if a question found (or put first) in the committed baseline no
///   longer is. Questions that newly pass are listed, so the baseline can be raised on purpose.
/// - `DODDY_RECALL_REPORT=<path>` also writes the Markdown report there.
/// - `DODDY_RECALL_UPDATE_BASELINE=1` rewrites the baseline from this run instead of checking it.
/// `scripts/recall_benchmark.sh` does both.
final class RecallBenchmarkTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let corpusURL = repoRoot.appendingPathComponent("docs/quality/evals/recall_golden_v1.json")
    static let baselineURL = repoRoot.appendingPathComponent("docs/quality/evals/recall_baseline_v1.json")
    /// The app asks for 20 (`MemoryStore.recall`, `AssistantService`), and Find shows all of them.
    static let appLimit = 20

    func testCorpusIsWellFormed() throws {
        let corpus = try Corpus.load(Self.corpusURL)
        let noteIDs = corpus.notes.map(\.id)
        XCTAssertEqual(Set(noteIDs).count, noteIDs.count, "duplicate note id")
        let queryIDs = corpus.queries.map(\.id)
        XCTAssertEqual(Set(queryIDs).count, queryIDs.count, "duplicate question id")
        XCTAssertTrue(Set(noteIDs).isDisjoint(with: queryIDs))
        for note in corpus.notes {
            XCTAssertTrue(["en", "pl"].contains(note.lang), note.id)
            XCTAssertFalse(note.text.isEmpty, note.id)
        }
        for query in corpus.queries {
            XCTAssertTrue(["en", "pl"].contains(query.lang), query.id)
            XCTAssertFalse(query.tags.isEmpty, query.id)
            XCTAssertTrue(Set(query.tags).isSubset(of: corpus.tags.keys), "\(query.id): unknown tag")
            XCTAssertTrue(Set(query.relevant).isSubset(of: noteIDs), "\(query.id): label names a missing note")
            // A question with no answer is labelled should_miss, and only then.
            XCTAssertEqual(query.relevant.isEmpty, query.tags.contains("should_miss"), query.id)
        }
        XCTAssertTrue(corpus.queries.contains { $0.lang == "pl" } && corpus.queries.contains { $0.lang == "en" })
    }

    /// The scoring itself, on answers written by hand, so the numbers mean what the report says.
    func testScoringCountsFoundFirstWrongAndHonestMisses() {
        let find = Query(id: "a", lang: "en", query: "x", relevant: ["n1", "n2"], tags: ["exact"])
        let miss = Query(id: "b", lang: "pl", query: "y", relevant: [], tags: ["should_miss"])
        let results = [
            QueryResult(query: find, returned: ["n9", "n2", "n8"], partial: true),  // found, second, two wrong, flagged
            QueryResult(query: find, returned: ["n1"], partial: false),             // found, first
            QueryResult(query: find, returned: [], partial: false),                 // not found
            QueryResult(query: miss, returned: [], partial: false),                 // honest no match
            QueryResult(query: miss, returned: ["n3"], partial: false),             // shown as an answer
            QueryResult(query: miss, returned: ["n4"], partial: true),              // shown, flagged partial
        ]
        XCTAssertEqual(results.map(\.passed), [true, true, false, true, false, true])
        XCTAssertEqual(results.map(\.first), [false, true, false, true, false, true])
        XCTAssertEqual(results[0].rank, 2)
        XCTAssertEqual(results[0].wrong, 2)

        let score = Score(results)
        XCTAssertEqual(score.findCount, 3)
        XCTAssertEqual(score.found, 2)
        XCTAssertEqual(score.top1, 1)
        XCTAssertEqual(score.top3, 2)
        XCTAssertEqual(score.reciprocalRankSum, 1.5, accuracy: 1e-9)
        XCTAssertEqual(score.wrongShown, 2)
        XCTAssertEqual(score.flaggedPartial, 1)
        XCTAssertEqual(score.missCount, 3)
        XCTAssertEqual(score.saidNoMatch, 1)
        XCTAssertEqual(score.honestAnswers, 2)
    }

    func testRecallBenchmarkHasNoRegressions() async throws {
        let corpus = try Corpus.load(Self.corpusURL)
        let results = try await Self.run(corpus)
        let env = ProcessInfo.processInfo.environment

        if let path = env["DODDY_RECALL_REPORT"], !path.isEmpty {
            try Report.markdown(corpus, results).write(toFile: path, atomically: true, encoding: .utf8)
        }
        if env["DODDY_RECALL_UPDATE_BASELINE"] == "1" {
            try Baseline(corpusVersion: corpus.version, results: results).write(Self.baselineURL)
            return
        }

        let baseline = try Baseline.load(Self.baselineURL)
        XCTAssertEqual(baseline.corpusVersion, corpus.version, "baseline is for another corpus version")
        var improved: [String] = []
        for result in results {
            guard let before = baseline.queries[result.query.id] else {
                XCTFail("\(result.query.id) has no baseline; run scripts/recall_benchmark.sh --update-baseline")
                continue
            }
            if !result.shouldMiss, before.partial == false, result.partial {
                XCTFail("\(result.query.id) \"\(result.query.query)\" is now flagged as a partial match: \(Report.describe(result))")
            }
            if before.passed && !result.passed {
                XCTFail("\(result.query.id) \"\(result.query.query)\" regressed: \(Report.describe(result))")
            } else if before.first && !result.first {
                XCTFail("\(result.query.id) \"\(result.query.query)\" no longer puts a right note first: \(Report.describe(result))")
            }
            if (!before.passed && result.passed) || (!before.first && result.first)
                || (!result.shouldMiss && before.partial == true && !result.partial) { improved.append(result.query.id) }
        }
        if !improved.isEmpty {
            print("Recall benchmark: improved \(improved.joined(separator: ", ")); raise the baseline with scripts/recall_benchmark.sh --update-baseline")
        }
    }

    // MARK: Running

    static func run(_ corpus: Corpus) async throws -> [QueryResult] {
        let repo = try SQLiteMemoryRepository.inMemory()
        var noteIDByRecord: [UUID: String] = [:]
        // One minute apart, oldest first, so the newest-first scan order is fixed.
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        for (index, note) in corpus.notes.enumerated() {
            let saved = try await repo.save(NewMemory(text: note.text, capturedAt: t0.addingTimeInterval(Double(index) * 60)))
            noteIDByRecord[saved.id] = note.id
        }
        let recall = RepositoryRecallService(repository: repo)
        var results: [QueryResult] = []
        for query in corpus.queries {
            switch try await recall.recall(query.query, limit: appLimit) {
            case .noMatch:
                results.append(QueryResult(query: query, returned: [], partial: false))
            case .matches(let candidates):
                // Same check the Find screen and the voice reply make (ADR-251).
                let partial = RecallCoverage(question: query.query, candidates: candidates).isPartial
                results.append(QueryResult(query: query, returned: candidates.map { noteIDByRecord[$0.memoryID] ?? "?" }, partial: partial))
            }
        }
        return results
    }
}

// MARK: Corpus

struct Corpus: Decodable {
    let version: Int
    let labelledBy: String
    let tags: [String: String]
    let notes: [Note]
    let queries: [Query]

    enum CodingKeys: String, CodingKey {
        case version, tags, notes, queries
        case labelledBy = "labelled_by"
    }

    static func load(_ url: URL) throws -> Corpus {
        try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }
}

struct Note: Decodable {
    let id: String
    let lang: String
    let text: String
}

struct Query: Decodable {
    let id: String
    let lang: String
    let query: String
    let relevant: [String]
    let tags: [String]
}

// MARK: Scoring

struct QueryResult {
    let query: Query
    /// Corpus note ids, in the order recall returned them; empty means no match.
    let returned: [String]
    /// The answer says no note covers the whole question (`RecallCoverage`, ADR-251).
    let partial: Bool

    var shouldMiss: Bool { query.relevant.isEmpty }
    /// 1-based position of the first right note, if any.
    var rank: Int? { returned.firstIndex(where: query.relevant.contains).map { $0 + 1 } }
    /// A right note was among the results. For a question with no answer: an honest answer,
    /// which is "no match" or notes clearly flagged as only a partial match.
    var passed: Bool { shouldMiss ? returned.isEmpty || partial : rank != nil }
    var first: Bool { shouldMiss ? passed : rank == 1 }
    /// Notes shown that are not an answer.
    var wrong: Int { returned.filter { !query.relevant.contains($0) }.count }
}

struct Score {
    var findCount = 0, found = 0, top1 = 0, top3 = 0, wrongShown = 0
    var reciprocalRankSum = 0.0
    /// Answerable questions whose answer was flagged as partial.
    var flaggedPartial = 0
    var missCount = 0, saidNoMatch = 0, honestAnswers = 0

    init(_ results: [QueryResult]) {
        for result in results {
            if result.shouldMiss {
                missCount += 1
                if result.returned.isEmpty { saidNoMatch += 1 }
                if result.passed { honestAnswers += 1 }
                continue
            }
            findCount += 1
            wrongShown += result.wrong
            if result.partial { flaggedPartial += 1 }
            guard let rank = result.rank else { continue }
            found += 1
            if rank == 1 { top1 += 1 }
            if rank <= 3 { top3 += 1 }
            reciprocalRankSum += 1 / Double(rank)
        }
    }
}

// MARK: Baseline

struct Baseline: Codable {
    struct Entry: Codable {
        let passed: Bool
        let first: Bool
        /// Flagged as a partial match (ADR-251); absent in baselines from before that.
        let partial: Bool?
    }

    let corpusVersion: Int
    let queries: [String: Entry]

    enum CodingKeys: String, CodingKey {
        case queries
        case corpusVersion = "corpus_version"
    }

    init(corpusVersion: Int, results: [QueryResult]) {
        self.corpusVersion = corpusVersion
        self.queries = Dictionary(uniqueKeysWithValues: results.map {
            ($0.query.id, Entry(passed: $0.passed, first: $0.first, partial: $0.partial))
        })
    }

    static func load(_ url: URL) throws -> Baseline {
        try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: url))
    }

    func write(_ url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(self)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: Report

enum Report {
    static func describe(_ result: QueryResult) -> String {
        let got = result.returned.isEmpty ? "no match" : result.returned.prefix(5).joined(separator: ", ")
            + (result.returned.count > 5 ? " (+\(result.returned.count - 5))" : "")
        let wanted = result.shouldMiss ? "no match" : result.query.relevant.joined(separator: " or ")
        return "wanted \(wanted), got \(got)"
    }

    static func markdown(_ corpus: Corpus, _ results: [QueryResult]) -> String {
        var out: [String] = []
        func line(_ text: String = "") { out.append(text) }
        func pct(_ part: Int, _ whole: Int) -> String {
            whole == 0 ? "–" : "\(part)/\(whole) (\(Int((Double(part) / Double(whole) * 100).rounded()))%)"
        }
        func row(_ label: String, _ group: [QueryResult]) -> String {
            let s = Score(group)
            let mrr = s.findCount == 0 ? "–" : String(format: "%.2f", s.reciprocalRankSum / Double(s.findCount))
            let wrong = s.findCount == 0 ? "–" : String(format: "%.1f", Double(s.wrongShown) / Double(s.findCount))
            return "| \(label) | \(pct(s.found, s.findCount)) | \(pct(s.top1, s.findCount)) | \(pct(s.top3, s.findCount)) | \(mrr) | \(wrong) | \(pct(s.flaggedPartial, s.findCount)) | \(pct(s.saidNoMatch, s.missCount)) | \(pct(s.honestAnswers, s.missCount)) |"
        }
        let header = "| | Found (any right note in the list) | Right note first | Right note in top 3 | MRR | Wrong notes shown per question | Answer flagged partial | Said \"no match\" | Honest answer (no match, or flagged partial) |"
        let divider = "|---|---|---|---|---|---|---|---|---|"

        line("# Recall benchmark — generated report")
        line()
        line("Generated by `scripts/recall_benchmark.sh` from `docs/quality/evals/recall_golden_v1.json` (corpus v\(corpus.version)); do not edit by hand. Decision: `DECISIONS.md` ADR-249.")
        line()
        line("**What this measures:** the shipping word rules (`RecallMatching`, FTS5 in `SQLiteMemoryRepository`) through `RepositoryRecallService`, on the real SQLite store, with the app's limit of \(RecallBenchmarkTests.appLimit) results. \(corpus.notes.count) invented notes, \(results.count) questions.")
        line()
        line("**What it does not measure:** real users, real notes or real wording. Labels: \(corpus.labelledBy)")
        line()
        line("## Summary")
        line()
        line(header)
        line(divider)
        line(row("All", results))
        line(row("English questions", results.filter { $0.query.lang == "en" }))
        line(row("Polish questions", results.filter { $0.query.lang == "pl" }))
        line()
        line("Found, first, top 3, MRR, wrong notes and \"flagged partial\" count only questions that have an answer; for those, a partial flag is a false alarm, since the note does answer. \"No match\" and \"honest answer\" count only the \(Score(results).missCount) questions that have none. A flagged partial answer still lists the notes, but says which words no note has (ADR-251).")
        line()
        line("## By kind of question")
        line()
        line(header)
        line(divider)
        for tag in corpus.tags.keys.sorted() {
            let group = results.filter { $0.query.tags.contains(tag) }
            if !group.isEmpty { line(row("`\(tag)` (\(group.count))", group)) }
        }
        line()
        line("## Questions that failed")
        line()
        let failed = results.filter { !$0.passed }
        if failed.isEmpty { line("None.") }
        for result in failed {
            line("- **\(result.query.id)** (\(result.query.lang), \(result.query.tags.joined(separator: ", "))) \"\(result.query.query)\" — \(describe(result))")
        }
        line()
        line("## Found, but a wrong note came first")
        line()
        let late = results.filter { $0.passed && !$0.first }
        if late.isEmpty { line("None.") }
        for result in late {
            line("- **\(result.query.id)** \"\(result.query.query)\" — right note at \(result.rank.map(String.init) ?? "?"); \(describe(result))")
        }
        line()
        line("## Answerable, but flagged as partial")
        line()
        line("The right notes are listed, but the answer says a word of the question is in no note. Usually a word the note doesn't use (\"say\", \"leave\").")
        line()
        let flagged = results.filter { !$0.shouldMiss && $0.partial }
        if flagged.isEmpty { line("None.") }
        for result in flagged {
            line("- **\(result.query.id)** \"\(result.query.query)\" — \(describe(result))")
        }
        line()
        line("## Every question")
        line()
        line("| ID | Lang | Question | Wanted | Got (first 5) | Result |")
        line("|---|---|---|---|---|---|")
        // "partial" marks an answer flagged as covering only part of the question.
        for result in results {
            let wanted = result.shouldMiss ? "no match" : result.query.relevant.joined(separator: ", ")
            let got = result.returned.isEmpty ? "no match" : result.returned.prefix(5).joined(separator: ", ")
                + (result.returned.count > 5 ? " (+\(result.returned.count - 5))" : "")
            var verdict = !result.passed ? "FAIL" : result.first ? "pass" : "pass (not first)"
            if result.partial { verdict += ", partial" }
            line("| \(result.query.id) | \(result.query.lang) | \(result.query.query.replacingOccurrences(of: "|", with: "\\|")) | \(wanted) | \(got) | \(verdict) |")
        }
        line()
        line("## Notes")
        line()
        line("| ID | Lang | Text |")
        line("|---|---|---|")
        for note in corpus.notes {
            line("| \(note.id) | \(note.lang) | \(note.text.replacingOccurrences(of: "|", with: "\\|")) |")
        }
        return out.joined(separator: "\n") + "\n"
    }
}
