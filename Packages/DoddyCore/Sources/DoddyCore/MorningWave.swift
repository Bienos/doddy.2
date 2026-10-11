import Foundation

/// When Home's Doddy waves instead of breathing (ADR-380): the first time Home shows on a
/// morning (before noon). Only the day it last waved is kept ("yyyy-MM-dd", on this iPhone); it is
/// not a note and is never sent anywhere.
public enum MorningWave {
    /// The day as stored: Gregorian, so a Buddhist or Japanese calendar doesn't change the key.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The day to store when he waves now, or nil when he shouldn't (afternoon, or already waved today).
    public static func dayToRecord(now: Date, lastWaveDay: String?, calendar: Calendar = .current) -> String? {
        guard calendar.component(.hour, from: now) < 12 else { return nil }
        let day = dayKey(now, calendar: calendar)
        return day == lastWaveDay ? nil : day
    }
}
