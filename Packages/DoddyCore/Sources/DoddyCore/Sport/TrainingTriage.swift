import Foundation

// Triage of what the person writes or says (ADR-632; research_sport_mode.md "Rules to enforce in code"
// 1, 4, 5 and 6; ADR-623's named gap: "a fixed, code-enforced reply for red-flag words is not built").
// This is code, not a prompt: a red flag gets one fixed message, in Polish or English, that no model
// output can change, and no plan above light intensity. It is a safety net with a deliberately wide
// mesh, never a diagnosis: it can only add a stop. Not finding a flag never means "all clear", the
// screening questions of `PlanScreening` are still asked before any plan.
//
// Platforms: iPhone, iPad, Mac, Watch (DoddyCore, no UI).

public enum TriageFlag: String, Codable, CaseIterable, Sendable {
    // Stop now, and 112 if it does not pass (research rule 1).
    case chestPain, jawOrRadiatingPain, fainting, dizziness, unexplainedBreathlessness, palpitations, neurologicalSigns
    /// A sharp or sudden injury or pain: no plan, no guess at the cause, a physiotherapist or doctor (rule 6).
    case sharpInjury
    /// Pregnant or recently gave birth: general advice only, ask a doctor or midwife (rule 5).
    case pregnancy
    /// Eating-disorder cues: no calorie or weight targets at all (rule 4, ADR-620).
    case eatingDisorderCue

    public static let emergency: Set<TriageFlag> = [
        .chestPain, .jawOrRadiatingPain, .fainting, .dizziness, .unexplainedBreathlessness, .palpitations, .neurologicalSigns,
    ]
}

public struct TriageOutcome: Equatable, Sendable {
    public let flags: Set<TriageFlag>

    public init(flags: Set<TriageFlag>) { self.flags = flags }

    public static let clear = TriageOutcome(flags: [])

    /// Stop exercising now.
    public var stopNow: Bool { !flags.isDisjoint(with: TriageFlag.emergency) }

    /// No plan is offered after a stop, an injury or a pregnancy; the message says who to ask.
    public var planAllowed: Bool { !stopNow && !flags.contains(.sharpInjury) && !flags.contains(.pregnancy) }

    /// No calorie, weight or deficit target in the answer when any flag is on (research rules 3 to 5).
    public var numbersAllowed: Bool { flags.isEmpty }

    public var risk: RiskLevel {
        if stopNow { return .emergency }
        if flags.contains(.sharpInjury) || flags.contains(.eatingDisorderCue) { return .high }
        if flags.contains(.pregnancy) { return .moderate }
        return .low
    }

    public var humorAllowed: Bool { risk.humorAllowed }

    /// The flag whose message is shown, most serious first.
    var primary: TriageFlag? {
        if let first = TriageFlag.allCases.first(where: { TriageFlag.emergency.contains($0) && flags.contains($0) }) { return first }
        for flag in [TriageFlag.sharpInjury, .pregnancy, .eatingDisorderCue] where flags.contains(flag) { return flag }
        return nil
    }

    /// The fixed text, or nil when there is no flag.
    public func message(_ language: NotificationLanguage) -> String? {
        guard let primary else { return nil }
        return TrainingTriage.fixedMessage(for: primary, language: language)
    }
}

public enum TrainingTriage {
    // MARK: The fixed texts. Nothing but these strings is ever shown for a flag.

    public static func fixedMessage(for flag: TriageFlag, language: NotificationLanguage) -> String {
        let polish = language == .polish
        if TriageFlag.emergency.contains(flag) { return polish ? stopPL : stopEN }
        switch flag {
        case .sharpInjury: return polish ? injuryPL : injuryEN
        case .pregnancy: return polish ? pregnancyPL : pregnancyEN
        default: return polish ? eatingPL : eatingEN
        }
    }

