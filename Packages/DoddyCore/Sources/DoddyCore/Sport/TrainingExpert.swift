import Foundation

// The training mode's decisions, in the order the research gives them (section 2.2) and the owner's
// rules require (ADR-620, ADR-642): safety first, then a goal about weight, then only the questions
// still missing, then the plan from `PlanEngine`. All of it is code. A model may later put the answer
// into friendlier words; it cannot change a stop message, a refusal, a pace or a number of a plan.
// Nothing here is saved, sent or written anywhere: the result is a value, and `verifiedExternalAction`
// stays false.
//
// Platforms: iPhone, iPad, Mac, Watch (DoddyCore, no UI).

public struct TrainingTurn: Sendable {
    /// What the person just said or typed.
    public var text: String
    /// What is already known from earlier turns.
    public var answers: TrainingAnswers
    public var language: NotificationLanguage
    /// The person said yes to Doddy reading Apple Health (HealthKit). Without it, nothing from Health is
    /// used; everything works from what the person says (research acceptance test 11).
    public var healthConsent: Bool
    /// The longest run of the last 30 days according to Apple Health, if it was read. Used only with consent.
    public var healthLongestRunMinutes: Int?
    public var bmi: Double?

    public init(text: String, answers: TrainingAnswers = TrainingAnswers(), language: NotificationLanguage = .polish,
                healthConsent: Bool = false, healthLongestRunMinutes: Int? = nil, bmi: Double? = nil) {
        self.text = text
        self.answers = answers
        self.language = language
        self.healthConsent = healthConsent
        self.healthLongestRunMinutes = healthLongestRunMinutes
        self.bmi = bmi
    }
}

public struct TrainingReply: Equatable, Sendable {
    public let result: ExpertResult
    public let plan: TrainingPlan?
    public let triage: TriageOutcome
    public let questions: [TrainingQuestion]
    /// What the person has now told, for the next turn.
    public let answers: TrainingAnswers
    /// True only when Apple Health's number filled in a gap and the person had said yes to reading it.
    public let healthDataUsed: Bool
}

public enum TrainingExpert {
    public static func respond(_ turn: TrainingTurn) -> TrainingReply {
        let polish = turn.language == .polish
        let triage = TrainingTriage.assess(turn.text)
        var answers = TrainingInterview.extract(from: turn.text, into: turn.answers)

        // 1. Safety first. A flag is a fixed text and no plan; no later step can soften it.
        if let message = triage.message(turn.language), !triage.planAllowed || triage.flags.contains(.eatingDisorderCue) {
            let result = ExpertResult(
                mode: .personalTraining, answer: message, sources: [.who2020], caveats: [disclosure(polish)],
                riskLevel: triage.risk)
            return reply(result, nil, triage, [], answers, false)
        }

        // 2. A weight goal in the words: the owner's pace rule, with no calorie number in the answer.
        var caveats = [disclosure(polish)]
        if let goal = WeightGoalRequest.parse(turn.text) {
            let advice = WeightGoalGuard.assess(goal, bmi: turn.bmi, age: answers.screening?.age, triage: triage)
            switch advice {
            case .fine:
                caveats.append(WeightGoalGuard.message(advice, language: turn.language))
            case .tooFast, .notAdvisable:
                let questions = remainingQuestions(answers)
                let result = ExpertResult(
                    mode: .personalTraining, answer: WeightGoalGuard.message(advice, language: turn.language),
                    missingData: questions.map(\.rawValue), sources: [.who2020], caveats: caveats, riskLevel: .moderate)
                return reply(result, nil, triage, questions, answers, false)
            }
        }

        // 3. Apple Health fills a gap only with the person's yes; otherwise the words are all there is.
        var healthUsed = false
        if turn.healthConsent, answers.longestRecentRunMinutes == nil, let minutes = turn.healthLongestRunMinutes, minutes > 0 {
            answers.longestRecentRunMinutes = minutes
            healthUsed = true
            caveats.append(polish ? "Na podstawie Twoich ostatnich biegów z Apple Health." : "Based on your recent runs in Apple Health.")
        }

        // 4. Ask only what is missing, then the engine.
        switch TrainingInterview.next(answers) {
        case .ask(let questions):
            let intro = polish ? "Żeby ułożyć plan, potrzebuję jeszcze tego:" : "To make a plan I still need this:"
            let text = ([intro] + questions.map { TrainingInterview.prompt($0, language: turn.language) }).joined(separator: "\n")
            let result = ExpertResult(
                mode: .personalTraining, answer: text, missingData: questions.map(\.rawValue), caveats: caveats, riskLevel: .low)
            return reply(result, nil, triage, questions, answers, healthUsed)
        case .ready(let request):
            switch PlanEngine.make(request) {
            case .plan(let plan):
                let result = ExpertResult(
                    mode: .personalTraining, answer: summary(plan, polish: polish),
                    proposedActions: [ExpertProposedAction(
                        kind: "keep_plan", summary: polish ? "Zachowaj ten plan na tym iPhonie." : "Keep this plan on this iPhone.")],
                    sources: sources(for: plan), caveats: caveats + [baseline(polish)], riskLevel: .low)
                return reply(result, plan, triage, [], answers, healthUsed)
            case .refused(let refusal):
                let (text, risk) = refusalText(refusal, polish: polish)
                let result = ExpertResult(
                    mode: .personalTraining, answer: text, sources: [.who2020], caveats: caveats, riskLevel: risk)
                return reply(result, nil, triage, [], answers, healthUsed)
            }
        }
    }

