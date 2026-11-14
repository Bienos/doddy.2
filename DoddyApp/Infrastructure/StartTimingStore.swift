import DoddyCore
import Foundation

/// Keeps the Action Button's timing lines on this iPhone, so they can be read without a Mac (decision
/// 2026-11-14-start-timing-on-the-phone): Settings › About › Advanced › Start timing shows them and copies them.
/// The lines are the ones the log already has (`talk start launch`, `talk start timing`, `voice first audible
/// sound after start`); what may be kept is decided by `StartTimingJournal` (fixed openings, fixed characters, a
/// length limit), so nothing else can get in. Nothing here is sent anywhere.
///
/// One value in the app's own preferences (`PreferenceKey.startTimingJournal`, erased by "Erase everything on this
/// iPhone"). Every read and write goes through one serial queue: a line is written in the order it was recorded
/// and never on the thread that recorded it (a press must not wait for it), and a read sees every line recorded
/// before it.
final class StartTimingStore: @unchecked Sendable {
    static let shared = StartTimingStore()

    private let defaults: UserDefaults
    private let key: String
    private let queue = DispatchQueue(label: "doddy.start-timing", qos: .utility)

    init(defaults: UserDefaults = .standard, key: String = PreferenceKey.startTimingJournal) {
        self.defaults = defaults
        self.key = key
    }

    /// Adds one line, later and in order; the time is the time of this call. A line that isn't one of ours
    /// (`StartTimingJournal.accepts`) is ignored.
    func record(_ text: String, at date: Date = Date()) {
        queue.async { [defaults, key] in
            var journal = StartTimingJournal.decode(defaults.data(forKey: key))
            guard journal.record(text, at: date), let data = journal.encoded() else { return }
            defaults.set(data, forKey: key)
        }
    }

    /// What is kept now, read from the preferences again (not remembered), so what a screen shows is what is stored.
    func journal() -> StartTimingJournal {
        queue.sync { StartTimingJournal.decode(defaults.data(forKey: key)) }
    }

    /// Removes everything kept. The journal is read back by the caller to show it empty.
    func clear() {
        queue.sync { defaults.removeObject(forKey: key) }
    }
}