    public static let stopPL = "Przerwij ćwiczenia teraz i usiądź albo się połóż. Jeśli ból w klatce, omdlenie, zawroty głowy, silna duszność, kołatanie serca lub drętwienie nie mijają albo się nasilają, zadzwoń pod 112. Nie układam planu treningowego, dopóki nie skonsultujesz tego z lekarzem. Jestem AI, nie lekarzem, i niczego nie rozpoznaję."
    public static let stopEN = "Stop exercising now and sit or lie down. If chest pain, fainting, dizziness, strong breathlessness, a racing heart or numbness do not pass or get worse, call 112. I won't make a training plan until you have talked to a doctor. I'm an AI, not a doctor, and I don't diagnose anything."
    public static let injuryPL = "Przy urazie lub nagłym, ostrym bólu nie układam planu i nie zgaduję, co się stało. Najlepiej pokaż to lekarzowi albo fizjoterapeucie. Jestem AI, nie lekarzem, i nie rozpoznaję ani nie leczę urazów."
    public static let injuryEN = "With an injury or sudden, sharp pain I don't make a plan and I don't guess what happened. Please show it to a doctor or a physiotherapist. I'm an AI, not a doctor, and I don't diagnose or treat injuries."
    public static let pregnancyPL = "W ciąży i krótko po porodzie to, jakie ćwiczenia są dla Ciebie dobre, ustalasz z lekarzem lub położną. Mogę najwyżej przypomnieć ogólne zalecenia WHO o regularnym ruchu, ale konkretnego planu nie układam."
    public static let pregnancyEN = "During pregnancy and soon after birth, which exercise suits you is something to settle with your doctor or midwife. At most I can remind you of WHO's general advice about regular movement, but I don't make a specific plan."
    public static let eatingPL = "Nie podaję żadnych celów wagi ani kalorii. Jeśli jedzenie, waga albo ćwiczenia zaczynają Cię przytłaczać lub męczyć poczuciem winy, warto porozmawiać o tym z lekarzem albo psychologiem. Jestem AI i niczego nie rozpoznaję."
    public static let eatingEN = "I don't give any weight or calorie targets. If food, weight or exercise starts to overwhelm you or fill you with guilt, it is worth talking to a doctor or a psychologist. I'm an AI and I don't diagnose anything."

    // MARK: Assessing text

    /// What the words of `text` (Polish or English, any accents) add up to. Words about being sore after
    /// a workout don't count as chest, arm or neck pain unless something sudden or crushing is also said;
    /// a negation within three words ("nie mam bólu w klatce", "no chest pain") cancels a match.
    public static func assess(_ text: String) -> TriageOutcome {
        let tokens = prepare(text)
        guard !tokens.isEmpty else { return .clear }
        var flags: Set<TriageFlag> = []
        let hasAcute = tokens.contains { token in acuteWords.contains { matches(token, $0) } }
        let hasSoreness = tokens.contains { token in sorenessWords.contains { matches(token, $0) } }
        let sorenessOnly = hasSoreness && !hasAcute

        for rule in rules {
            if sorenessOnly, rule.sorenessExempt { continue }
            if rule.matchIndexes(in: tokens).contains(where: { !isNegated(tokens, at: $0) }) {
                flags.insert(rule.flag)
            }
        }
        return TriageOutcome(flags: flags)
    }

    // MARK: Matching

    /// The folded words, with three everyday uses that are not symptoms taken out: "duszno" (stuffy
    /// air), "blood pressure" (a reading, not pressure in the chest).
    static func prepare(_ text: String) -> [String] {
        var words: [String] = []
        for token in SearchFolding.tokens(text) {
            if token == "duszno" { words.append("stuffy"); continue }
            if token == "pressure", words.last == "blood" { words.removeLast(); words.append("bloodpressure"); continue }
            words.append(token)
        }
        return words
    }

    /// A pattern ending in `*` matches any word that starts with it; others must match whole.
    static func matches(_ token: String, _ pattern: String) -> Bool {
        pattern.hasSuffix("*") ? token.hasPrefix(pattern.dropLast()) : token == pattern
    }

    private static let negators: Set<String> = [
        "bez", "nie", "brak", "zadnych", "zadnego", "zadnej", "no", "not", "without", "never", "none", "t",
    ]

    private static func isNegated(_ tokens: [String], at index: Int) -> Bool {
        tokens[max(0, index - 3)..<index].contains { negators.contains($0) }
    }

