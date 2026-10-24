import XCTest
@testable import DoddyCore

/// ADR-632: red flags in free text get one fixed message that code owns (research rules 1, 4, 5, 6).
final class TrainingTriageTests: XCTestCase {
    private func flags(_ text: String) -> Set<TriageFlag> { TrainingTriage.assess(text).flags }

    func testChestPainInPolishAndEnglishStopsEverything() {
        for text in ["Boli mnie nagle w klatce przy treningu", "BOLI MNIE W KLATCE", "mam ucisk w klatce piersiowej",
                     "chest pain when I run", "pressure in my chest", "my chest hurts", "tightness in the chest"] {
            let outcome = TrainingTriage.assess(text)
            XCTAssertTrue(outcome.flags.contains(.chestPain), text)
            XCTAssertTrue(outcome.stopNow, text)
            XCTAssertFalse(outcome.planAllowed, text)
            XCTAssertEqual(outcome.risk, .emergency, text)
        }
    }

    func testTheOtherEmergencySignsEachStop() {
        let cases: [(String, TriageFlag)] = [
            ("zemdlałem na bieżni", .fainting), ("Omdlałam po treningu", .fainting), ("I fainted at the gym", .fainting),
            ("straciłem przytomność", .fainting), ("I almost passed out", .fainting),
            ("mam zawroty głowy", .dizziness), ("kręci mi się w głowie", .dizziness), ("I feel dizzy", .dizziness),
            ("mam duszność przy schodach", .unexplainedBreathlessness), ("nie mogę złapać tchu", .unexplainedBreathlessness),
            ("I'm short of breath", .unexplainedBreathlessness), ("I can't breathe", .unexplainedBreathlessness),
            ("mam kołatanie serca", .palpitations), ("heart racing", .palpitations), ("palpitations after the run", .palpitations),
            ("drętwieje mi ręka", .neurologicalSigns), ("double vision after lifting", .neurologicalSigns),
            ("ból promieniuje do szczęki", .jawOrRadiatingPain), ("pain in my jaw", .jawOrRadiatingPain),
            ("nagły ucisk w lewej ręce", .jawOrRadiatingPain),
        ]
        for (text, flag) in cases {
            let outcome = TrainingTriage.assess(text)
            XCTAssertTrue(outcome.flags.contains(flag), "\(text) should raise \(flag)")
            XCTAssertTrue(outcome.stopNow, text)
        }
    }

    func testANegationWithinThreeWordsCancelsAMatch() {
        for text in ["nie mam bólu w klatce", "no chest pain, just tired", "bez zawrotów głowy", "I don't have palpitations",
                     "nigdy nie omdlałem", "I'm not pregnant", "bez urazów"] {
            XCTAssertEqual(flags(text), [], text)
        }
    }

    func testBeingSoreAfterAWorkoutIsNotChestPainUnlessSomethingSuddenIsSaid() {
        XCTAssertEqual(flags("bolą mnie mięśnie klatki po treningu"), [])
        XCTAssertEqual(flags("mam zakwasy w klatce piersiowej"), [])
        XCTAssertEqual(flags("my chest muscles are sore after bench day"), [])
        XCTAssertTrue(flags("bolą mnie mięśnie klatki, nagle ucisk").contains(.chestPain))
        XCTAssertTrue(flags("my muscles are sore but I felt a sudden crushing pain in my chest").contains(.chestPain))
    }

    func testEverydayWordsThatLookLikeSymptomsDoNotTrigger() {
        for text in ["duszno na siłowni", "mam zadyszkę po biegu", "słabo mi idzie bieganie", "my phone number is on the form",
                     "I track my blood pressure and heart rate on my watch", "Trenuję 3 dni w tygodniu", "boli mnie lekko łydka po sprincie"] {
            XCTAssertEqual(flags(text), [], text)
        }
    }

    func testSharpInjuryMeansNoPlanButNotAnEmergencyStop() {
        for text in ["skręciłem kostkę", "naciągnąłem mięsień", "I sprained my wrist", "mam ostry ból w kolanie", "sharp pain in my knee"] {
            let outcome = TrainingTriage.assess(text)
            XCTAssertTrue(outcome.flags.contains(.sharpInjury), text)
            XCTAssertFalse(outcome.planAllowed, text)
            XCTAssertFalse(outcome.stopNow, text)
            XCTAssertEqual(outcome.risk, .high, text)
        }
    }

