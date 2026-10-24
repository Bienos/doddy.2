import Foundation

// The words of the weekly review (ADR-632). Fixed, in Polish and English, chosen by the priority that
// `TrainingReview` worked out: a model may later say them more warmly, it cannot change which one
// applies or any number in it. The text names one thing to change and never counts missed sessions,
// never praises a streak and never says where the person will end up.
//
// Platforms: iPhone, iPad, Mac, Watch (DoddyCore, no UI).

extension TrainingReview {
    public static func message(_ result: TrainingReviewResult, language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch result.priority {
        case .logFirstSession:
            return polish
                ? "Nie widzę wpisów z ostatnich 2 tygodni, więc nie mam na czym oprzeć zmiany. Po następnym treningu zapisz serie, ciężar i to, ile powtórzeń jeszcze byś zrobił. Do tego czasu zostaw plan bez zmian."
                : "I don't see entries from the last 2 weeks, so I have nothing to base a change on. After your next session, note the sets, the load and how many more reps you could have done. Until then, leave the plan as it is."
        case .stopAndGetChecked:
            return polish
                ? "W zapisie z ostatnich 2 tygodni jest ból, a nie samo zmęczenie. Nic nie podnoszę. Jeśli ból jest ostry, nagły albo nie mija, zobacz się z lekarzem lub fizjoterapeutą. Jeśli to była pomyłka, popraw wpis."
                : "The last 2 weeks of your log include pain, not just tiredness. I'm not raising anything. If the pain is sharp, sudden or doesn't go away, see a doctor or a physiotherapist. If it was a mistake, correct the entry."
        case .easeOff:
            return polish
                ? "Dwa ostatnie treningi były ciężkie. Na następny: te same wartości co ostatnio, bez dokładania ciężaru, powtórzeń ani minut."
                : "Your last two sessions were hard. For the next one: the same as last time, with no added load, reps or minutes."
        case .lighter(let key):
            let name = exerciseName(key, language)
            let easier = ExerciseCatalogue.card(forKey: key)?.easierVersion.map { $0.text(language) }
            return polish
                ? "Na następny trening zmień jedno: lżej w ćwiczeniu «\(name)». W kilku seriach nie udało się dojść do dolnej granicy powtórzeń. Zmniejsz ciężar albo weź łatwiejszą wersję." + (easier.map { " Łatwiejsza wersja: \($0)" } ?? "")
                : "For your next session change one thing: go lighter on “\(name)”. Several sets stopped short of the bottom of the rep range. Reduce the load or take an easier version." + (easier.map { " Easier version: \($0)" } ?? "")
        case .progress(let key, let advice):
            guard let review = result.exercises.first(where: { $0.key == key }) else { return keepText(result, polish) }
            return progressText(key, advice, review, polish: polish, language: language)
        case .keepAsPlanned:
            return keepText(result, polish)
        }
    }

    /// The review as an `ExpertResult`: the words, its source and how careful they are. Nothing is proposed
    /// as an action, because nothing is changed in the plan; the person decides what to do with the advice.
    public static func expertResult(_ result: TrainingReviewResult, language: NotificationLanguage) -> ExpertResult {
        let risk: RiskLevel
        switch result.priority {
        case .stopAndGetChecked: risk = .high
        case .easeOff, .lighter: risk = .moderate
        case .logFirstSession, .progress, .keepAsPlanned: risk = .low
        }
        let missing: [String] = result.priority == .logFirstSession ? ["training_log"] : []
        return ExpertResult(
            mode: .personalTraining, answer: message(result, language: language), missingData: missing,
            sources: [.acsm2026], caveats: [TrainingExpert.disclosure(language == .polish)], riskLevel: risk)
    }

    // MARK: Pieces