    /// Words that say something sudden or crushing, which override "just sore".
    private static let acuteWords = [
        "nagle", "nagly", "nagla", "ostry", "ostra", "ostro", "promieniuj*", "ucisk*", "scisk*", "scisn*",
        "zawrot*", "omdl*", "sudden*", "sharp", "radiat*", "crushing", "pressure", "faint*", "dizz*",
    ]
    private static let sorenessWords = ["miesn*", "miesien*", "zakwas*", "doms", "sore*", "muscle*", "stiff*", "sztywn*"]

    struct Rule {
        enum Kind {
            /// The words in this order.
            case phrase([String])
            /// Any one word.
            case word([String])
            /// One word of each list, at most `window` words apart.
            case near([String], [String], window: Int)
        }

        let flag: TriageFlag
        let kind: Kind
        /// The match is ignored when the text only talks about being sore after a workout.
        var sorenessExempt = false

        /// The index of the first word of every match.
        func matchIndexes(in tokens: [String]) -> [Int] {
            switch kind {
            case .word(let patterns):
                return tokens.indices.filter { index in patterns.contains { TrainingTriage.matches(tokens[index], $0) } }
            case .phrase(let words):
                guard !words.isEmpty, tokens.count >= words.count else { return [] }
                return (0...(tokens.count - words.count)).filter { start in
                    words.indices.allSatisfy { TrainingTriage.matches(tokens[start + $0], words[$0]) }
                }
            case .near(let first, let second, let window):
                var found: [Int] = []
                for (i, a) in tokens.enumerated() where first.contains(where: { TrainingTriage.matches(a, $0) }) {
                    let lower = max(0, i - window), upper = min(tokens.count - 1, i + window)
                    for j in lower...upper where j != i && second.contains(where: { TrainingTriage.matches(tokens[j], $0) }) {
                        found.append(min(i, j))
                    }
                }
                return found
            }
        }
    }

    private static let painWords = [
        "bol*", "boli", "bola", "bole", "bolesc*", "ucisk*", "scisk*", "scisn*", "pieka*", "kluje", "kluc*",
        "pain*", "hurt*", "ache*", "aching", "pressure", "tight*", "crushing",
    ]
    private static let chestWords = ["klatc*", "klatk*", "piers*", "mostek", "mostku", "serc*", "sercu", "chest", "sternum", "heart"]

    /// The arm in the forms Polish uses ("ręka", "ręce", "ręką"), after folding, and in English.
    private static let armWords = ["ram*", "reka", "reki", "rece", "reke", "rak", "arm", "arms"]

