import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// Opt-in synthetic benchmark; no timing threshold in CI and no user content/provider calls.
/// Run the identical fixture before and after a change, in the same build configuration.
final class MemoryRetrievalBenchmarkTests: XCTestCase {
    /// A small transparent diagnostic corpus, not a representative benchmark or model evaluation.
    /// Includes two deliberate paraphrase gaps that keyword lookup is not expected to solve.
    func testSyntheticRetrievalQuality() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DODDY_MEMORY_BENCHMARK"] == "1", "opt-in local evaluation")
        let repository = try SQLiteMemoryRepository.inMemory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let texts = [
            "music": "My favourite music is hypnotic techno.",
            "restaurant": "Marta poleciła restaurację Zapiecek w Warszawie.",
            "decision": "DODDY onboarding decision: ask two optional questions.",
            "keys": "Spare keys in the blue tin.",
            "code": "Kod do bramy 4821.",
            "birthday": "Urodziny mam 14 maja.",
            "job": "I work at Company Amber.",
            "jazz": "Lubię słuchać jazzu ostatnio.",
            "private": "Obsidian is a private synthetic detail.",
        ]
        var records: [String: MemoryRecord] = [:]
        for key in texts.keys.sorted() {
            records[key] = try await repository.save(NewMemory(text: texts[key]!, capturedAt: now))
        }
        _ = try await repository.update(id: records["job"]!.id, currentText: "I work at Company Birch.")
        let hidden = records["private"]!.id
        let recall = ShareableRecallService(base: RepositoryRecallService(repository: repository), privateIDs: { [hidden] })
        let cases: [(id: String, query: String, gold: String?)] = [
            ("music", "What kind of music do I like?", "music"),
            ("restaurant_en", "What restaurant did Marta recommend?", "restaurant"),
            ("decision", "What did we decide about DODDY onboarding?", "decision"),
            ("keys_pl", "Gdzie są klucze?", "keys"),
            ("code_en", "What code did I save?", "code"),
            ("birthday_en", "When is my birthday?", "birthday"),
            ("current_job", "Where do I work?", "job"),
            ("restaurant_paraphrase", "That place with great dumplings", "restaurant"),
            ("jazz_paraphrase_en", "What genre have I been enjoying recently?", "jazz"),
            ("unknown_blood", "What is my blood group?", nil),
            ("unknown_school", "What school did I attend?", nil),
            ("private", "Obsidian", nil),
            ("edited_away", "Amber", nil),
        ]
        for item in cases {
            let hits: [MemoryCandidate]
            if case .matches(let found) = try await recall.recall(item.query, limit: 5) { hits = found } else { hits = [] }
            let relevant = item.gold.map { key in hits.contains { $0.memoryID == records[key]!.id } ? 1 : 0 } ?? 0
            var report: [String: Any] = ["case": item.id, "returned": hits.count, "relevant_returned": relevant,
                                       "answerable": item.gold != nil, "precision_at_5": Double(relevant) / 5]
            if item.gold != nil { report["recall_at_5"] = relevant }
            else { report["empty_result"] = hits.isEmpty }
            let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print("DODDY_MEMORY_EVALUATION " + String(decoding: json, as: UTF8.self))
        }
    }

    func testSyntheticRetrievalTimings() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["DODDY_MEMORY_BENCHMARK"] == "1", "opt-in local benchmark")
        let clock = ContinuousClock()
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        for count in [1_000, 5_000, 10_000] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("synthetic.sqlite")
            let repository = try SQLiteMemoryRepository(path: url.path)
            for index in 0..<count {
                let text = index == 0 ? "Restauracja Zapiecek, pierogi w Warszawie."
                    : "Synthetic notebook item \(index), blue folder, project planning."
                _ = try await repository.save(NewMemory(text: text, capturedAt: time.addingTimeInterval(Double(index))))
            }
            let service = RepositoryRecallService(repository: repository)
            for (kind, query) in [("exact", "Zapiecek"), ("none", "qzxvbnm"),
                                  ("typo", "Zapiecekk"), ("bilingual", "restaurant")] {
                for _ in 0..<2 { _ = try await service.recall(query, limit: 20) }
                var milliseconds: [Double] = []
                var hitCount = 0
                for _ in 0..<20 {
                    let start = clock.now
                    let outcome = try await service.recall(query, limit: 20)
                    let duration = start.duration(to: clock.now).components
                    milliseconds.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
                    if case .matches(let hits) = outcome { hitCount = hits.count }
                }
                milliseconds.sort()
                let bytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
                let report: [String: Any] = [
                    "label": environment["DODDY_BENCHMARK_LABEL"] ?? "unspecified", "notes": count,
                    "kind": kind, "samples": milliseconds.count, "p50_ms": milliseconds[9],
                    "p95_ms": milliseconds[18], "hits": hitCount, "database_bytes": bytes?.intValue ?? 0,
                ]
                let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                print("DODDY_MEMORY_BENCHMARK " + String(decoding: json, as: UTF8.self))
            }
        }
    }
}
