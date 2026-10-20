import DoddyCore
import SwiftUI
import UserNotifications

/// Puts the weekly tidy-up notification in iOS and reads it back (ADR-228).
enum TidyUpScheduler {
    enum Outcome: Equatable { case scheduled, off, needsPermission, failed }

    static func apply(_ settings: TidyUpSettings) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [TidyUp.notificationID])
        guard settings.isOn else { return .off }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .needsPermission }
        let language = NotificationLanguage.current
        let content = UNMutableNotificationContent()
        content.title = TidyUp.title(language)
        content.body = TidyUp.body(language)
        // Doddy kneeling to look the notes over (ADR-546); the words are unchanged.
        if let art = NotificationArt.attachment(for: .tidyUp) { content.attachments = [art] }
        var when = DateComponents()
        when.weekday = settings.weekday
        when.hour = settings.hour
        when.minute = settings.minute
        let request = UNNotificationRequest(
            identifier: TidyUp.notificationID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        do { try await center.add(request) } catch { return .failed }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        return pending.contains(TidyUp.notificationID) ? .scheduled : .failed
    }
}

/// The tidy-up screen: each suggestion has its own button; nothing happens without a tap.
struct TidyUpView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(NoteReminderStore.self) private var noteReminders
    @Environment(\.dismiss) private var dismiss
    @State private var kept: Set<UUID> = []
    @State private var confirmDelete: MemoryRecord?
    @State private var problem: String?
    @State private var lastDone: String?
    @State private var isUndoing = false
    private let sharing = SharedListsController.shared

    /// Notes with a photo or a voice memo are never offered as copies (review D2): deleting one
    /// would delete a different photo or recording.
    private var tidy: TidyUp.Suggestions {
        TidyUp.suggestions(
            memories: store.memories, lists: store.lists, reminders: noteReminders.reminders, now: .now,
            withAttachments: Set(store.photos.keys).union(store.recordings.keys))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    JourneyHeading(eyebrow: "Weekly tidy-up", title: "A little\ntidier.",
                                   subtitle: "Suggestions only. Nothing changes until you tap it.")
                    if let lastDone { Label(lastDone, systemImage: "checkmark.circle").foregroundStyle(Theme.confirmed) }
                    // The app's Undo bar is hidden under this sheet (review F3), so Undo is here too,
                    // for as long as the bar would offer it.
                    if store.recentlyDeleted != nil {
                        Button(isUndoing ? "Undoing…" : "Undo the delete") { Task { await undoDelete() } }
                            .disabled(isUndoing)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("tidy.undo")
                    }
                    if let problem { ProblemView(message: problem) }
                    let tidy = tidy
                    let duplicates = tidy.duplicates.filter { !kept.contains($0.id) }
                    let reminders = tidy.passedReminders.filter { !kept.contains($0.id) }
                    let lists = tidy.finishedLists.filter { !kept.contains($0.id) }
                    if duplicates.isEmpty && reminders.isEmpty && lists.isEmpty {
                        HStack(spacing: 14) {
                            // Nothing to do: he waits, cross-legged (ADR-313).
                            WholeDoddyView(pose: .crosslegged, height: 80)
                            Text("Nothing to tidy right now.").foregroundStyle(Theme.secondaryText)
                                .accessibilityIdentifier("tidy.nothing")
                        }
                    }
                    if !duplicates.isEmpty {
                        section("Saved twice") {
                            ForEach(duplicates) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.keep.currentText).lineLimit(3)
                                    Text("First saved \(DateText.full(group.keep.capturedAt)). Copies: \(group.copies.count).")
                                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                                    ForEach(group.copies) { copy in
                                        Button(role: .destructive) { confirmDelete = copy } label: {
                                            Text("Delete the copy from \(DateText.full(copy.capturedAt))")
                                        }
                                    }
                                    Button("Keep them all") { kept.insert(group.id) }
                                }
                                .modifier(TidyCard())
                            }
                        }
                    }
                    if !reminders.isEmpty {
                        section("Reminders that already passed") {
                            ForEach(reminders) { reminder in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(store.record(id: reminder.memoryID)?.currentText ?? "").lineLimit(3)
                                    if let fireAt = reminder.fireAt {
                                        Text("Was due \(DateText.full(fireAt)).").font(.footnote).foregroundStyle(Theme.secondaryText)
                                    }
                                    Button("Mark done") { Task { await markDone(reminder) } }
                                    Button("Leave it") { kept.insert(reminder.id) }
                                }
                                .modifier(TidyCard())
                            }
                        }
                    }
                    if !lists.isEmpty {
                        section("Lists with everything ticked") {
                            ForEach(lists) { list in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(list.name).font(.headline)
                                    Text("\(list.done.count) ticked").font(.footnote).foregroundStyle(Theme.secondaryText)
                                    Button("Clear the ticked items") { Task { await clear(list) } }
                                    Button(role: .destructive) { confirmDelete = list.record } label: { Text("Delete the list") }
                                    Button("Leave it") { kept.insert(list.id) }
                                }
                                .modifier(TidyCard())
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Theme.canvas).foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { DoddyWordmark() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete this?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible, presenting: confirmDelete) { record in
                Button("Delete", role: .destructive) { Task { await delete(record) } }
                Button("Cancel", role: .cancel) {}
            } message: { record in
                Text(deleteMessage(record))
            }
        }
        .task { await store.reload(); await noteReminders.reload() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title)).font(.headline)
            content()
        }
    }

    private func delete(_ record: MemoryRecord) async {
        do {
            // A shared list stops being shared first, so no copy and no invitees are left in
            // iCloud (review F2). Not confirmed: the list stays.
            try await sharing.stopSharingBeforeDeleting(record.id)
        } catch {
            problem = SharingError.message(for: error)
            return
        }
        do {
            try await store.delete(id: record.id)
            problem = nil
            lastDone = store.record(id: record.id) == nil ? NSLocalizedString("Deleted. You can undo it for a few seconds.", comment: "") : nil
        } catch {
            problem = UserFacingError.message(for: error)
        }
    }

    /// Undo (ADR-183) brings the note or list back, not its reminder and not its sharing, so the
    /// question says so before the delete (review F3).
    private func deleteMessage(_ record: MemoryRecord) -> String {
        var parts: [String] = []
        if let reminder = noteReminders.reminder(forMemory: record.id) {
            parts.append("Its reminder (\(ReminderFormat.short(reminder))) is cancelled too, and undo doesn't bring the reminder back.")
        }
        if let warning = sharing.deleteWarning(record.id) { parts.append(warning) }
        parts.append(NSLocalizedString("You can undo for a few seconds afterwards.", comment: ""))
        return parts.joined(separator: " ")
    }

    /// The same undo as the app's Undo bar; said done only when the store shows it back.
    private func undoDelete() async {
        guard let deleted = store.recentlyDeleted, !isUndoing else { return }
        isUndoing = true
        defer { isUndoing = false }
        do {
            try await store.undoDelete()
        } catch {
            problem = NSLocalizedString("Couldn't bring it back. Nothing changed.", comment: "")
            return
        }
        if store.record(id: deleted.record.id) != nil {
            problem = nil
            lastDone = NSLocalizedString("Brought back.", comment: "")
        } else {
            lastDone = nil
            problem = NSLocalizedString("The time to undo has passed, so it stays deleted.", comment: "")
        }
    }

    private func markDone(_ reminder: MemoryReminder) async {
        await noteReminders.done(reminderID: reminder.id)
        if noteReminders.reminders.contains(where: { $0.id == reminder.id }) {
            problem = NSLocalizedString("That reminder couldn't be marked done. It's unchanged.", comment: "")
        } else {
            problem = nil
            lastDone = "Reminder marked done."
        }
    }

    private func clear(_ list: DoddyList) async {
        do {
            try await store.clearTicked(listID: list.id)
            problem = nil
            lastDone = "Cleared the ticked items on \(list.name)."
        } catch {
            problem = UserFacingError.listMessage(for: error)
        }
    }
}

