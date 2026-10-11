// Runs UnfinishedNoteStore (ADR-340) against real files: scripts/check_unfinished_note_store.sh.
import Foundation
@MainActor func run() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("drafts-\(UUID())")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("unfinished-notes.json")
    var fails = 0
    func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { fails += 1 } }

    let a = UnfinishedNoteStore(fileURL: url)
    let id = UUID()
    a.keep(UnfinishedNote(id: id, text: "Kod do bramy 4821", category: .place, startedAt: Date(), updatedAt: Date()))
    check(!FileManager.default.fileExists(atPath: url.path), "nothing written before the delay")
    a.flush()
    // "Restart": a new store reads the file.
    let b = UnfinishedNoteStore(fileURL: url)
    check(b.book.newest?.text == "Kod do bramy 4821" && b.book.newest?.category == .place && b.book == a.book, "restart reads back exactly")
    // Debounced write lands by itself.
    guard var typed = b.book.newest else { check(false, "the draft is there after the restart"); exit(1) }
    typed.text = "Kod do bramy 4821, klucz pod wycieraczką"; typed.updatedAt = Date()
    b.keep(typed)
    try? await Task.sleep(for: .milliseconds(900))
    check(UnfinishedNoteStore(fileURL: url).book.newest?.text == typed.text, "a typed change is on disk after the delay")
    // Saved: gone, and the empty book removes the file.
    b.remove(id: id)
    check(!FileManager.default.fileExists(atPath: url.path) && UnfinishedNoteStore(fileURL: url).book.notes.isEmpty, "saved draft removed from disk")
    // A file Doddy can't read is set aside, not written over.
    try! Data("garbage".utf8).write(to: url)
    let c = UnfinishedNoteStore(fileURL: url)
    let aside = dir.appendingPathComponent("unfinished-notes.unreadable.json")
    check(c.problem != nil && FileManager.default.fileExists(atPath: aside.path) && (try? String(contentsOf: aside, encoding: .utf8)) == "garbage", "unreadable file kept aside")
    c.keep(UnfinishedNote(text: "new", startedAt: Date())); c.flush()
    check(c.problem == nil && FileManager.default.fileExists(atPath: aside.path), "new draft written, aside file kept")
    c.removeAll()
    check(!FileManager.default.fileExists(atPath: aside.path) && !FileManager.default.fileExists(atPath: url.path), "delete all removes both")
    // A write that can't happen says so.
    let d = UnfinishedNoteStore(fileURL: dir.appendingPathComponent("missing-dir/x.json"))
    d.keep(UnfinishedNote(text: "x", startedAt: Date())); d.flush()
    check(d.problem != nil, "a failed write is reported")
    print(fails == 0 ? "ALL PASS" : "\(fails) FAILED"); if fails > 0 { exit(1) }
}
@main struct Main { static func main() async { await run() } }
