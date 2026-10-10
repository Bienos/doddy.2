import Foundation

/// The user's own words for when, checked against the day and time the agent wrote out
/// (ADR-215, research backlog OP-014). The agent turns "next Friday at 7" into a date; these
/// fixed rules decide whether that date follows from the words, and ask one question instead of
/// guessing when the words allow two answers. No model is involved: English and Polish words only.
///
/// It catches three things:
/// - words that allow two days or two times: "next Friday", "this weekend", "next week",
///   "at 7" with nothing saying morning or evening;
/// - a time the user never said: "tomorrow morning" sent as 09:00;
/// - a date that contradicts the words: "Friday" sent as a Thursday, "tomorrow" sent as today,
///   "at 9" sent as 10:00, "16 October" sent as the 17th, "in 2 hours" sent for tomorrow.
/// Words it doesn't understand are not judged: no question is asked about them.
public enum SaidTime {
    /// One question for the agent to ask, or nil when the date follows from the words.
    /// `timeRequired` is true for calendar events and note reminders, false for Apple Reminders
    /// (where a day without a time is a valid answer).
    public static func check(_ said: String, due: ReminderDue, now: Date, timeRequired: Bool) -> ReminderClarification? {
        let words = Words(said)
        guard !words.tokens.isEmpty, let dueDate = due.date else { return nil }
        let calendar = due.calendar
        let quoted = "\"\(said.trimmingCharacters(in: .whitespacesAndNewlines))\""
        return dayProblem(words, quoted: quoted, due: due, dueDate: dueDate, now: now, calendar: calendar)
            ?? timeProblem(words, quoted: quoted, due: due, dueDate: dueDate, now: now, calendar: calendar, timeRequired: timeRequired)
    }

    // MARK: Day

