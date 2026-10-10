import DoddyCore
import Foundation
import Observation
import UserNotifications

/// The morning brief's one daily local notification (ADR-212). Same words every day, so nothing
/// personal is on the Lock Screen and nothing runs in the background. Only the identifier
/// `MorningBriefNotification.identifier` is touched here; timers, nudges, note reminders and server
/// pushes share iOS's queue and are left alone.
enum MorningBriefNotifications {
    enum Outcome: Equatable {
        /// Read back from iOS's pending list at the asked time.
        case set
        /// iOS accepted it but didn't list it as asked: not claimed as set.
        case unconfirmed
        /// Notifications are off for Doddy (or the user said no).
        case notificationsOff
        case failed(String)
    }

    static func current() -> MorningBriefSchedule {
        let defaults = UserDefaults.standard
        return MorningBriefSchedule(
            isOn: defaults.bool(forKey: PreferenceKey.morningBriefOn),
            hour: defaults.object(forKey: PreferenceKey.morningBriefHour) as? Int ?? MorningBriefSchedule.defaultHour,
            minute: defaults.object(forKey: PreferenceKey.morningBriefMinute) as? Int ?? MorningBriefSchedule.defaultMinute)
    }

    /// Adds (or replaces) the daily notification at `schedule`'s time in the iPhone's current zone,
    /// then reads it back. Asks for notification permission only when `mayAsk`.
    static func schedule(_ schedule: MorningBriefSchedule, mayAsk: Bool) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, mayAsk {
            // Same options as timers and note reminders; no badge, no provisional delivery.
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .ephemeral else { return .notificationsOff }

        let content = UNMutableNotificationContent()
        content.title = MorningBriefNotification.title
        content.body = MorningBriefNotification.body
        content.sound = .default
        content.interruptionLevel = .active
        // No zone: the brief follows the iPhone's local morning wherever the user is.
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: schedule.hour, minute: schedule.minute), repeats: true)
        do {
            try await center.add(UNNotificationRequest(
                identifier: MorningBriefNotification.identifier, content: content, trigger: trigger))
        } catch {
            return .failed(error.localizedDescription)
        }
        let pending = await center.pendingNotificationRequests()
        guard let found = pending.first(where: { $0.identifier == MorningBriefNotification.identifier }),
              let listed = found.trigger as? UNCalendarNotificationTrigger, listed.repeats,
              listed.dateComponents.hour == schedule.hour, listed.dateComponents.minute == schedule.minute
        else { return .unconfirmed }
        return .set
    }

    /// Removes the daily notification and checks iOS no longer lists it.
    static func cancel() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [MorningBriefNotification.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [MorningBriefNotification.identifier])
        return !(await center.pendingNotificationRequests()).contains { $0.identifier == MorningBriefNotification.identifier }
    }

    /// At launch: keep iOS's list equal to the setting, without asking for permission.
    static func syncAtLaunch() async {
        // UI-test launches never touch iOS notifications (as for note reminders).
        guard !ProcessInfo.processInfo.arguments.contains("-inMemoryStore") else { return }
        let schedule = current()
        if schedule.isOn {
            _ = await self.schedule(schedule, mayAsk: false)
        } else {
            _ = await cancel()
        }
    }
}

extension MorningBriefSections {
    /// The choices in Settings → Morning brief → In your brief.
    static func stored(_ defaults: UserDefaults = .standard) -> MorningBriefSections {
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        let standard = MorningBriefSections.standard
        return MorningBriefSections(
            events: flag(PreferenceKey.morningBriefEvents, standard.events),
            reminders: flag(PreferenceKey.morningBriefReminders, standard.reminders),
            noteReminders: flag(PreferenceKey.morningBriefNoteReminders, standard.noteReminders),
            news: flag(PreferenceKey.morningBriefNews, standard.news),
            todoist: flag(PreferenceKey.morningBriefTodoist, standard.todoist),
            gmail: flag(PreferenceKey.morningBriefGmail, standard.gmail),
            gmailImportantOnly: flag(PreferenceKey.morningBriefGmailImportant, standard.gmailImportantOnly))
    }
}

/// What the server sections returned this morning (ADR-213). Kept in memory only (email subjects
/// and task titles are never written to disk) and fetched at most once per day and choice, unless
/// the user taps Refresh, so opening Home again doesn't ask Doddy's server again.
@MainActor
final class MorningBriefOnlineCache {
    static let shared = MorningBriefOnlineCache()
    private var key: String?
    private var value: BriefOnline?

    func value(for key: String) -> BriefOnline? { self.key == key ? value : nil }

    func store(_ value: BriefOnline, for key: String) {
        self.key = key
        self.value = value
    }

    func clear() {
        key = nil
        value = nil
    }

    /// Fetches the chosen sections, all at once. Sections not chosen are never asked for.
    static func fetch(_ sections: MorningBriefSections, now: Date, calendar: Calendar) async -> BriefOnline {
        let accounts = sections.todoist || sections.gmail ? OnlineAccountsClientFactory.make() : nil
        let news = sections.news ? ServerConfig.client() : nil
        let zone = calendar.timeZone.identifier
        async let todoist: BriefFetch<BriefOnlineList> = sections.todoist
            ? MorningBriefFetcher.todoist(accounts, timeZone: zone) : .notIncluded
        async let gmail: BriefFetch<BriefOnlineList> = sections.gmail
            ? MorningBriefFetcher.gmail(accounts, importantOnly: sections.gmailImportantOnly, timeZone: zone) : .notIncluded
        async let digest = newsSection(sections.news, client: news, now: now, calendar: calendar)
        return BriefOnline(news: await digest, todoist: await todoist, gmail: await gmail)
    }

    private static func newsSection(_ chosen: Bool, client: DoddyServerClient?, now: Date, calendar: Calendar) async -> BriefFetch<[NewsDigest.Item]> {
        guard chosen else { return .notIncluded }
        guard let client else { return .unavailable("Doddy's server for daily news isn't set up.") }
        return await MorningBriefFetcher.news({ try await client.newsDigests() }, now: now, calendar: calendar)
    }
}

/// A tap on the brief's notification opens Home.
@MainActor
@Observable
final class MorningBriefRouter {
    static let shared = MorningBriefRouter()
    var openRequested = false
}
