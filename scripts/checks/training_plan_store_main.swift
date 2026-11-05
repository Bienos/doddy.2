// Runs TrainingPlanStore (ADR-625) against real files: scripts/check_training_plan_store.sh.
import Foundation
@MainActor func run() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sport-\(UUID())")
    let url = dir.appendingPathComponent("Sport/training-plan.json")
    var fails = 0
    func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }

    let request = PlanRequest(goal: .tenK, level: .some, daysPerWeek: 3, minutesPerSession: 45, screening: .clear(age: 30))
    guard case .plan(let plan) = PlanEngine.make(request) else { print("FAIL the engine makes a 10 km plan"); exit(1) }
    let start = PlanStart(year: 2026, month: 10, day: 26)

    let a = TrainingPlanStore(fileURL: url)
    check(a.state == .nothingKept && a.saved == nil, "no file: nothing kept")
    check(a.keep(plan, start: start) && a.saved?.plan == plan && a.saved?.start == start && a.problem == nil, "kept and read back")
    // "Restart": a new store reads the file.
    let b = TrainingPlanStore(fileURL: url)
    check(b.saved == a.saved, "restart reads back exactly")
    #if canImport(Darwin)
    let excluded = (try? url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup
    check(excluded == true, "the folder is left out of backups")
    #endif

    // A changed file is not shown as Doddy's plan, and isn't written over by reading it.
    var text = try! String(contentsOf: url, encoding: .utf8)
    let longRun = plan.weeks[0].sessions.last!
    text = text.replacingOccurrences(of: "\"kind\":\"longRun\",\"minutes\":\(longRun.minutes)", with: "\"kind\":\"longRun\",\"minutes\":\(longRun.minutes + 40)")
    try! text.write(to: url, atomically: true, encoding: .utf8)
    let c = TrainingPlanStore(fileURL: url)
    check(c.state == .notThisDoddysPlan && (try? String(contentsOf: url, encoding: .utf8)) == text, "an edited plan isn't Doddy's and stays as it is")

    // A file Doddy can't read stays until the person decides.
    try! Data("garbage".utf8).write(to: url)
    let d = TrainingPlanStore(fileURL: url)
    check(d.state == .unreadable && (try? String(contentsOf: url, encoding: .utf8)) == "garbage", "unreadable file kept, not written over")
    check(d.keep(plan, start: start) && TrainingPlanStore(fileURL: url).saved?.plan == plan, "keeping a new plan replaces it")

    // Delete: gone from disk.
    check(d.delete() && d.state == .nothingKept && !FileManager.default.fileExists(atPath: url.path), "delete removes the file")
    check(TrainingPlanStore(fileURL: url).state == .nothingKept, "nothing after a restart")

    // A write that can't happen says so, and keeps nothing.
    let blocker = dir.appendingPathComponent("blocker")
    try! Data("a file, not a folder".utf8).write(to: blocker)
    let e = TrainingPlanStore(fileURL: blocker.appendingPathComponent("training-plan.json"))
    check(!e.keep(plan, start: start) && e.problem != nil && e.saved == nil, "a failed write is reported and nothing claimed")
    try? FileManager.default.removeItem(at: dir)
    print(fails == 0 ? "ALL PASS" : "\(fails) FAILED"); if fails > 0 { exit(1) }
}
@main struct Main { static func main() { MainActor.assumeIsolated { run() } } }