    private static func dayProblem(
        _ words: Words, quoted: String, due: ReminderDue, dueDate: Date, now: Date, calendar: Calendar
    ) -> ReminderClarification? {
        let today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: dueDate)).day ?? 0
        let dueText = describe(due, calendar: calendar, now: now)
        func differs(_ why: String) -> ReminderClarification {
            ReminderClarification(
                kind: .saidDifferently,
                problem: "the user said \(quoted) but the request says \(dueText), \(why)",
                question: "which day and time they mean")
        }

        // Relative days. "Day after tomorrow" first: it contains "tomorrow".
        let relative: (Int, String)? =
            words.has(phrase: "day after tomorrow") || words.has("pojutrze") ? (2, "which is not the day after tomorrow")
            : words.has("tomorrow", "jutro") ? (1, "which is not tomorrow")
            : words.has("today", "tonight", "dzis", "dzisiaj") || words.has(phrase: "this evening")
                || words.has(phrase: "this morning") || words.has(phrase: "this afternoon") ? (0, "which is not today")
            : nil
        if let (expected, why) = relative, offset != expected { return differs(why) }

        // A date written out: "16 October", "October 16th", "16 października".
        if let date = words.dayAndMonth {
            if date.day != due.day || date.month != due.month { return differs("which is not \(date.text)") }
            return nil  // A full date settles the day; "next Friday 16 October" is not ambiguous.
        }

        let named = Set(words.tokens.compactMap { weekdays[$0] })
        if named.count > 1 { return nil }  // "Monday or Tuesday": not something to check.
        let dueWeekday = calendar.component(.weekday, from: dueDate)
        if let weekday = named.first {
            if weekday != dueWeekday { return differs("which is a \(weekdayName(dueWeekday)), not a \(weekdayName(weekday))") }
            let dayNumberSaid = words.dayNumbers.contains(due.day)
            if words.saysNext(beforeWeekday: true), !dayNumberSaid {
                // "next Friday": the coming Friday or the one after it.
                let coming = nextDate(weekday: weekday, after: today, calendar: calendar)
                let following = calendar.date(byAdding: .day, value: 7, to: coming) ?? coming
                let a = describe(day: coming, calendar: calendar, now: now)
                let b = describe(day: following, calendar: calendar, now: now)
                return ReminderClarification(
                    kind: .ambiguousDay,
                    problem: "\(quoted) can mean \(a) or \(b)",
                    question: "whether they mean \(a) or \(b), and call again with the day written out")
            }
            return nil
        }

        if words.has("weekend", "weekendzie", "weekendu"), words.dayNumbers.isEmpty {
            let saturday = nextDate(weekday: 7, after: calendar.date(byAdding: .day, value: -1, to: today) ?? today, calendar: calendar)
            let sunday = calendar.date(byAdding: .day, value: 1, to: saturday) ?? saturday
            let a = describe(day: saturday, calendar: calendar, now: now)
            let b = describe(day: sunday, calendar: calendar, now: now)
            return ReminderClarification(
                kind: .ambiguousDay,
                problem: "\(quoted) can mean \(a) or \(b)",
                question: "whether they mean \(a) or \(b)")
        }

        if words.saysNextWeek, words.dayNumbers.isEmpty {
            return ReminderClarification(
                kind: .ambiguousDay,
                problem: "\(quoted) doesn't say which day of next week",
                question: "which day next week they mean")
        }
        return nil
    }

    // MARK: Time

    private static func timeProblem(
        _ words: Words, quoted: String, due: ReminderDue, dueDate: Date, now: Date, calendar: Calendar, timeRequired: Bool
    ) -> ReminderClarification? {
        let dueText = describe(due, calendar: calendar, now: now)
        func differs(_ why: String) -> ReminderClarification {
            ReminderClarification(
                kind: .saidDifferently,
                problem: "the user said \(quoted) but the request says \(dueText), \(why)",
                question: "which day and time they mean")
        }

        // "in 2 hours", "za 30 minut": due should be that long from now.
        if let minutes = words.inMinutes {
            guard due.hasTime else { return differs("which has no time") }
            let expected = now.addingTimeInterval(Double(minutes) * 60)
            if abs(dueDate.timeIntervalSince(expected)) > 5 * 60 {
                return differs("which is not \(minutes) minutes from now")
            }
            return nil
        }
        if words.hasUnreadTime { return nil }

        guard let clock = words.clock else {
            guard let hour = due.hour else { return nil }
            let time = String(format: "%02d:%02d", hour, due.minute ?? 0)
            let partOfDay = words.partOfDay != nil
            return ReminderClarification(
                kind: .noTimeSaid,
                problem: partOfDay
                    ? "the user said \(quoted) without a clock time, but the request says \(time)"
                    : "the user didn't say a time (\(quoted)), but the request says \(time)",
                question: timeRequired
                    ? "what time they mean"
                    : "what time they want, or whether a reminder for the day without a time is fine")
        }

        guard let dueHour = due.hour else { return differs("which has no time") }
        var hours: [Int]
        switch clock.meridiem ?? words.partOfDay {
        case .am: hours = [clock.hour == 12 ? 0 : clock.hour]
        case .pm: hours = [clock.hour < 12 ? clock.hour + 12 : clock.hour]
        case nil: hours = (1...11).contains(clock.hour) ? [clock.hour, clock.hour + 12] : [clock.hour]
        }
        // On the day itself, a time already gone is not what they meant ("at 7" said at 10:00).
        if calendar.isDate(dueDate, inSameDayAs: now) {
            let open = hours.filter { hour in
                guard let candidate = calendar.date(bySettingHour: hour, minute: clock.minute, second: 0, of: dueDate) else { return true }
                return candidate > now
            }
            if !open.isEmpty { hours = open }
        }
        let said = clock.text
        guard hours.contains(dueHour), (due.minute ?? 0) == clock.minute else {
            return differs("which is not \(said)")
        }
        if hours.count == 2 {
            let morning = String(format: "%02d:%02d", hours[0], clock.minute)
            let evening = String(format: "%02d:%02d", hours[1], clock.minute)
            return ReminderClarification(
                kind: .ambiguousTime,
                problem: "\(quoted) can mean \(morning) or \(evening)",
                question: "whether they mean \(morning) or \(evening)")
        }
        return nil
    }

    // MARK: Dates for the agent

    private static func describe(_ due: ReminderDue, calendar: Calendar, now: Date) -> String {
        guard let date = due.date else { return due.localText }
        let day = describe(day: date, calendar: calendar, now: now)
        guard let hour = due.hour else { return "\(day), no time" }
        return day + String(format: " %02d:%02d", hour, due.minute ?? 0)
    }

    /// "Friday 16 October", with the year when it isn't this year.
    private static func describe(day: Date, calendar: Calendar, now: Date) -> String {
        let parts = calendar.dateComponents([.weekday, .day, .month, .year], from: day)
        let month = englishMonths[(parts.month ?? 1) - 1].capitalized
        var text = "\(weekdayName(parts.weekday ?? 1)) \(parts.day ?? 0) \(month)"
        if parts.year != calendar.component(.year, from: now) { text += " \(parts.year ?? 0)" }
        return text
    }

    /// The first day after `day` that falls on `weekday` (1 = Sunday … 7 = Saturday).
    private static func nextDate(weekday: Int, after day: Date, calendar: Calendar) -> Date {
        var date = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        while calendar.component(.weekday, from: date) != weekday {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    private static func weekdayName(_ weekday: Int) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][(weekday - 1 + 7) % 7]
    }

    // MARK: Word lists (folded: lowercase, no diacritics, ł → l)

    /// Weekday words → Calendar weekday (1 = Sunday). Polish forms are listed in full, not as
    /// prefixes: "piątej" (five o'clock) and "czwartej" (four) must not read as Friday or Thursday.
    static let weekdays: [String: Int] = {
        let groups: [(Int, [String])] = [
            (1, ["sunday", "niedziela", "niedziele", "niedzieli"]),
            (2, ["monday", "poniedzialek", "poniedzialku", "poniedzialkiem"]),
            (3, ["tuesday", "wtorek", "wtorku", "wtorkiem"]),
            (4, ["wednesday", "sroda", "srode", "srody", "srodzie"]),
            (5, ["thursday", "czwartek", "czwartku", "czwartkiem"]),
            (6, ["friday", "piatek", "piatku", "piatkiem"]),
            (7, ["saturday", "sobota", "sobote", "soboty", "sobocie"]),
        ]
        var map: [String: Int] = [:]
        for (day, names) in groups { for name in names { map[name] = day } }
        return map
    }()

    static let englishMonths = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
    ]

    /// Month words → 1…12: English, and Polish nominative and genitive ("październik", "października").
    static let months: [String: Int] = {
        let polish = [
            ["styczen", "stycznia"], ["luty", "lutego"], ["marzec", "marca"], ["kwiecien", "kwietnia"],
            ["maj", "maja"], ["czerwiec", "czerwca"], ["lipiec", "lipca"], ["sierpien", "sierpnia"],
            ["wrzesien", "wrzesnia"], ["pazdziernik", "pazdziernika"], ["listopad", "listopada"], ["grudzien", "grudnia"],
        ]
        var map: [String: Int] = [:]
        for (index, name) in englishMonths.enumerated() { map[name] = index + 1 }
        for (index, names) in polish.enumerated() { for name in names { map[name] = index + 1 } }
        return map
    }()

    /// Polish hour ordinals ("o siódmej" = at seven).
    static let polishHours: [String: Int] = [
        "pierwszej": 1, "drugiej": 2, "trzeciej": 3, "czwartej": 4, "piatej": 5, "szostej": 6,
        "siodmej": 7, "osmej": 8, "dziewiatej": 9, "dziesiatej": 10, "jedenastej": 11, "dwunastej": 12,
        "trzynastej": 13, "czternastej": 14, "pietnastej": 15, "szesnastej": 16, "siedemnastej": 17,
        "osiemnastej": 18, "dziewietnastej": 19, "dwudziestej": 20,
    ]

    static let englishHours: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    ]

    enum Meridiem { case am, pm }

    struct Clock {
        let hour: Int
        let minute: Int
        /// Known from "am"/"pm", from 24-hour form ("19:00", "07:30") or from an hour above 12.
        let meridiem: Meridiem?
        let text: String
    }

    struct DayAndMonth {
        let day: Int
        let month: Int
        var text: String { "\(day) \(englishMonths[month - 1].capitalized)" }
    }

    /// The folded words of what the user said, and what they say about days and times.
    struct Words {
        let text: String
        let tokens: [String]

        init(_ said: String) {
            // Fold like search, but keep ":" and "." so "9:30" and "a.m." survive.
            text = SearchFolding.fold(said)
            tokens = SearchFolding.tokens(folded: text)
        }

        func has(_ words: String...) -> Bool { words.contains(where: tokens.contains) }

        func has(phrase: String) -> Bool {
            let parts = phrase.split(separator: " ").map(String.init)
            guard parts.count <= tokens.count else { return false }
            return (0...(tokens.count - parts.count)).contains { Array(tokens[$0..<($0 + parts.count)]) == parts }
        }

        /// "next Friday", "w przyszły piątek", "w następną sobotę".
        func saysNext(beforeWeekday: Bool) -> Bool {
            let next: Set = ["next", "przyszly", "przyszla", "przyszlej", "przyszle", "nastepny", "nastepna", "nastepnej", "nastepne"]
            return tokens.indices.dropLast().contains { next.contains(tokens[$0]) && SaidTime.weekdays[tokens[$0 + 1]] != nil }
        }

        var saysNextWeek: Bool {
            has(phrase: "next week") || has(phrase: "przyszlym tygodniu") || has(phrase: "przyszly tydzien")
                || has(phrase: "nastepnym tygodniu") || has(phrase: "nastepny tydzien")
        }

        /// Day numbers said as days: "the 16th", "16 October", "piątek 16".
        var dayNumbers: Set<Int> {
            var days = Set<Int>()
            for match in matches(#"\b(\d{1,2})(?:st|nd|rd|th)\b"#) { days.insert(match[1]) }
            if let date = dayAndMonth { days.insert(date.day) }
            // A bare number right after a weekday ("piątek 16", "Friday 16").
            let clockWords: Set = ["am", "pm", "a", "p", "oclock", "clock", "rano", "wieczorem"]
            for index in tokens.indices.dropLast() where SaidTime.weekdays[tokens[index]] != nil {
                guard let number = Int(tokens[index + 1]), (1...31).contains(number) else { continue }
                if index + 2 < tokens.count, clockWords.contains(tokens[index + 2]) { continue }
                days.insert(number)
            }
            return days
        }

        var dayAndMonth: DayAndMonth? {
            for index in tokens.indices {
                guard let month = SaidTime.months[tokens[index]] else { continue }
                // "16 October", "October 16", "16th of October".
                var around = [index - 1, index + 1]
                if index >= 2, tokens[index - 1] == "of" { around.append(index - 2) }
                for other in around where tokens.indices.contains(other) {
                    let token = tokens[other].replacingOccurrences(of: #"(st|nd|rd|th)$"#, with: "", options: .regularExpression)
                    // "may" is also a verb: only a month next to a day number counts.
                    if let day = Int(token), (1...31).contains(day) { return DayAndMonth(day: day, month: month) }
                }
            }
            return nil
        }

        /// Morning or evening words, which settle "at 7".
        var partOfDay: Meridiem? {
            if has("morning", "rano", "rankiem", "rana") || has(phrase: "przed poludniem") { return .am }
            if has("afternoon", "evening", "tonight", "wieczorem", "wieczor", "wieczora") || has(phrase: "po poludniu") { return .pm }
            return nil
        }

        /// "in 2 hours", "in 30 minutes", "in an hour", "za 2 godziny", "za pół godziny".
        var inMinutes: Int? {
            if has(phrase: "half an hour") || has(phrase: "pol godziny") { return 30 }
            if has(phrase: "in an hour") || has(phrase: "za godzine") { return 60 }
            for match in matchStrings(#"\b(?:in|za)\s+(\d{1,3})\s*(minutes?|mins?|minut\w*|hours?|godzin\w*)\b"#) {
                guard let amount = Int(match[1]) else { continue }
                return match[2].hasPrefix("h") || match[2].hasPrefix("godzin") ? amount * 60 : amount
            }
            return nil
        }

        /// Clock words these rules don't read ("half past seven", "kwadrans po", "wpół do ósmej").
        var hasUnreadTime: Bool {
            has(phrase: "half past") || has("quarter", "wpol", "kwadrans")
        }

        /// The first clock time said, if any.
        var clock: Clock? {
            // "19:30", "9:30", "9.30 pm"
            for m in matchStrings(#"\b(\d{1,2})[:.](\d{2})\s*(am|pm|a\.m\.|p\.m\.)?"#) {
                guard let hour = Int(m[1]), let minute = Int(m[2]), hour <= 23, minute <= 59 else { continue }
                // "16.10" is a date in Polish: a dot counts only with a clock word before it.
                if m[0].contains("."), m[3].isEmpty, !text.contains("o \(m[0])"), !text.contains("at \(m[0])") { continue }
                return Clock(hour: hour, minute: minute, meridiem: meridiem(m[3], hour: hour, twoDigit: m[1].count == 2 && hour < 10, colon: true),
                             text: m[0].trimmingCharacters(in: .whitespaces))
            }
            // "7pm", "7 a.m."
            for m in matchStrings(#"\b(\d{1,2})\s*(am|pm|a\.m\.|p\.m\.)"#) {
                guard let hour = Int(m[1]), (1...12).contains(hour) else { continue }
                return Clock(hour: hour, minute: 0, meridiem: meridiem(m[2], hour: hour, twoDigit: false), text: m[0])
            }
            // "at 7", "o 19", "godz. 9" (not "od 16 października": a number before a month is a day)
            let month = SaidTime.months.keys.joined(separator: "|")
            for m in matchStrings(#"\b(?:at|o|godz\w*|godzinie|godzina|by|from|od|around|okolo)\.?\s+(\d{1,2})\b(?![:.]\d)(?!(?:st|nd|rd|th)?\s+(?:of\s+)?(?:"# + month + #")\b)"#) {
                guard let hour = Int(m[1]), hour <= 23 else { continue }
                return Clock(hour: hour, minute: 0, meridiem: meridiem("", hour: hour, twoDigit: m[1].count == 2 && hour < 10),
                             text: m[0])
            }
            // "seven o'clock", "seven pm"
            for m in matchStrings(#"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*(o.?clock|am|pm|a\.m\.|p\.m\.)"#) {
                guard let hour = SaidTime.englishHours[m[1]] else { continue }
                return Clock(hour: hour, minute: 0, meridiem: meridiem(m[2], hour: hour, twoDigit: false), text: m[0])
            }
            // "o siódmej", "na dziewiątą"… (ordinals after "o"; whole hours only)
            for index in tokens.indices.dropLast() where ["o", "godz", "godzinie", "okolo"].contains(tokens[index]) {
                guard var hour = SaidTime.polishHours[tokens[index + 1]] else { continue }
                if hour == 20, index + 2 < tokens.count, let extra = ["pierwszej": 1, "drugiej": 2, "trzeciej": 3][tokens[index + 2]] {
                    hour += extra
                }
                return Clock(hour: hour, minute: 0, meridiem: hour > 12 ? .pm : nil, text: "\(tokens[index]) \(tokens[index + 1])")
            }
            if has("noon", "midday") || has(phrase: "w poludnie") {
                return Clock(hour: 12, minute: 0, meridiem: .pm, text: "noon")
            }
            if has("midnight", "polnoc", "polnocy") {
                return Clock(hour: 0, minute: 0, meridiem: .am, text: "midnight")
            }
            return nil
        }

        private func meridiem(_ suffix: String, hour: Int, twoDigit: Bool, colon: Bool = false) -> Meridiem? {
            if suffix.hasPrefix("a") { return .am }
            if suffix.hasPrefix("p") { return .pm }
            // 24-hour form: "19:00", "07:30", "o 0". Hours and minutes ("9:30") are read as the
            // 24-hour clock Poland uses; "at 9" alone is the case that needs a question.
            if hour > 12 { return .pm }
            if hour == 0 || twoDigit || (colon && hour < 12) { return .am }
            return nil
        }

        private func matchStrings(_ pattern: String) -> [[String]] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(text.startIndex..., in: text)
            return regex.matches(in: text, range: range).map { match in
                (0..<match.numberOfRanges).map { group in
                    Range(match.range(at: group), in: text).map { String(text[$0]) } ?? ""
                }
            }
        }

        private func matches(_ pattern: String) -> [[Int]] {
            matchStrings(pattern).map { $0.map { Int($0) ?? -1 } }
        }
    }
}
