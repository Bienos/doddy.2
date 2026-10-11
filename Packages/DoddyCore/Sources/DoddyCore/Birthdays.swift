import Foundation

// Birthday reminders from contacts (ADR-288). Off until the user turns it on, and then only for
// the people they pick: Settings › Birthdays lists the contacts that have a birthday, each with
// its own switch, all off. A picked birthday becomes Doddy's own yearly notification at 09:00 on
// the day, read back from iOS. Contacts are read on this iPhone only (with Contacts on in
// Connections); nothing goes to the voice agent or any server. The notification names the
// person only when the user lets notifications show note text; otherwise it says "A birthday
// today". Nothing is added to the Calendar or Reminders apps.

public struct BirthdayContact: Equatable, Sendable, Identifiable {
    /// The contact's identifier on this iPhone.
    public let id: String
    public let name: String
    public let month: Int
    public let day: Int

    public init(id: String, name: String, month: Int, day: Int) {
        self.id = id
        self.name = name
        self.month = month
        self.day = day
    }
}

public enum Birthdays {
    /// iOS keeps at most 64 pending notifications for an app; birthdays may use this many.
    public static let maxReminders = 20
    public static let hour = 9
    public static let notificationPrefix = "doddy.birthday."
    public static let pickedKey = "birthdays.picked"

    public static func isBirthday(notificationID: String) -> Bool { notificationID.hasPrefix(notificationPrefix) }

    /// A request id per contact that never shows the contact id itself.
    public static func notificationID(for contactID: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in contactID.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return notificationPrefix + String(hash, radix: 16)
    }

    /// Contacts with a valid birthday, the next one first. 29 February counts as 28 February in
    /// other years, as many calendars do; it is scheduled on 28 February every year.
    public static func upcoming(_ contacts: [BirthdayContact], now: Date, calendar: Calendar) -> [BirthdayContact] {
        let today = calendar.dateComponents([.month, .day], from: now)
        let todayKey = (today.month ?? 1) * 100 + (today.day ?? 1)
        return contacts
            .filter { (1...12).contains($0.month) && (1...31).contains($0.day) }
            .sorted { lhs, rhs in
                let a = lhs.month * 100 + lhs.day, b = rhs.month * 100 + rhs.day
                let aNext = a >= todayKey ? a : a + 10_000, bNext = b >= todayKey ? b : b + 10_000
                return aNext != bNext ? aNext < bNext : lhs.name < rhs.name
            }
    }

    /// The day it is scheduled on: 29 February moves to 28 February.
    public static func scheduledDay(_ contact: BirthdayContact) -> (month: Int, day: Int) {
        contact.month == 2 && contact.day == 29 ? (2, 28) : (contact.month, contact.day)
    }

    /// Picked contacts that still exist with a birthday, at most `maxReminders`, next first.
    public static func toSchedule(_ contacts: [BirthdayContact], picked: Set<String>, now: Date, calendar: Calendar) -> [BirthdayContact] {
        Array(upcoming(contacts.filter { picked.contains($0.id) }, now: now, calendar: calendar).prefix(maxReminders))
    }

    public static func title(_ name: String?, _ language: NotificationLanguage) -> String {
        switch (name, language) {
        case (let name?, .polish): "Urodziny: \(name)"
        case (let name?, .english): "\(name)'s birthday"
        case (nil, .polish): "Dzisiaj są czyjeś urodziny"
        case (nil, .english): "A birthday today"
        }
    }

    public static func body(_ language: NotificationLanguage) -> String {
        language == .polish ? "Może warto się odezwać." : "Maybe say hello."
    }
}