    func testPregnancyMeansGeneralAdviceOnly() {
        for text in ["jestem w ciąży", "urodziłam miesiąc temu", "I'm pregnant", "just gave birth"] {
            let outcome = TrainingTriage.assess(text)
            XCTAssertTrue(outcome.flags.contains(.pregnancy), text)
            XCTAssertFalse(outcome.planAllowed, text)
            XCTAssertEqual(outcome.risk, .moderate, text)
        }
    }

    func testEatingDisorderCuesSwitchNumbersOffAndNothingElse() {
        for text in ["mam bulimię", "wymiotuję po jedzeniu", "I have anorexia", "I've been starving myself", "zaburzenia odżywiania"] {
            let outcome = TrainingTriage.assess(text)
            XCTAssertTrue(outcome.flags.contains(.eatingDisorderCue), text)
            XCTAssertFalse(outcome.numbersAllowed, text)
            XCTAssertTrue(outcome.planAllowed, "a cue alone is not a stop")
            XCTAssertEqual(outcome.risk, .high, text)
        }
    }

    func testTheMessageIsTheFixedTextAndNothingElse() {
        let stop = TrainingTriage.assess("boli mnie w klatce")
        XCTAssertEqual(stop.message(.polish), TrainingTriage.stopPL)
        XCTAssertEqual(stop.message(.english), TrainingTriage.stopEN)
        for text in [TrainingTriage.stopPL, TrainingTriage.stopEN] {
            XCTAssertTrue(text.contains("112"))
            XCTAssertFalse(text.lowercased().contains("diagnos") && !text.lowercased().contains("don't diagnose"))
        }
        XCTAssertEqual(TrainingTriage.assess("jestem w ciąży").message(.polish), TrainingTriage.pregnancyPL)
        XCTAssertEqual(TrainingTriage.assess("skręciłem kostkę").message(.english), TrainingTriage.injuryEN)
        XCTAssertEqual(TrainingTriage.assess("mam bulimię").message(.polish), TrainingTriage.eatingPL)
        XCTAssertNil(TrainingTriage.assess("Trenuję 3 dni").message(.polish))
        // A stop outranks the rest when several are raised.
        let both = TrainingTriage.assess("jestem w ciąży i mam zawroty głowy")
        XCTAssertEqual(both.message(.polish), TrainingTriage.stopPL)
    }

    func testEveryTextAdmitsItIsAnAIAndNeverGivesANumberOfCalories() {
        let all = [TrainingTriage.stopPL, TrainingTriage.stopEN, TrainingTriage.injuryPL, TrainingTriage.injuryEN,
                   TrainingTriage.pregnancyPL, TrainingTriage.pregnancyEN, TrainingTriage.eatingPL, TrainingTriage.eatingEN]
        for text in all {
            XCTAssertFalse(text.lowercased().contains("kcal"), text)
            XCTAssertFalse(text.lowercased().contains("kalor") && text.contains(where: \.isNumber), text)
        }
        for flag in TriageFlag.allCases {
            for language in [NotificationLanguage.polish, .english] {
                XCTAssertFalse(TrainingTriage.fixedMessage(for: flag, language: language).isEmpty)
            }
        }
    }

    func testHumorIsOffAboveLow() {
        XCTAssertTrue(TriageOutcome.clear.humorAllowed)
        XCTAssertTrue(TrainingTriage.assess("Trenuję 3 dni").humorAllowed)
        for text in ["boli mnie w klatce", "skręciłem kostkę", "jestem w ciąży", "mam bulimię"] {
            XCTAssertFalse(TrainingTriage.assess(text).humorAllowed, text)
        }
    }

    func testEmptyTextRaisesNothing() {
        XCTAssertEqual(TrainingTriage.assess(""), .clear)
        XCTAssertEqual(TrainingTriage.assess("   \n"), .clear)
    }
}
