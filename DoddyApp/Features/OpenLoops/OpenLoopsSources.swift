import DoddyCore
import Foundation

/// The only place the "Na oku" page reads the app's stores (ADR-728). It collects what each source already
/// holds into an `OpenLoopsInput` and decides two things for the builder:
/// - **Words.** A reminder on a private note comes back with `.hidden` words unless Face ID has unlocked private
///   notes, the same rule as Home's "Due now" card (ADR-310). A note that no longer exists is `.hidden` too.
/// - **Unreadable is not empty.** A source the person turned on but the app can't read now (a permission
///   revoked, Settings › Pause all, a store that failed to open) goes in `unavailable`. A source the person
///   never turned on is simply not asked, and nothing is claimed about it.
/// It stores nothing, schedules nothing and starts no look-up: the tasks are read from this iPhone's copy,
/// parcels are not looked up, and the price watches are re-read from Doddy's server only if the Tasks screen
/// already loaded them in this session (the same request that screen makes).
/// NOT COMPILED in the session that wrote it (no Xcode): the hosted Mac job is its first build.
@MainActor
struct OpenLoopsSources {
    private let noteReminders: NoteReminderStore
    private let memories: MemoryStore
    private let devices = DeviceConnections()
    /// Calendar days looked ahead for events (a later event is listed only while a nudge holds it).
    static let eventDays = 7

    init(noteReminders: NoteReminderStore, memories: MemoryStore) {
        self.noteReminders = noteReminders
        self.memories = memories
    }

    func read(now: Date = .now, calendar: Calendar = .current) async -> OpenLoopsInput {
        var input = OpenLoopsInput()
        await readNoteReminders(into: &input)
        await readDevice(into: &input, now: now, calendar: calendar)
        await readErrands(into: &input)
        await readWatches(into: &input)
        readParcels(into: &input)
        return input
    }

    // MARK: Sources

    private func readNoteReminders(into input: inout OpenLoopsInput) async {
        guard noteReminders.isAvailable else {
            input.unavailable.insert(.noteReminder)
            return
        }
        await noteReminders.reload()
        let privateNotes = PrivateNotesStore.current()
        let unlocked = AppLock.shared.privateUnlocked
        input.noteReminders = noteReminders.reminders.map { reminder in
            OpenLoopNoteReminder(reminder: reminder, title: title(forMemory: reminder.memoryID, privateNotes: privateNotes, unlocked: unlocked))
        }
    }

    private func title(forMemory id: UUID, privateNotes: PrivateNotes, unlocked: Bool) -> OpenLoopTitle {
        if privateNotes.contains(id) && !unlocked { return .hidden }
        guard let record = memories.record(id: id) else { return .hidden }
        let line = record.currentText.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? .hidden : .text(String(line.prefix(80)))
    }

    private func readDevice(into input: inout OpenLoopsInput, now: Date, calendar: Calendar) async {
        let defaults = UserDefaults.standard
        let paused = defaults.bool(forKey: ConnectionPause.preferenceKey)
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: Self.eventDays, to: start) ?? now
        for (connection, source) in [(VoiceConnection.calendar, OpenLoopSource.calendarEvent), (.reminders, .appleReminder)] {
            // Never turned on: nothing is asked and nothing is claimed.
            guard defaults.bool(forKey: connection.preferenceKey) else { continue }
            guard !paused, devices.access(for: connection) == .granted else {
                input.unavailable.insert(source)
                continue
            }
            switch source {
            case .calendarEvent:
                input.events = devices.events(in: VoiceTimeRange(start: start, end: end))
                input.nudges = await devices.pendingNudges()
            default:
                input.appleReminders = await devices.remindersDue(by: end, calendar: calendar)
            }
        }
    }

    private func readErrands(into input: inout OpenLoopsInput) async {
        let model = ErrandsModel.shared
        await model.load()
        if model.loadProblem != nil { input.unavailable.insert(.errand) } else { input.errands = model.errands }
    }

    private func readWatches(into input: inout OpenLoopsInput) async {
        let model = WatchModel.shared
        // Watches live on Doddy's server. Nothing is asked of it here unless the Tasks screen already did.
        guard model.hasLoaded else { return }
        await model.refresh()
        if model.loadProblem != nil { input.unavailable.insert(.priceWatch) } else { input.watches = model.watches }
    }

    private func readParcels(into input: inout OpenLoopsInput) {
        let parcels = ParcelsModel(
            fetcher: InPostTrackingClient.shared,
            isPaused: { UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) })
        // Off until the person turns the list on; nothing is looked up either way.
        if parcels.isOn { input.parcels = parcels.entries }
    }
}