    // MARK: Pieces

    private static func reply(_ result: ExpertResult, _ plan: TrainingPlan?, _ triage: TriageOutcome, _ questions: [TrainingQuestion],
                              _ answers: TrainingAnswers, _ healthUsed: Bool) -> TrainingReply {
        TrainingReply(result: result, plan: plan, triage: triage, questions: questions, answers: answers, healthDataUsed: healthUsed)
    }

    private static func remainingQuestions(_ answers: TrainingAnswers) -> [TrainingQuestion] {
        if case .ask(let questions) = TrainingInterview.next(answers) { return questions }
        return []
    }

    static func disclosure(_ polish: Bool) -> String {
        polish ? "Jestem AI, nie trenerem z certyfikatem, fizjoterapeutą ani lekarzem."
               : "I'm an AI, not a certified trainer, a physiotherapist or a doctor."
    }

    /// WHO's weekly figures are a target for a population, not a duty from Monday (research section 2.2 step 3).
    private static func baseline(_ polish: Bool) -> String {
        polish ? "WHO zaleca dorosłym 150–300 min umiarkowanej aktywności tygodniowo i ćwiczenia siłowe co najmniej 2 razy w tygodniu; to cel dla populacji, nie obowiązek od poniedziałku."
               : "WHO advises adults 150–300 minutes of moderate activity a week and strength work at least 2 days a week; that is a goal for a population, not a duty from Monday."
    }

    private static func sources(for plan: TrainingPlan) -> [ExpertSource] {
        plan.request.goal.isRunning ? [.who2020, .frandsen2025] : [.who2020, .acsm2026]
    }

    private static func summary(_ plan: TrainingPlan, polish: Bool) -> String {
        let sessions = plan.weeks.first?.sessions.count ?? 0
        let weeks = plan.weeks.count
        if plan.request.goal.isRunning {
            return polish
                ? "Plan na \(weeks) tyg.: \(sessions) bieg\(sessions == 1 ? "" : sessions < 5 ? "i" : "ów") w tygodniu. Biegnij tak, żebyś mógł mówić pełnymi zdaniami, i zacznij od tygodnia 1."
                : "A \(weeks)-week plan: \(sessions) run\(sessions == 1 ? "" : "s") a week. Run so you could speak in full sentences, and start with week 1."
        }
        return polish
            ? "Plan na \(weeks) tyg.: \(sessions) \(sessions < 5 ? "sesje" : "sesji") siłowe w tygodniu. Każdą serię kończ z 2 powtórzeniami w zapasie i zacznij od tygodnia 1."
            : "A \(weeks)-week plan: \(sessions) strength sessions a week. Stop each set with 2 reps left, and start with week 1."
    }

    private static func refusalText(_ refusal: PlanRefusal, polish: Bool) -> (String, RiskLevel) {
        switch refusal {
        case .seeDoctorFirst:
            return (polish ? "Przy chorobie serca, płuc, nerek lub cukrzycy, objawach albo zaleceniu lekarza najpierw porozmawiaj z lekarzem; wtedy układam plan."
                           : "With a heart, lung or kidney condition, diabetes, symptoms or a doctor's limit, talk to a doctor first; then I make a plan.", .high)
        case .pregnancy: return (TrainingTriage.fixedMessage(for: .pregnancy, language: polish ? .polish : .english), .moderate)
        case .injury: return (TrainingTriage.fixedMessage(for: .sharpInjury, language: polish ? .polish : .english), .high)
        case .tooYoung:
            return (polish ? "Przed 16. rokiem życia ćwicz z rodzicem, nauczycielem WF lub trenerem, nie z planu z aplikacji."
                           : "Under 16, train with a parent, a PE teacher or a coach, not from an app's plan.", .moderate)
        case .needsMoreTime(let minutes):
            return (polish ? "Ten plan potrzebuje co najmniej \(minutes) minut na sesję."
                           : "This plan needs at least \(minutes) minutes a session.", .low)
        case .needsMoreDays(let days):
            return (polish ? "Do planu potrzebuję co najmniej \(days) dni w tygodniu." : "I need at least \(days) days a week for a plan.", .low)
        case .notReadyFor(_, let suggested):
            return (polish ? "Ten cel to za duży krok od teraz. Zacznij od mniejszego (\(name(suggested, polish: true)))."
                           : "That goal is too big a step from here. Start with a smaller one (\(name(suggested, polish: false))).", .low)
        }
    }

    private static func name(_ goal: PlanGoal, polish: Bool) -> String {
        switch goal {
        case .firstFiveK: polish ? "pierwsze 5 km" : "a first 5 km"
        case .tenK: polish ? "10 km" : "10 km"
        case .halfMarathon: polish ? "półmaraton" : "a half marathon"
        case .strengthHome: polish ? "siła w domu" : "strength at home"
        case .strengthGym: polish ? "siła na siłowni" : "strength in the gym"
        }
    }
}
