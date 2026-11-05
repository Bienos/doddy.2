import Foundation
import XCTest
@testable import DoddyCore

/// Golden tests: `MotionEngine`, driven through the owner's 25 studies on the reference layout,
/// reproduces what the renderer measured in each clip (`design/motion-v2/telemetry/*.json`):
/// every hop within ±1 ms and ±0.5 pt, the tab commits, braces, ride peaks, the listening
/// frames, every scale change, the event log and the final state.
final class MotionTelemetryTests: XCTestCase {
    static let telemetryDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("design/motion-v2/telemetry")

    static let ms = 1.0
    static let pt = 0.5

    func telemetry(_ id: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.telemetryDir.appendingPathComponent("\(id).json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEveryStudyHasTelemetry() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.telemetryDir.path)
            .filter { $0.hasSuffix(".json") && $0 != "timing.json" }
            .map { String($0.dropLast(5)) }
        XCTAssertEqual(Set(files), Set(ReferenceStudies.all.map(\.id)))
        XCTAssertEqual(files.count, 25)
    }

    func testEveryStudyMatchesItsTelemetry() throws {
        for study in ReferenceStudies.all {
            try check(study)
        }
    }

    // MARK: Comparison

    func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    func near(_ a: Double?, _ b: Any?, _ tol: Double, _ what: String, _ id: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let a, let b = num(b) else {
            XCTFail("\(id): \(what) missing (\(String(describing: a)) vs \(String(describing: b)))", file: file, line: line)
            return
        }
        XCTAssertLessThanOrEqual(abs(a - b), tol, "\(id): \(what) \(a) vs \(b)", file: file, line: line)
    }

    func check(_ study: ReferenceStudy, file: StaticString = #filePath, line: UInt = #line) throws {
        let id = study.id
        let ref = try telemetry(id)
        let w = study.run()
        let m = w.engine.metrics

        XCTAssertEqual(w.frames, ref["frames"] as? Int, "\(id): frames")

        // Hops.
        let hops = ref["hops"] as? [[String: Any]] ?? []
        XCTAssertEqual(m.hops.count, hops.count, "\(id): hop count")
        for (i, (h, r)) in zip(m.hops, hops).enumerated() {
            let tag = "hop \(i) (\(r["why"] as? String ?? ""))"
            XCTAssertEqual(h.why, r["why"] as? String, "\(id): \(tag) why")
            XCTAssertEqual(h.from, r["from"] as? String, "\(id): \(tag) from")
            XCTAssertEqual(h.to, r["to"] as? String, "\(id): \(tag) to")
            near(h.requestedAt, r["tReq"], Self.ms, "\(tag) request", id)
            near(h.tapAt, r["tap"], Self.ms, "\(tag) tap", id)
            near(h.anticipation, r["ant"], Self.ms, "\(tag) anticipation", id)
            near(h.startScale, r["s0"], 1e-6, "\(tag) s0", id)
            near(h.endScale, r["s1"], 1e-6, "\(tag) s1", id)
            if let tabTap = r["tabTap"] as? Bool { XCTAssertEqual(h.isTabHop, tabTap, "\(id): \(tag) tab hop") }
            if r["cancelled"] != nil {
                near(h.cancelledAt, r["cancelled"], Self.ms, "\(tag) cancelled", id)
                continue
            }
            // "capped" is false or the formula's flight time (always over 260 ms).
            if let capped = num(r["capped"]), capped > 1 { near(h.cappedFrom, capped, 0.5, "\(tag) capped", id) } else { XCTAssertNil(h.cappedFrom, "\(id): \(tag) not capped") }
            near(h.takeoffAt, r["takeoff"], Self.ms, "\(tag) take-off", id)
            near(h.crouch, r["crouch"], Self.ms, "\(tag) crouch", id)
            near(h.flightTime, r["T"], Self.ms, "\(tag) flight", id)
            near(h.distance, r["D"], Self.pt, "\(tag) distance", id)
            near(h.apex, r["A"], Self.pt, "\(tag) apex", id)
            if let p0 = r["p0"] as? [String: Any] {
                near(h.start?.x, p0["x"], Self.pt, "\(tag) p0.x", id)
                near(h.start?.y, p0["y"], Self.pt, "\(tag) p0.y", id)
            }
            if let p1 = r["p1"] as? [String: Any] {
                near(h.end?.x, p1["x"], Self.pt, "\(tag) p1.x", id)
                near(h.end?.y, p1["y"], Self.pt, "\(tag) p1.y", id)
            }
            near(h.contactAt, r["contact"], Self.ms, "\(tag) contact", id)
            near(h.contactAfterTap, r["contactAfterTap"], Self.ms, "\(tag) contact after tap", id)
            near(h.impact, r["impact"], 1, "\(tag) impact speed", id)
            near(h.squash, r["squashPt"], 0.011, "\(tag) squash", id)
            near(h.landScale, r["landScale"], 1e-6, "\(tag) land scale", id)
            if r["retargets"] != nil {
                XCTAssertEqual(h.retargets, r["retargets"] as? Int, "\(id): \(tag) retargets")
                near(h.retargetAt, r["retargetAt"], Self.ms, "\(tag) re-target time", id)
                near(h.retargetFlightTime, r["T2"], Self.ms, "\(tag) re-target flight", id)
            }
            if r["reaimed"] != nil { XCTAssertTrue(h.reaimedInCrouch, "\(id): \(tag) re-aimed") }
        }

        // Tab commits.
        let taps = ref["tabTaps"] as? [[String: Any]] ?? []
        XCTAssertEqual(w.tabTaps.count, taps.count, "\(id): tab taps")
        for (a, r) in zip(w.tabTaps, taps) {
            near(a.t, r["t"], Self.ms, "tab tap", id)
            XCTAssertEqual(a.tab, r["tab"] as? String, "\(id): tab")
            if r["done"] is NSNull || r["done"] == nil {
                XCTAssertNil(a.done, "\(id): tab never finished committing")
            } else {
                near(a.done, r["done"], Self.ms, "tab done", id)
            }
        }

        // Braces and ride peaks (acceleration within 1 %).
        let braces = ref["braces"] as? [[String: Any]] ?? []
        XCTAssertEqual(m.braces.count, braces.count, "\(id): braces")
        for (b, r) in zip(m.braces, braces) {
            near(b.t, r["t"], Self.ms, "brace time", id)
            near(b.acc, r["acc"], max(1, (num(r["acc"]) ?? 0) * 0.01), "brace acceleration", id)
        }
        let peaks = ref["ridePeaks"] as? [[String: Any]] ?? []
        XCTAssertEqual(m.ridePeaks.count, peaks.count, "\(id): ride peaks")
        for (p, r) in zip(m.ridePeaks, peaks) {
            near(p.t, r["t"], Self.ms, "ride peak time", id)
            XCTAssertEqual(p.surface, r["surface"] as? String, "\(id): ride peak surface")
            near(p.peak, r["peak"], max(1, (num(r["peak"]) ?? 0) * 0.01), "ride peak", id)
        }

        // Rule checks the renderer ran every frame.
        XCTAssertEqual(w.violations.count, (ref["violations"] as? [Any])?.count ?? 0, "\(id): violations \(w.violations)")
        near(w.maxContactGap, ref["maxContactGap"], 0.01, "max contact gap", id)
        near(w.maxComposerGap, ref["maxComposerGap"], 0.01, "max composer gap", id)
        near(m.listenFrames, ref["listenFrames"], 0.5, "listening frames", id)
        XCTAssertEqual(w.listenViolations, ref["listenViolations"] as? Int, "\(id): listening violations")
        let playful = ref["playful"] as? [[String: Any]] ?? []
        XCTAssertEqual(m.playful.count, playful.count, "\(id): playful moments")
        for (p, r) in zip(m.playful, playful) {
            near(p.t, r["t"], Self.ms, "playful time", id)
            XCTAssertEqual(p.kind, r["kind"] as? String, "\(id): playful kind")
            XCTAssertEqual(p.duringTask, r["duringTask"] as? Bool, "\(id): playful during a task")
        }
        let scales = ref["scaleChanges"] as? [[String: Any]] ?? []
        XCTAssertEqual(w.scaleChanges.count, scales.count, "\(id): scale changes")
        for (s, r) in zip(w.scaleChanges, scales) {
            near(s.t, r["t"], Self.ms, "scale change time", id)
            XCTAssertEqual(s.mode, r["mode"] as? String, "\(id): scale change mode")
            near(s.s, r["s"], 0.0011, "scale", id)
            XCTAssertEqual(s.ok, r["ok"] as? Bool, "\(id): scale change allowed")
        }

        // The event log, line for line.
        let events = ref["events"] as? [[String: Any]] ?? []
        XCTAssertEqual(m.events.count, events.count, "\(id): event count\n\(m.events.map { "\(Int($0.t)) \($0.message)" }.joined(separator: "\n"))")
        for (e, r) in zip(m.events, events) {
            XCTAssertEqual(e.message, r["msg"] as? String, "\(id): event at \(e.t)")
            near(e.t, r["t"], Self.ms, "event time (\(e.message))", id)
        }

        // Where he ends.
        let fin = try XCTUnwrap(ref["final"] as? [String: Any])
        let mine = w.finalState()
        for key in ["screen", "tab", "mode", "activity", "mood", "gaze"] {
            XCTAssertEqual(mine[key] as? String, fin[key] as? String, "\(id): final \(key)")
        }
        XCTAssertEqual(mine["surface"] as? String, fin["surface"] as? String, "\(id): final surface")
        near(num(mine["x"]), fin["x"], Self.pt, "final x", id)
        near(num(mine["y"]), fin["y"], Self.pt, "final y", id)
        near(num(mine["scale"]), fin["scale"], 1e-3, "final scale", id)
        near(num(mine["opacity"]), fin["opacity"], 1e-3, "final opacity", id)
        XCTAssertEqual(mine["mic"] as? Bool, fin["mic"] as? Bool, "\(id): final mic")
        near(w.now, fin["t"], Self.ms, "final time", id)
    }
}
