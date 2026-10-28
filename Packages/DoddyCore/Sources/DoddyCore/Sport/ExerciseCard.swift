import Foundation

// Exercise cards (ADR-642; research section 2.3). One text-only card for each exercise the plan
// engine can prescribe, so a plan can say how to do it without a picture or a video. The cards are
// written for Doddy in Doddy's own words; no atlas, picture or video is copied (research: "do not use
// commercial atlases without a licence"; pictures wait for wger's licensed set, ADR-624). Each card
// cites the guidance its loading rule rests on (WHO 2020, ACSM 2026) and says when it was last
// reviewed. A card explains and never diagnoses: its safety line always says to stop at sudden,
// sharp pain without guessing the cause.
//
// Platforms: iPhone, iPad, Mac, Watch (DoddyCore, no UI).

public struct LocalizedText: Equatable, Hashable, Codable, Sendable {
    public let pl: String
    public let en: String

    public init(pl: String, en: String) {
        self.pl = pl
        self.en = en
    }

    public func text(_ language: NotificationLanguage) -> String { language == .polish ? pl : en }
}

public enum MovementPattern: String, Codable, CaseIterable, Sendable {
    case squat, hinge, push, pull, carry, locomotion
    /// Planks and the like: holding the trunk still.
    case core
    /// One small muscle group, such as the calves.
    case isolation
}

public struct ExerciseCard: Equatable, Hashable, Codable, Sendable, Identifiable {
    /// The key the plan engine uses (`StrengthExercise.key`), or a session kind for the run cards.
    public let id: String
    public let name: LocalizedText
    public let pattern: MovementPattern
    public let primaryMuscles: [String]
    /// What it needs, as alternatives: ["kettlebell", "dumbbell"] means one of them. Empty: nothing.
    public let equipment: [String]
    public let easierVersion: LocalizedText?
    public let coachingCues: [LocalizedText]
    public let commonIssues: [LocalizedText]
    public let safety: LocalizedText
    public let sources: [ExpertSource]
    /// A day, `yyyy-MM-dd`.
    public let reviewedAt: String
    public let wording: String

    public static let ownWording = "Doddy's own words. No atlas, picture or video was copied."
}

public enum ExerciseCatalogue {
    public static let reviewedAt = "2026-10-24"

    /// The line every card ends with: stop, and don't guess why.
    static let stopLine = LocalizedText(
        pl: "Przerwij przy nagłym, ostrym bólu i nie szukaj przyczyny na własną rękę; jeśli ból wraca, pokaż go lekarzowi lub fizjoterapeucie.",
        en: "Stop at sudden, sharp pain and don't try to find the cause yourself; if it comes back, show it to a doctor or a physiotherapist.")

    public static func card(forKey key: String) -> ExerciseCard? { byID[key] }

    public static var all: [ExerciseCard] { cards }

