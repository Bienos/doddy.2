import Foundation

// The minimum interview before a plan (research section 2.2 step 1: "ask for what is missing, not a
// full questionnaire for an ordinary question"). What the person already said is taken from their
// words; what is still missing is asked, grouped, and never more than five questions in all. The
// five safety questions and age are ONE question and are never assumed: nothing is pre-set (ADR-625),
// so a plan never starts from an answer the person did not give.
//
// Platforms: iPhone, iPad, Mac, Watch (DoddyCore, no UI).

/// What the person has said so far. Every answer is optional until given.
public struct TrainingAnswers: Equatable, Sendable, Codable {
    public var goal: PlanGoal?
    public var level: PlanLevel?
    public var daysPerWeek: Int?
    public var minutesPerSession: Int?
    /// The longest run of the last 30 days in minutes, if known. Never required.
    public var longestRecentRunMinutes: Int?
    /// The five safety questions and age, answered together; nil until the person has answered them.
    public var screening: PlanScreening?

    public init(goal: PlanGoal? = nil, level: PlanLevel? = nil, daysPerWeek: Int? = nil, minutesPerSession: Int? = nil,
                longestRecentRunMinutes: Int? = nil, screening: PlanScreening? = nil) {
        self.goal = goal
        self.level = level
        self.daysPerWeek = daysPerWeek
        self.minutesPerSession = minutesPerSession
        self.longestRecentRunMinutes = longestRecentRunMinutes
        self.screening = screening
    }
}

public enum TrainingQuestion: String, CaseIterable, Codable, Sendable {
    case goal, level, daysPerWeek, minutesPerSession, screening
}

public enum InterviewStep: Equatable, Sendable {
    /// Ask these, in this order, and nothing else.
    case ask([TrainingQuestion])
    /// Everything the engine needs is there.
    case ready(PlanRequest)
}

public enum TrainingInterview {
    /// At most five questions in the whole interview, the screening counted as one.
    public static let maxQuestions = TrainingQuestion.allCases.count

    public static func next(_ answers: TrainingAnswers) -> InterviewStep {
        var missing: [TrainingQuestion] = []
        if answers.goal == nil { missing.append(.goal) }
        if answers.level == nil { missing.append(.level) }
        if answers.daysPerWeek == nil { missing.append(.daysPerWeek) }
        if answers.minutesPerSession == nil { missing.append(.minutesPerSession) }
        if answers.screening == nil { missing.append(.screening) }
        if missing.isEmpty, let goal = answers.goal, let level = answers.level, let days = answers.daysPerWeek,
           let minutes = answers.minutesPerSession, let screening = answers.screening {
            return .ready(PlanRequest(goal: goal, level: level, daysPerWeek: days, minutesPerSession: minutes,
                                      longestRecentRunMinutes: answers.longestRecentRunMinutes, screening: screening))
        }
        return .ask(missing)
    }

    /// What the words of `text` already answer, added to `answers` without overwriting anything the
    /// person gave before. Understands the plain ways people say it in Polish and English: "3 dni",
    /// "trzy razy w tygodniu", "45 minut", "10 km", "półmaraton", "siłownia". It never invents a level
    /// ("trenuję" alone says nothing about how much) and never touches the screening.
    public static func extract(from text: String, into answers: TrainingAnswers = TrainingAnswers()) -> TrainingAnswers {
        var result = answers
        let folded = SearchFolding.fold(text)
        let tokens = SearchFolding.tokens(folded: folded)

        if result.daysPerWeek == nil { result.daysPerWeek = days(in: folded, tokens: tokens) }
        if result.minutesPerSession == nil { result.minutesPerSession = minutes(in: folded) }
        if result.goal == nil { result.goal = goal(in: folded, tokens: tokens) }
        if result.level == nil { result.level = level(in: folded) }
        return result
    }

    private static let numberWords: [String: Int] = [
        "dwa": 2, "dwie": 2, "dwoch": 2, "trzy": 3, "trzech": 3, "cztery": 4, "czterech": 4, "piec": 5, "pieciu": 5,
        "two": 2, "three": 3, "four": 4, "five": 5,
    ]

