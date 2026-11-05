import Foundation

// A weight goal said in words ("schudnąć 10 kg w tydzień") meets the owner's rules from ADR-620 and
// the research's rules 3 to 5: a deficit of at most about 500 kcal a day, which is about half a kilo
// a week; no weight loss under BMI 18.5, for the under-18s, or with eating-disorder cues. This is
// code: the pace is worked out and judged here, and the answer has no calorie numbers at all (ADR-620:
// food numbers are off until the person turns counting on and passes its own check).
//
// Platforms: iPhone, iPad, Mac, Watch (DoddyCore, no UI).

public struct WeightGoalRequest: Equatable, Sendable {
    public let kilograms: Double
    public let weeks: Double

    public init?(kilograms: Double, weeks: Double) {
        guard kilograms.isFinite, weeks.isFinite, kilograms > 0, weeks > 0 else { return nil }
        self.kilograms = kilograms
        self.weeks = weeks
    }

    public var kilogramsPerWeek: Double { kilograms / weeks }

    /// "schudnąć 10 kg w tydzień", "lose 5 kilos in 2 months", "zrzucić 3 kg w 6 tygodni". A period with
    /// no number ("w tydzień", "in a month") is one. Nil when the text has no amount in kilos or no period.
    public static func parse(_ text: String) -> WeightGoalRequest? {
        let folded = SearchFolding.fold(text)
        guard let amount = firstMatch(#"(\d+(?:[.,]\d+)?)\s*(?:kg|kilogram\w*|kilos?\b|kilo\w*)"#, in: folded),
              let kilograms = number(amount.groups[0]) else { return nil }
        let rest = String(folded[amount.range.upperBound...])
        let unit = #"(tydzien|tygodni\w*|tygodn\w*|tyg\b|week\w*|miesiac\w*|miesiec\w*|month\w*|dzien|dni\b|day\w*)"#
        guard let period = firstMatch(#"(?:(\d+(?:[.,]\d+)?)\s*)?"# + unit, in: rest) else { return nil }
        let count = period.groups[0].isEmpty ? 1 : (number(period.groups[0]) ?? 1)
        let unitText = period.groups[1]
        let weeksPerUnit: Double
        if unitText.hasPrefix("tyd") || unitText.hasPrefix("tyg") || unitText.hasPrefix("week") {
            weeksPerUnit = 1
        } else if unitText.hasPrefix("mies") || unitText.hasPrefix("month") {
            weeksPerUnit = 4.345
        } else {
            weeksPerUnit = 1.0 / 7.0
        }
        return WeightGoalRequest(kilograms: kilograms, weeks: count * weeksPerUnit)
    }

    private static func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }

    private static func firstMatch(_ pattern: String, in text: String) -> (range: Range<String.Index>, groups: [String])? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let groups = (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
        return (range, groups)
    }
}

public enum WeightGoalAdvice: Equatable, Sendable {
    /// A pace the owner's rules allow: at most about half a kilo a week.
    case fine(kilogramsPerWeek: Double)
    /// Too fast. `saferWeeks` is how long the same loss takes at the safe pace.
    case tooFast(kilogramsPerWeek: Double, saferWeeks: Int)
    /// No weight-loss target at all, for a reason that is not about speed.
    case notAdvisable(WeightGoalRefusal)
}

public enum WeightGoalRefusal: Equatable, Sendable {
    /// BMI under 18.5.
    case underweight
    /// Under 18.
    case minor
    /// Eating-disorder cues or pregnancy (from `TriageOutcome`).
    case sensitive
}

public enum WeightGoalGuard {
    /// About 500 kcal a day, as ADR-620 puts it, is about half a kilo of body fat a week.
    public static let maxKilogramsPerWeek = 0.5
    public static let minimumBMI = 18.5

    public static func assess(_ request: WeightGoalRequest, bmi: Double? = nil, age: Int? = nil,
                              triage: TriageOutcome = .clear) -> WeightGoalAdvice {
        if !triage.numbersAllowed { return .notAdvisable(.sensitive) }
        if let age, age < 18 { return .notAdvisable(.minor) }
        if let bmi, bmi < minimumBMI { return .notAdvisable(.underweight) }
        let pace = request.kilogramsPerWeek
        if pace > maxKilogramsPerWeek + 1e-9 {
            return .tooFast(kilogramsPerWeek: pace, saferWeeks: Int((request.kilograms / maxKilogramsPerWeek).rounded(.up)))
        }
        return .fine(kilogramsPerWeek: pace)
    }

    /// The answer's words. No calorie, deficit or macro number appears in any of them.
    public static func message(_ advice: WeightGoalAdvice, language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch advice {
        case .fine:
            return polish
                ? "To tempo mieści się w tym, co uznaje się za rozsądne. Ruch pomoże, ale o odchudzaniu rozmawiaj też z lekarzem lub dietetykiem."
                : "That pace is within what is considered reasonable. Exercise helps, but talk to a doctor or dietitian about losing weight too."
        case .tooFast(let pace, let weeks):
            let rate = format(pace, polish: polish)
            return polish
                ? "\(rate) kg na tydzień to za szybko i nie będę układać planu pod taki cel. Rozsądne jest do około 0,5 kg na tydzień, więc ta sama zmiana zajmie około \(weeks) tygodni. Mogę ułożyć plan ruchu na dłuższy czas. Jestem AI, nie lekarzem ani dietetykiem."
                : "\(rate) kg a week is too fast and I won't build a plan around that goal. Up to about 0.5 kg a week is reasonable, so the same change takes about \(weeks) weeks. I can make a movement plan for the longer time. I'm an AI, not a doctor or a dietitian."
        case .notAdvisable(.underweight):
            return polish
                ? "Przy Twojej wadze nie ustawiam żadnego celu odchudzania. Jeśli chcesz, mogę pomóc w planie ruchu bez celu wagi; o wadze porozmawiaj z lekarzem."
                : "At your weight I don't set any weight-loss goal. If you like, I can help with a movement plan with no weight goal; talk to a doctor about weight."
        case .notAdvisable(.minor):
            return polish
                ? "Przed 18. rokiem życia nie ustawiam celów odchudzania. Mogę pomóc w planie ruchu; o wadze porozmawiaj z lekarzem."
                : "Under 18 I don't set weight-loss goals. I can help with a movement plan; talk to a doctor about weight."
        case .notAdvisable(.sensitive):
            return polish
                ? "Nie podaję celów wagi ani kalorii. Jeśli chcesz, porozmawiaj o tym z lekarzem lub psychologiem; mogę pomóc w planie ruchu bez celu wagi."
                : "I don't give weight or calorie targets. If you like, talk to a doctor or a psychologist; I can help with a movement plan with no weight goal."
        }
    }

    private static func format(_ value: Double, polish: Bool) -> String {
        let rounded = value >= 10 ? value.rounded() : (value * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return polish ? text.replacingOccurrences(of: ".", with: ",") : text
    }
}