    private static let byID: [String: ExerciseCard] = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })

    private static func t(_ pl: String, _ en: String) -> LocalizedText { LocalizedText(pl: pl, en: en) }

    private static func strength(
        _ id: String, _ pl: String, _ en: String, _ pattern: MovementPattern, muscles: [String], equipment: [String] = [],
        easier: (String, String)?, cues: [(String, String)], issues: [(String, String)], extraSafety: (String, String)? = nil
    ) -> ExerciseCard {
        ExerciseCard(
            id: id, name: t(pl, en), pattern: pattern, primaryMuscles: muscles, equipment: equipment,
            easierVersion: easier.map { t($0.0, $0.1) },
            coachingCues: cues.map { t($0.0, $0.1) }, commonIssues: issues.map { t($0.0, $0.1) },
            safety: extraSafety.map { t($0.0 + " " + stopLine.pl, $0.1 + " " + stopLine.en) } ?? stopLine,
            sources: [.who2020, .acsm2026], reviewedAt: reviewedAt, wording: ExerciseCard.ownWording)
    }

    private static let cards: [ExerciseCard] = [
        strength("squat", "Przysiad", "Squat", .squat, muscles: ["quadriceps", "glutes"],
                 easier: ("Wstawanie z krzesła i siadanie.", "Sit-to-stand from a chair."),
                 cues: [("Stopy na szerokość bioder lub trochę szerzej, kolana idą w kierunku palców.", "Feet hip-width or a little wider; knees follow the toes."),
                        ("Schodź tak głęboko, jak możesz to kontrolować, z prostymi plecami.", "Go as deep as you can control, with a straight back.")],
                 issues: [("Pięty odrywają się od podłogi.", "Heels lift off the floor."), ("Kolana uciekają do środka.", "Knees cave inwards.")]),
        strength("goblet_squat", "Przysiad goblet", "Goblet squat", .squat, muscles: ["quadriceps", "glutes"],
                 equipment: ["kettlebell", "dumbbell"],
                 easier: ("Przysiad bez ciężaru albo wstawanie z krzesła.", "A squat with no weight, or sit-to-stand."),
                 cues: [("Ciężar trzymaj przy klatce, łokcie w dół.", "Hold the weight at your chest, elbows pointing down."),
                        ("Stabilna pozycja, kontrolowany ruch, zakres komfortowy.", "A steady stance, a controlled movement, a comfortable range.")],
                 issues: [("Utrata stabilności.", "Losing balance."), ("Ciężar za duży do kontroli.", "A weight too heavy to control.")]),
        strength("back_squat", "Przysiad ze sztangą na plecach", "Back squat", .squat, muscles: ["quadriceps", "glutes", "adductors"],
                 equipment: ["barbell and rack"],
                 easier: ("Przysiad goblet z lżejszym ciężarem.", "A goblet squat with a lighter weight."),
                 cues: [("Sztanga na górze pleców, brzuch napięty, wzrok przed siebie.", "The bar on your upper back, belly braced, eyes ahead."),
                        ("Zawsze stań w stojakach z ogranicznikami i zostaw 2 powtórzenia w zapasie.", "Always use a rack with safety arms and leave 2 reps in reserve.")],
                 issues: [("Tułów opada do przodu.", "The trunk falls forward."), ("Ciężar dobrany ponad kontrolę.", "A load chosen beyond control.")],
                 extraSafety: ("Przy dużych ciężarach ćwicz ze stojakiem lub z asekuracją.", "With heavy loads use a rack or a spotter.")),
        strength("reverse_lunge", "Wykrok do tyłu", "Reverse lunge", .squat, muscles: ["quadriceps", "glutes"],
                 easier: ("Wykrok z podparciem ręką o ścianę lub poręcz.", "A lunge with a hand on a wall or rail."),
                 cues: [("Krok do tyłu, przednia stopa cała na podłodze.", "Step back; the front foot stays flat."),
                        ("Tułów prosto, kolano tylnej nogi opuszczaj powoli.", "Trunk upright; lower the back knee slowly.")],
                 issues: [("Zbyt krótki krok.", "A step that is too short."), ("Chwiejność.", "Wobbling.")]),
        strength("leg_press", "Wypychanie ciężaru nogami na suwnicy", "Leg press", .squat, muscles: ["quadriceps", "glutes"],
                 equipment: ["leg press machine"],
                 easier: ("Mniejszy ciężar i krótszy zakres ruchu.", "A lighter load and a shorter range."),
                 cues: [("Plecy i biodra przylegają do oparcia przez cały ruch.", "Your back and hips stay on the pad throughout."),
                        ("Nie prostuj kolan do końca na siłę.", "Don't lock the knees out hard.")],
                 issues: [("Biodra odrywają się od siedziska.", "Hips lift off the seat."), ("Zbyt duży ciężar.", "Too heavy a load.")]),
        strength("push_up", "Pompka", "Push-up", .push, muscles: ["chest", "triceps", "front deltoids"],
                 easier: ("Pompka z rękami na podwyższeniu.", "A push-up with your hands on a raised surface."),
                 cues: [("Ciało w jednej linii od głowy do stóp.", "Your body in one line from head to feet."),
                        ("Łokcie pod kątem, nie szeroko na boki.", "Elbows angled back, not flared wide.")],
                 issues: [("Biodra opadają.", "Hips sag."), ("Zakres ruchu za mały.", "A range that is too small.")]),
        strength("incline_push_up", "Pompka z rękami na podwyższeniu", "Incline push-up", .push, muscles: ["chest", "triceps", "front deltoids"],
                 equipment: ["a stable bench, table or wall"],
                 easier: ("Wyższe podparcie, na przykład ściana.", "A higher support, such as a wall."),
                 cues: [("Ręce na stabilnym podwyższeniu, ciało w jednej linii.", "Hands on a stable surface, body in one line."),
                        ("Im niższe podparcie, tym trudniej.", "The lower the support, the harder it gets.")],
                 issues: [("Niestabilne podparcie.", "An unstable support."), ("Biodra opadają.", "Hips sag.")]),
        strength("knee_push_up", "Pompka na kolanach", "Knee push-up", .push, muscles: ["chest", "triceps", "front deltoids"],
                 easier: ("Pompka z rękami na podwyższeniu.", "A push-up with your hands on a raised surface."),
                 cues: [("Linia od kolan do głowy prosta.", "A straight line from knees to head."),
                        ("Opuszczaj się powoli, z kontrolą.", "Lower yourself slowly and with control.")],
                 issues: [("Biodra wypchnięte do tyłu.", "Hips pushed back."), ("Zbyt szybkie tempo.", "A pace that is too fast.")]),
        strength("pike_push_up", "Pompka w pozycji odwróconego V", "Pike push-up", .push, muscles: ["shoulders", "triceps"],
                 easier: ("Ręce na podwyższeniu albo wyciskanie lekkich hantli nad głowę.", "Hands on a raised surface, or a light dumbbell shoulder press."),
                 cues: [("Biodra wysoko, ciało jak odwrócone V.", "Hips high, your body an upside-down V."),
                        ("Opuszczaj głowę między ręce, bez zjeżdżania do przodu.", "Lower your head between your hands without sliding forward.")],
                 issues: [("Biodra opadają.", "Hips drop."), ("Ból w barku.", "Pain in the shoulder.")]),
        strength("dumbbell_bench_press", "Wyciskanie hantli leżąc", "Dumbbell bench press", .push, muscles: ["chest", "triceps", "front deltoids"],
                 equipment: ["dumbbells", "bench"],
                 easier: ("Lżejsze hantle albo pompki z rękami na podwyższeniu.", "Lighter dumbbells, or incline push-ups."),
                 cues: [("Łopatki ściągnięte, stopy na podłodze.", "Shoulder blades drawn together, feet on the floor."),
                        ("Opuszczaj do poziomu klatki, wyciskaj bez blokowania łokci.", "Lower to chest level; press without locking the elbows.")],
                 issues: [("Hantle nierówno.", "The dumbbells uneven."), ("Ciężar nad kontrolę.", "A load beyond control.")]),
        strength("bench_press", "Wyciskanie sztangi leżąc", "Bench press", .push, muscles: ["chest", "triceps", "front deltoids"],
                 equipment: ["barbell, bench and rack"],
                 easier: ("Wyciskanie hantli leżąc z lżejszym ciężarem.", "A dumbbell bench press with a lighter load."),
                 cues: [("Łopatki ściągnięte, sztanga nad klatką, nadgarstki prosto.", "Shoulder blades together, the bar over your chest, wrists straight."),
                        ("Zawsze ze stojakiem z ogranicznikami lub z asekuracją.", "Always with a rack with safety arms, or a spotter.")],
                 issues: [("Biodra odrywają się od ławki.", "Hips lift off the bench."), ("Ciężar nad kontrolę.", "A load beyond control.")],
                 extraSafety: ("Nie ćwicz z dużym ciężarem sam i bez stojaka.", "Don't train with a heavy load alone and without a rack.")),
        strength("dumbbell_shoulder_press", "Wyciskanie hantli nad głowę", "Dumbbell shoulder press", .push, muscles: ["shoulders", "triceps"],
                 equipment: ["dumbbells"],
                 easier: ("Lżejsze hantle, ćwiczenie siedząc z oparciem.", "Lighter dumbbells, seated with back support."),
                 cues: [("Brzuch napięty, żebra nie wypchnięte do przodu.", "Belly braced, ribs not pushed forward."),
                        ("Wyciskaj w górę, nad barkami, w kontrolowanym tempie.", "Press up over your shoulders at a controlled pace.")],
                 issues: [("Plecy wyginają się w łuk.", "The back arches."), ("Ból w barku.", "Pain in the shoulder.")]),
        strength("backpack_row", "Wiosłowanie z plecakiem", "Backpack row", .pull, muscles: ["lats", "rhomboids", "biceps"],
                 equipment: ["a loaded backpack"],
                 easier: ("Lżejszy plecak i ręka oparta o kolano lub krzesło.", "A lighter backpack and a hand on a knee or chair."),
                 cues: [("Pochyl się z prostymi plecami, plecak przy ciele.", "Hinge over with a straight back, the backpack close to you."),
                        ("Przyciągaj łokcie do biodra, łopatki do siebie.", "Pull your elbows to your hips, shoulder blades together.")],
                 issues: [("Szarpanie tułowiem.", "Jerking the trunk."), ("Okrągłe plecy.", "A rounded back.")]),
        strength("seated_cable_row", "Wiosłowanie na wyciągu siedząc", "Seated cable row", .pull, muscles: ["lats", "rhomboids", "biceps"],
                 equipment: ["cable machine"],
                 easier: ("Mniejszy ciężar i wolniejsze tempo.", "A lighter load and a slower pace."),
                 cues: [("Siedź prosto, przyciągaj uchwyt do brzucha.", "Sit tall and pull the handle to your belly."),
                        ("Łopatki ściągaj na końcu ruchu, bez kołysania tułowiem.", "Draw the shoulder blades together at the end, with no rocking.")],
                 issues: [("Kołysanie tułowiem.", "Rocking the trunk."), ("Za duży ciężar.", "Too heavy a load.")]),
        strength("lat_pulldown", "Ściąganie drążka wyciągu górnego", "Lat pulldown", .pull, muscles: ["lats", "biceps"],
                 equipment: ["lat pulldown machine"],
                 easier: ("Mniejszy ciężar albo wiosłowanie na wyciągu.", "A lighter load, or a seated cable row."),
                 cues: [("Ściągaj drążek do górnej części klatki, łokcie w dół.", "Pull the bar to your upper chest, elbows down."),
                        ("Nie odchylaj się mocno do tyłu.", "Don't lean far back.")],
                 issues: [("Ściąganie za głowę.", "Pulling behind the head."), ("Szarpanie.", "Jerking.")]),
        strength("romanian_deadlift", "Martwy ciąg rumuński", "Romanian deadlift", .hinge, muscles: ["hamstrings", "glutes", "back extensors"],
                 equipment: ["barbell", "dumbbells"],
                 easier: ("Hantle lub sam ruch bez ciężaru; albo mostek biodrowy.", "Dumbbells or no weight at all; or a glute bridge."),
                 cues: [("Biodra do tyłu, kolana lekko ugięte, plecy proste.", "Hips back, knees slightly bent, back straight."),
                        ("Sztanga lub hantle blisko nóg.", "The bar or dumbbells stay close to your legs.")],
                 issues: [("Zaokrąglone plecy.", "A rounded back."), ("Ciężar nad kontrolę.", "A load beyond control.")],
                 extraSafety: ("Przy zaokrąglonych plecach zmniejsz ciężar.", "If your back rounds, lower the load.")),
        strength("glute_bridge", "Mostek biodrowy", "Glute bridge", .hinge, muscles: ["glutes", "hamstrings"],
                 easier: ("Mniejszy zakres ruchu, stopy bliżej pośladków.", "A smaller range, feet closer to your buttocks."),
                 cues: [("Leżąc, unieś biodra, aż ciało będzie w linii od kolan do ramion.", "Lying down, raise your hips until your body forms a line from knees to shoulders."),
                        ("Przytrzymaj chwilę u góry, opuszczaj powoli.", "Hold briefly at the top and lower slowly.")],
                 issues: [("Plecy wyginają się w łuk.", "The lower back arches."), ("Praca tylko ud.", "Only the thighs doing the work.")]),
        strength("single_leg_glute_bridge", "Mostek biodrowy na jednej nodze", "Single-leg glute bridge", .hinge, muscles: ["glutes", "hamstrings"],
                 easier: ("Mostek biodrowy na dwóch nogach.", "A two-leg glute bridge."),
                 cues: [("Jedna noga wyprostowana w powietrzu, biodra w jednej linii.", "One leg straight in the air, hips level."),
                        ("Unoś się ruchem kontrolowanym, bez skrętu miednicy.", "Rise with control and no twist of the pelvis.")],
                 issues: [("Biodra przechylają się na bok.", "Hips tilt to one side."), ("Plecy w łuk.", "The back arches.")]),
        strength("hip_thrust", "Unoszenie bioder z podparciem pleców", "Hip thrust", .hinge, muscles: ["glutes"],
                 equipment: ["bench", "dumbbell or barbell"],
                 easier: ("Mostek biodrowy bez ciężaru.", "A glute bridge with no weight."),
                 cues: [("Łopatki na ławce, stopy na podłodze, biodra w górę.", "Shoulder blades on the bench, feet on the floor, hips up."),
                        ("Broda przy klatce, żebra w dół, bez wyginania pleców.", "Chin tucked, ribs down, with no arching of the back.")],
                 issues: [("Plecy w łuk.", "The back arches."), ("Ciężar nad kontrolę.", "A load beyond control.")]),
        strength("plank", "Deska", "Plank", .core, muscles: ["abdominals", "deep trunk muscles"],
                 easier: ("Deska na kolanach albo z rękami na podwyższeniu.", "A plank on your knees or with hands on a raised surface."),
                 cues: [("Ciało w linii od głowy do pięt, brzuch napięty.", "Your body in a line from head to heels, belly braced."),
                        ("Oddychaj spokojnie, nie wstrzymuj oddechu.", "Breathe calmly; don't hold your breath.")],
                 issues: [("Biodra opadają.", "Hips sag."), ("Biodra za wysoko.", "Hips too high.")]),
        strength("side_plank", "Deska boczna", "Side plank", .core, muscles: ["obliques", "deep trunk muscles"],
                 easier: ("Deska boczna z kolan.", "A side plank from your knees."),
                 cues: [("Łokieć pod barkiem, biodra uniesione w jednej linii.", "Elbow under your shoulder, hips raised in one line."),
                        ("Patrz przed siebie, oddychaj spokojnie.", "Look ahead and breathe calmly.")],
                 issues: [("Biodra opadają.", "Hips drop."), ("Skręt tułowia.", "The trunk twists.")]),
        strength("dead_bug", "Martwy żuk", "Dead bug", .core, muscles: ["abdominals", "hip flexors"],
                 easier: ("Ruszaj tylko rękami albo tylko nogami.", "Move only your arms, or only your legs."),
                 cues: [("Leżąc, dolny odcinek pleców przy podłodze.", "Lying down, keep your lower back close to the floor."),
                        ("Wyprostuj przeciwną rękę i nogę powoli, wróć i zmień stronę.", "Extend the opposite arm and leg slowly, return and switch sides.")],
                 issues: [("Plecy odrywają się od podłogi.", "The lower back lifts off the floor."), ("Zbyt szybkie tempo.", "A pace that is too fast.")]),
        strength("calf_raise", "Wspięcia na palce", "Calf raise", .isolation, muscles: ["calves"],
                 equipment: ["a step or machine, optional"],
                 easier: ("Na dwóch nogach, z ręką na ścianie.", "On two feet, with a hand on a wall."),
                 cues: [("Wspinaj się na palce wolno i opuszczaj powoli.", "Rise on your toes slowly and lower slowly."),
                        ("Kolana lekko ugięte, ciężar na przodostopiu.", "Knees slightly bent, weight on the ball of your foot.")],
                 issues: [("Kołysanie na boki.", "Rocking sideways."), ("Zbyt krótki zakres.", "A range that is too short.")]),
        run("run_walk", "Marszobieg", "Run/walk intervals",
            easier: ("Krótszy bieg i dłuższy marsz.", "A shorter run and a longer walk."),
            cues: [("Biegnij tak, żebyś mógł mówić pełnymi zdaniami.", "Run so that you could speak in full sentences."),
                   ("Przed i po bloku pięć minut spokojnego marszu.", "Five minutes of easy walking before and after the block.")],
            issues: [("Zbyt szybki start.", "Starting too fast."), ("Pomijanie marszu.", "Skipping the walks.")]),
        run("easy_run", "Spokojny bieg", "Easy run",
            easier: ("Marszobieg z krótszymi biegami.", "Run/walk with shorter runs."),
            cues: [("Tempo, w którym możesz rozmawiać (test rozmowy).", "A pace at which you can talk (the talk test)."),
                   ("Większość biegów ma być spokojna; około 80% tygodnia.", "Most runs should be easy; about 80% of the week.")],
            issues: [("Bieg zbyt szybko każdego dnia.", "Running too fast every day."), ("Zbyt duży skok długości.", "Too big a jump in length.")]),
    ]

    /// The run cards cite the walk/run rule the plan keeps (a run no more than 10% longer than the longest
    /// of the last 30 days) and the idea of the NHS's Couch to 5K; the table itself is Doddy's own.
    private static func run(_ id: String, _ pl: String, _ en: String, easier: (String, String),
                            cues: [(String, String)], issues: [(String, String)]) -> ExerciseCard {
        ExerciseCard(
            id: id, name: t(pl, en), pattern: .locomotion, primaryMuscles: ["legs", "heart and lungs"], equipment: [],
            easierVersion: t(easier.0, easier.1), coachingCues: cues.map { t($0.0, $0.1) },
            commonIssues: issues.map { t($0.0, $0.1) }, safety: stopLine,
            sources: [.who2020, .frandsen2025], reviewedAt: reviewedAt,
            wording: ExerciseCard.ownWording + " The run/walk table is Doddy's own; only the idea comes from the NHS's Couch to 5K.")
    }
}