    private static func progressText(_ key: String, _ advice: ExerciseAdvice, _ review: ExerciseReview,
                                     polish: Bool, language: NotificationLanguage) -> String {
        let name = exerciseName(key, language)
        let lead = polish ? "Na następny trening zmień jedno: " : "For your next session change one thing: "
        let body: String
        switch advice {
        case .addLoad(let kilograms):
            let kg = kilogramText(kilograms, polish: polish)
            body = polish
                ? "w «\(name)» dodaj \(kg) kg i zacznij od \(review.low) powtórzeń. Wszystkie serie doszły do górnej granicy z zapasem co najmniej 2 powtórzeń. Resztę zostaw."
                : "in “\(name)” add \(kg) kg and start again from \(review.low) reps. Every set reached the top of the range with at least 2 reps in reserve. Leave the rest."
        case .harderVariation:
            body = polish
                ? "w «\(name)» przejdź na trudniejszą wersję ćwiczenia. Wszystkie serie doszły do górnej granicy z zapasem co najmniej 2 powtórzeń. Resztę zostaw."
                : "in “\(name)” move to a harder version of the exercise. Every set reached the top of the range with at least 2 reps in reserve. Leave the rest."
        case .addReps:
            body = polish
                ? "w «\(name)» dołóż po 1 powtórzeniu w seriach, do \(review.high). Ciężar i resztę zostaw."
                : "in “\(name)” add 1 rep to each set, up to \(review.high). Leave the load and the rest."
        case .longerHold:
            body = polish
                ? "w «\(name)» przytrzymaj o kilka sekund dłużej, do \(review.high) s. Resztę zostaw."
                : "in “\(name)” hold a few seconds longer, up to \(review.high) s. Leave the rest."
        case .keep, .lighter:
            return keepText(TrainingReviewResult(priority: .keepAsPlanned, exercises: [review], sessionsLookedAt: 1), polish)
        }
        return lead + body + comparison(review, polish: polish)
    }

    /// What the log itself says about this exercise across the two weeks, when the load was the same
    /// both times so the totals can be compared. Facts, not praise.
    private static func comparison(_ review: ExerciseReview, polish: Bool) -> String {
        guard let previous = review.previous, previous.topLoadGrams == review.latest.topLoadGrams else { return "" }
        let unit = review.timed ? "s" : (polish ? repsWord(review.latest.totalReps) : "reps")
        return polish
            ? " W ostatnim treningu razem \(review.latest.totalReps) \(unit), wcześniej \(previous.totalReps)."
            : " In your last session \(review.latest.totalReps) \(unit) in total, before that \(previous.totalReps)."
    }

    private static func keepText(_ result: TrainingReviewResult, _ polish: Bool) -> String {
        let needReserve = result.exercises.contains { $0.missingReserve }
        let base = polish
            ? "Nic nie zmieniam. Zostaw ciężary, powtórzenia i minuty tak jak w planie."
            : "I'm changing nothing. Keep the loads, reps and minutes as the plan has them."
        guard needReserve else { return base }
        return base + (polish
            ? " Żeby cokolwiek podnieść, potrzebuję przy każdej serii zapisu, ile powtórzeń jeszcze byś zrobił."
            : " To raise anything, I need a note on each set of how many more reps you could have done.")
    }

    private static func exerciseName(_ key: String, _ language: NotificationLanguage) -> String {
        ExerciseCatalogue.card(forKey: key)?.name.text(language) ?? key.replacingOccurrences(of: "_", with: " ")
    }

    private static func kilogramText(_ kilograms: Double, polish: Bool) -> String {
        let text = kilograms == kilograms.rounded() ? String(Int(kilograms)) : String(kilograms)
        return polish ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    /// "powtórzenie / powtórzenia / powtórzeń" for the totals.
    private static func repsWord(_ count: Int) -> String {
        if count == 1 { return "powtórzenie" }
        let tens = count % 100, units = count % 10
        return (2...4).contains(units) && !(12...14).contains(tens) ? "powtórzenia" : "powtórzeń"
    }
}
