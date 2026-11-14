import DoddyCore
import Foundation

/// Keeps the Action Button's timing lines on this iPhone, so they can be read without a Mac (decision
/// 2026-11-14-start-timing-on-the-phone): Settings › About › Advanced › Start timing shows them and copies them.
/// The lines are the ones the log already has (`talk start launch`, `talk start timing`, `voice first audible
/// sound after start`); what may be kept is decided by `StartTimingJournal` (fixed openings, fixed characters, a
/// length limit), so nothing else can get in. Nothing here is sent anywhere.
///
/// One value in the app's own preferences (`PreferenceKey.startTimingJournal`, erased by "Erase everything on this
/// iPhone"). Read and written under a lock: the first-sound line arrives on a background queue.
final class StartTimingStore: @unchecked Sendable {
    static let shared = StartTimingStore()

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, key: String = PreferenceKey.startTimingJournal) {
        self.defaults = defaults
        self.key = key
    }

    /// Adds one line. A line that isn't one of ours (`StartTimingJournal.accepts`) is ignored.
    func record(_ text: String, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var journal = StartTimingJournal.decode(defaults.data(forKey: key))
        guard journal.record(text, at: date), let data = journal.encoded() else { return }
        defaults.set(data, forKey: key)
    }

    /// What is kept now, read from the preferences again (not remembered), so what a screen shows is what is stored.
    func journal() -> StartTimingJournal {
        lock.lock()
        defer { lock.unlock() }
        return StartTimingJournal.decode(defaults.data(forKey: key))
    }

    /// Removes everything kept. The journal is read back by the caller to show it empty.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}
