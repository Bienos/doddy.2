import DoddyCore
import SwiftUI
import UserNotifications

/// "A thought is ready for review" (ADR-342). Off by default. When it is on, Doddy puts one
/// passive notification in iOS for the next chosen time, for the one note `ThoughtReview.due`
/// picks from the notes as they are now; it is rebuilt at every launch and return to the
/// foreground, so a deleted note is never offered. Passive: no sound, no banner, it waits in
/// Notification Center. It never carries the note's words; a tap opens the note in Doddy and
/// that is written in the review log, nothing else.
@MainActor
enum ThoughtReviewScheduler {
    enum Outcome: Equatable {
        case scheduled(Date)
        /// On, but no note is due yet (nothing older than a week, or everything reviewed lately).
        case nothingDue
        case off
        case needsPermission
        case failed
    }

    static let threadID = "doddy-thought-review"

    /// From the app's store: what is loaded now. Before the first load nothing is scheduled;
    /// the next refresh does it.
    static func refresh(store: MemoryStore) async -> Outcome {
        await apply(.stored(), memories: store.hasLoaded ? store.memories : nil)
    }

    static func apply(_ settings: ThoughtReviewSettings, memories: [MemoryRecord]?) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [ThoughtReview.notificationID])
        guard settings.isOn else { return .off }
        guard let memories else { return .nothingDue }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .needsPermission }
        await registerCategory()
        var log = ThoughtReviewLog.decoded(UserDefaults.standard.data(forKey: ThoughtReviewLog.storageKey))
        log.keepOnly(Set(memories.map(\.id)))
        save(log)
        // Private notes (ADR-310) are never offered.
        let shareable = PrivateNotesStore.current().shareable(memories)
        let now = Date()
        guard let note = ThoughtReview.due(memories: shareable, log: log, now: now) else { return .nothingDue }
        let fire = ThoughtReview.nextFire(after: now, hour: settings.hour, minute: settings.minute)
        let language = NotificationLanguage.current
        let content = UNMutableNotificationContent()
        content.title = ThoughtReview.title(language)
        content.body = ThoughtReview.body(language)
        content.categoryIdentifier = ThoughtReview.categoryID
        content.threadIdentifier = threadID
        content.interruptionLevel = .passive
        content.userInfo = [ThoughtReview.memoryIDKey: note.id.uuidString]
        // Doddy reading, lying on his front (ADR-313 art rules); none with Hide character artwork.
        if let art = NotificationArt.attachment(.bellyReading) { content.attachments = [art] }
        var when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        when.second = 0
        let request = UNNotificationRequest(
            identifier: ThoughtReview.notificationID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
        do { try await center.add(request) } catch { return .failed }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        return pending.contains(ThoughtReview.notificationID) ? .scheduled(fire) : .failed
    }

    /// The user opened the note from its notification: written in the log, read back.
    static func opened(_ id: UUID, at now: Date = Date()) {
        var log = ThoughtReviewLog.decoded(UserDefaults.standard.data(forKey: ThoughtReviewLog.storageKey))
        log.mark(id, at: now)
        save(log)
    }

    private static func save(_ log: ThoughtReviewLog) {
        if let data = try? log.encoded() {
            UserDefaults.standard.set(data, forKey: ThoughtReviewLog.storageKey)
        }
    }

    /// "Open the note" on a long press; added to the categories already registered.
    private static func registerCategory() async {
        let language = NotificationLanguage.current
        let open = UNNotificationAction(identifier: SystemNoteNotifications.openAction,
                                        title: ThoughtReview.openAction(language), options: [.foreground])
        let category = UNNotificationCategory(identifier: ThoughtReview.categoryID, actions: [open], intentIdentifiers: [], options: [])
        let center = UNUserNotificationCenter.current()
        let existing = await center.notificationCategories().filter { $0.identifier != ThoughtReview.categoryID }
        center.setNotificationCategories(existing.union([category]))
    }
}

/// Settings › Thought review: off by default; the time; read back from iOS.
struct ThoughtReviewSettingsSection: View {
    @Environment(MemoryStore.self) private var store
    @State private var settings = ThoughtReviewSettings.stored()
    @State private var outcome: ThoughtReviewScheduler.Outcome?

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: settings.hour, minute: settings.minute)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.hour = parts.hour ?? 19
                settings.minute = parts.minute ?? 30
            })
    }

    var body: some View {
        Section("A thought to review") {
            Toggle("Bring back a saved thought", isOn: $settings.isOn).accessibilityIdentifier("settings.thoughtReviewOn")
            if settings.isOn {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
            }
            if let outcome {
                Text(message(outcome)).font(.footnote)
                    .foregroundStyle(outcome == .failed || outcome == .needsPermission ? Theme.error : Theme.secondaryText)
            }
            Text("Once a day, at most, a quiet notification waits in Notification Center: \"A thought is ready for review\". It names no note. Tap it to read one note you saved about a week ago, or one you haven't looked at in a month. Lists and private notes stay out. Nothing is scored and nothing is sent anywhere.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .onChange(of: settings) {
            settings.store()
            let wanted = settings
            Task {
                let result = await ThoughtReviewScheduler.apply(wanted, memories: store.hasLoaded ? store.memories : nil)
                if wanted == settings { outcome = result }
            }
        }
    }

    private func message(_ outcome: ThoughtReviewScheduler.Outcome) -> String {
        switch outcome {
        case .scheduled(let date):
            return String(format: NSLocalizedString("Set. The next one comes %@.", comment: ""),
                          date.formatted(date: .abbreviated, time: .shortened))
        case .nothingDue: return NSLocalizedString("On. Nothing is due yet: a note comes back about a week after you save it.", comment: "")
        case .off: return NSLocalizedString("Off. Nothing is scheduled.", comment: "")
        case .needsPermission: return NSLocalizedString("Notifications are off for Doddy, so no thought can come back. Turn them on in iOS Settings.", comment: "")
        case .failed: return NSLocalizedString("The review couldn't be set. Try again.", comment: "")
        }
    }
}