    /// "3 dni", "trzy razy w tygodniu", "3x", "three days a week". Only 2 to 7 count as days.
    private static func days(in folded: String, tokens: [String]) -> Int? {
        for (index, token) in tokens.enumerated() where index + 1 < tokens.count {
            let next = tokens[index + 1]
            let isDayWord = next.hasPrefix("dni") || next.hasPrefix("dzien") || next.hasPrefix("razy") || next.hasPrefix("raz")
                || next.hasPrefix("day") || next.hasPrefix("time") || next == "x"
            guard isDayWord else { continue }
            let value = Int(token) ?? numberWords[token]
            if let value, (2...7).contains(value) { return value }
        }
        if let match = folded.range(of: #"\b([2-7])\s*x\b"#, options: .regularExpression), let digit = folded[match].first(where: \.isNumber) {
            return digit.wholeNumberValue
        }
        return nil
    }

    /// "45 minut", "45 min", "po 45 minut", "45 minutes". Between 10 and 180.
    private static func minutes(in folded: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{2,3})\s*(?:min\b|minut\w*|minute\w*)"#),
              let match = regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
              let range = Range(match.range(at: 1), in: folded), let value = Int(folded[range]), (10...180).contains(value)
        else { return nil }
        return value
    }

    private static func goal(in folded: String, tokens: [String]) -> PlanGoal? {
        let has = { (words: [String]) in words.contains { folded.contains($0) } }
        if has(["polmaraton", "half marathon", "half-marathon", "21 km", "21km"]) { return .halfMarathon }
        if has(["10 km", "10km", "10k "]) || tokens.contains("10k") { return .tenK }
        if has(["5 km", "5km", "pierwsze 5", "zaczac biegac", "zaczac bieganie", "start running", "start to run", "couch to 5k"])
            || tokens.contains("5k") { return .firstFiveK }
        if has(["silowni"]) || tokens.contains("gym") || tokens.contains("gyms") { return .strengthGym }
        if has(["w domu", "at home", "kalistenik", "bodyweight", "bez sprzetu", "no equipment"])
            && has(["cwicz", "silow", "trening", "workout", "strength", "exercise"]) { return .strengthHome }
        return nil
    }

    private static func level(in folded: String) -> PlanLevel? {
        let has = { (words: [String]) in words.contains { folded.contains($0) } }
        if has(["poczatkuj", "nigdy nie cwicz", "nie trenuje", "od zera", "beginner", "never exercised", "never trained"]) { return .beginner }
        if has(["regularnie", "co tydzien", "kilka razy w tygodniu", "most weeks", "regularly"]) { return .regular }
        if has(["czasami", "od czasu do czasu", "sometimes", "now and then", "occasionally"]) { return .some }
        return nil
    }

    // MARK: The words of each question

    public static func prompt(_ question: TrainingQuestion, language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch question {
        case .goal:
            return polish ? "Jaki masz cel: pierwsze 5 km, 10 km, półmaraton, siła w domu czy na siłowni?"
                          : "What is your goal: a first 5 km, 10 km, a half marathon, strength at home or in the gym?"
        case .level:
            return polish ? "Ile teraz ćwiczysz: wcale, czasami czy większość tygodni?"
                          : "How much do you train now: not at all, now and then, or most weeks?"
        case .daysPerWeek:
            return polish ? "Ile dni w tygodniu możesz ćwiczyć?" : "How many days a week can you train?"
        case .minutesPerSession:
            return polish ? "Ile minut masz na jedną sesję w dni powszednie?" : "How many minutes do you have for a weekday session?"
        case .screening:
            return polish ? "Pięć krótkich pytań o zdrowie (tak lub nie) i wiek: choroba serca, płuc, nerek albo cukrzyca; ból w klatce, omdlenia, zawroty, nietypowa duszność, kołatanie; zalecenie lekarza, by ograniczyć wysiłek; ciąża lub poród; uraz albo ból."
                          : "Five short health questions (yes or no) and your age: a heart, lung, kidney condition or diabetes; chest pain, fainting, dizziness, unusual breathlessness, palpitations; a doctor's advice to limit exercise; pregnancy or a recent birth; an injury or pain."
        }
    }
}