private struct TidyCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator))
    }
}

/// Settings › Weekly tidy-up: off by default; day and time; read back from iOS.
struct TidyUpSettingsSection: View {
    @State private var settings = TidyUpSettings.stored()
    @State private var outcome: TidyUpScheduler.Outcome?

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: settings.hour, minute: settings.minute)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.hour = parts.hour ?? 18
                settings.minute = parts.minute ?? 0
            })
    }

    var body: some View {
        Section("Weekly tidy-up") {
            Toggle("Weekly tidy-up", isOn: $settings.isOn).accessibilityIdentifier("settings.tidyOn")
            if settings.isOn {
                Picker("Day", selection: $settings.weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                }
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
            }
            if let outcome {
                Text(message(outcome)).font(.footnote)
                    .foregroundStyle(outcome == .failed || outcome == .needsPermission ? Theme.error : Theme.secondaryText)
            }
            Text("Once a week Doddy suggests notes saved twice, reminders that passed and lists with everything ticked. Nothing is deleted unless you tap it.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Button("Open the tidy-up now") { ShortcutRouter.shared.tidyUpOpened() }
        }
        .onChange(of: settings) {
            settings.store()
            let wanted = settings
            Task {
                let result = await TidyUpScheduler.apply(wanted)
                if wanted == settings { outcome = result }
            }
        }
    }

    private func message(_ outcome: TidyUpScheduler.Outcome) -> String {
        switch outcome {
        case .scheduled: return NSLocalizedString("Set. The tidy-up notification comes once a week.", comment: "")
        case .off: return NSLocalizedString("Off. Nothing is scheduled.", comment: "")
        case .needsPermission: return NSLocalizedString("Notifications are off for Doddy, so the tidy-up can't ring. Turn them on in iOS Settings.", comment: "")
        case .failed: return NSLocalizedString("The tidy-up couldn't be set. Try again.", comment: "")
        }
    }
}