    static let rules: [Rule] = [
        // Chest pain: the pain word near a chest word.
        Rule(flag: .chestPain, kind: .near(painWords, chestWords, window: 5), sorenessExempt: true),
        // Jaw pain, or pain that spreads to the arm, shoulder, back or jaw.
        Rule(flag: .jawOrRadiatingPain, kind: .near(painWords, ["szczek*", "zuchw*", "jaw"], window: 4)),
        Rule(flag: .jawOrRadiatingPain, kind: .near(["promieniuj*", "radiat*", "spread*"],
                                                    armWords + ["lewej", "lewym", "left", "jaw", "szczek*", "plec*", "bark*", "shoulder"], window: 6)),
        // Arm or neck pain counts only with something sudden or crushing in the same text; muscle soreness doesn't.
        Rule(flag: .jawOrRadiatingPain, kind: .near(["ucisk*", "scisk*", "scisn*", "crushing", "pressure"],
                                                    armWords + ["szyj*", "szyi", "neck"], window: 4)),
        // Fainting.
        Rule(flag: .fainting, kind: .word(["omdl*", "zemdl*", "faint*"])),
        Rule(flag: .fainting, kind: .near(["strac*", "utrat*", "lost", "losing"], ["przytomnosc*", "consciousness"], window: 3)),
        Rule(flag: .fainting, kind: .phrase(["passed", "out"])),
        Rule(flag: .fainting, kind: .phrase(["blacked", "out"])),
        // Dizziness.
        Rule(flag: .dizziness, kind: .word(["zawrot*", "dizz*", "lightheaded", "mroczk*"])),
        Rule(flag: .dizziness, kind: .phrase(["kreci", "mi", "sie", "w", "glowie"])),
        Rule(flag: .dizziness, kind: .phrase(["ciemno", "przed", "oczami"])),
        Rule(flag: .dizziness, kind: .phrase(["light", "headed"])),
        // Breathlessness that is not the ordinary puffing of a run ("zadyszka" does not match).
        Rule(flag: .unexplainedBreathlessness, kind: .word(["duszn*", "dusze", "dusi", "breathless*"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["brak", "tchu"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["brakuje", "mi", "tchu"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["nie", "moge", "zlapac", "tchu"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["nie", "moge", "zlapac", "oddechu"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["nie", "moge", "oddychac"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["short", "of", "breath"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["shortness", "of", "breath"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["can", "t", "breathe"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["cannot", "breathe"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["hard", "to", "breathe"])),
        Rule(flag: .unexplainedBreathlessness, kind: .phrase(["difficulty", "breathing"])),
        // Palpitations.
        Rule(flag: .palpitations, kind: .word(["kolatan*", "palpitation*"])),
        Rule(flag: .palpitations, kind: .phrase(["nieregularne", "bicie", "serca"])),
        Rule(flag: .palpitations, kind: .phrase(["racing", "heart"])),
        Rule(flag: .palpitations, kind: .phrase(["heart", "racing"])),
        Rule(flag: .palpitations, kind: .phrase(["irregular", "heartbeat"])),
        Rule(flag: .palpitations, kind: .phrase(["skipped", "beat*"])),
        // Neurological signs (stroke-like).
        Rule(flag: .neurologicalSigns, kind: .word(["dretw*", "niedowlad*", "belkot*", "slurred*", "numb", "numbness", "droop*", "paraly*"])),
        Rule(flag: .neurologicalSigns, kind: .near(["opada*"], ["kacik*", "twarz*", "powiek*"], window: 3)),
        Rule(flag: .neurologicalSigns, kind: .phrase(["zaburzenia", "mowy"])),
        Rule(flag: .neurologicalSigns, kind: .phrase(["podwojne", "widzenie"])),
        Rule(flag: .neurologicalSigns, kind: .phrase(["double", "vision"])),
        // A sharp or sudden injury or pain.
        Rule(flag: .sharpInjury, kind: .word(["naciagn*", "naderw*", "zerwa*", "zerwi*", "skrec*", "zlaman*", "zwichn*",
                                              "kontuzj*", "uraz*", "sprain*", "strain*", "torn", "tore", "fractur*",
                                              "dislocat*", "injur*", "snapped"])),
        Rule(flag: .sharpInjury, kind: .near(["ostr*", "sharp", "nagly", "nagle", "sudden*"], ["bol*", "boli", "pain*"], window: 2)),
        // Pregnancy and the weeks after birth.
        Rule(flag: .pregnancy, kind: .word(["ciazy", "ciaza", "ciaze", "pregnan*", "postpartum", "porodzie", "polog*", "urodzilam"])),
        Rule(flag: .pregnancy, kind: .phrase(["gave", "birth"])),
        Rule(flag: .pregnancy, kind: .phrase(["had", "a", "baby"])),
        // Eating-disorder cues.
        Rule(flag: .eatingDisorderCue, kind: .word(["anoreks*", "anorex*", "bulimi*", "bulimic*", "glodz*", "glodowk*", "starv*",
                                                    "purg*", "przeczyszcz*", "objadan*", "binge*", "laxative*"])),
        Rule(flag: .eatingDisorderCue, kind: .phrase(["zaburzenia", "odzywiania"])),
        Rule(flag: .eatingDisorderCue, kind: .phrase(["zaburzenia", "jedzenia"])),
        Rule(flag: .eatingDisorderCue, kind: .phrase(["eating", "disorder*"])),
        Rule(flag: .eatingDisorderCue, kind: .near(["wymiotuj*", "wywoluj*", "vomit*", "throw*"],
                                                   ["jedzeni*", "jem", "eating", "food", "meal*"], window: 4)),
    ]
}
