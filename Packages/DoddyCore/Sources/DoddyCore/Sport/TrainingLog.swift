import Foundation

// The training logbook (ADR-642; research docs/research/2026-10-24/research_expert_modes_PL.md
// section 2.4): what the person did in a session — sets, reps, load, how many reps were left, and how
// it felt — kept on this iPhone so the next session can be judged on what really happened and not on
// what the plan said. Training notes are health data, so the rules are tighter than for a note:
//   - nothing is written until the person has said yes to keeping a log, and the yes can be taken back;
//   - a write is read back before it counts as saved;
//   - the person can see everything (export) and remove everything (delete all) at any time;
//   - nothing here leaves the phone, and no word of it is sent to a model by this code.
// This file holds the values and the port (the protocol a store implements). The store itself is
// `SQLiteTrainingLogRepository` in DoddyPersistence.
//
// Platforms: iPhone, iPad, Mac, Watch (DoddyCore, no UI).

/// How a session felt. `pain` means pain and not tiredness: the review never raises anything while
/// one is on record (`TrainingReview`).
public enum TrainingFeeling: String, Codable, CaseIterable, Sendable {
    case easy, okay, hard, pain
}

/// Why a log entry was refused. Each one is a rule of the value, so the same rule holds for a
/// screen, a voice tool and a file read back from disk.
public enum TrainingLogProblem: Equatable, Sendable {
    /// A session with no sets and no run time says nothing.
    case emptySession
    case tooManySets
    /// An exercise key is a short lowercase word with digits and underscores, never free text.
    case badExerciseKey
    case badReps
    case badLoad
    case badReserve
    case badWeek
    case badRunMinutes
    /// More than a day ahead of now.
    case inTheFuture
}

public enum TrainingLogError: Error, Equatable, Sendable {
    /// The person has not said yes to keeping a log, or has taken it back.
    case consentMissing
    case invalid(TrainingLogProblem)
    case notFound(UUID)
    /// The write reported success but reading it back did not match. Treated as a failed save.
    case verificationFailed
    /// A stored row no longer satisfies the rules of the value.
    case corruptRecord(String)
}

/// One set as it was done. `reps` is seconds for a timed hold (the plan says which).
public struct LoggedSet: Equatable, Hashable, Codable, Sendable {
    public static let maxReps = 200
    public static let maxLoadGrams = 500_000
    public static let maxReserve = 10

    public let exerciseKey: String
    public let reps: Int
    /// Grams, so that 2.5 kg is 2,500 and compares exactly. Nil is bodyweight or "not said".
    public let loadGrams: Int?
    /// How many more reps could have been done. Nil when not said; the review then raises nothing.
    public let repsInReserve: Int?

    public var loadKilograms: Double? { loadGrams.map { Double($0) / 1000 } }

    public init(exerciseKey: String, reps: Int, loadKilograms: Double? = nil, repsInReserve: Int? = nil) throws {
        var grams: Int?
        if let loadKilograms {
            guard loadKilograms.isFinite, loadKilograms >= 0, loadKilograms * 1000 <= Double(Self.maxLoadGrams) else {
                throw TrainingLogError.invalid(.badLoad)
            }
            grams = Int((loadKilograms * 1000).rounded())
        }
        try self.init(exerciseKey: exerciseKey, reps: reps, loadGrams: grams, repsInReserve: repsInReserve)
    }

    public init(exerciseKey: String, reps: Int, loadGrams: Int?, repsInReserve: Int?) throws {
        guard Self.isValidKey(exerciseKey) else { throw TrainingLogError.invalid(.badExerciseKey) }
        guard (0...Self.maxReps).contains(reps) else { throw TrainingLogError.invalid(.badReps) }
        if let loadGrams, !(0...Self.maxLoadGrams).contains(loadGrams) { throw TrainingLogError.invalid(.badLoad) }
        if let repsInReserve, !(0...Self.maxReserve).contains(repsInReserve) { throw TrainingLogError.invalid(.badReserve) }
        self.exerciseKey = exerciseKey
        self.reps = reps
        self.loadGrams = loadGrams
        self.repsInReserve = repsInReserve
    }

    static func isValidKey(_ key: String) -> Bool {
        guard (1...48).contains(key.utf8.count) else { return false }
        return key.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 }
    }

    enum CodingKeys: String, CodingKey {
        case exerciseKey = "exercise_key"
        case reps
        case loadGrams = "load_grams"
        case repsInReserve = "reps_in_reserve"
    }

    /// A set read from a file goes through the same rules as one typed in.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            exerciseKey: container.decode(String.self, forKey: .exerciseKey),
            reps: container.decode(Int.self, forKey: .reps),
            loadGrams: container.decodeIfPresent(Int.self, forKey: .loadGrams),
            repsInReserve: container.decodeIfPresent(Int.self, forKey: .repsInReserve))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exerciseKey, forKey: .exerciseKey)
        try container.encode(reps, forKey: .reps)
        try container.encode(loadGrams, forKey: .loadGrams)
        try container.encode(repsInReserve, forKey: .repsInReserve)
    }
}

/// One training session: a strength session has sets, a run has its minutes; both have a feeling.
public struct LoggedSession: Equatable, Codable, Sendable, Identifiable {
    public static let maxSets = 40
    public static let maxRunMinutes = 600

    public let id: UUID
    /// When it was done, to the millisecond (what the database keeps).
    public let performedAt: Date
    /// The plan's week number, when the session came from a plan.
    public let planWeek: Int?
    public let feeling: TrainingFeeling
    public let runMinutes: Int?
    public let sets: [LoggedSet]

    public init(id: UUID = UUID(), performedAt: Date, planWeek: Int? = nil, feeling: TrainingFeeling,
                runMinutes: Int? = nil, sets: [LoggedSet] = []) throws {
        if let planWeek, !(1...52).contains(planWeek) { throw TrainingLogError.invalid(.badWeek) }
        if let runMinutes, !(1...Self.maxRunMinutes).contains(runMinutes) { throw TrainingLogError.invalid(.badRunMinutes) }
        guard !sets.isEmpty || runMinutes != nil else { throw TrainingLogError.invalid(.emptySession) }
        guard sets.count <= Self.maxSets else { throw TrainingLogError.invalid(.tooManySets) }
        self.id = id
        self.performedAt = EpochMilliseconds.date(EpochMilliseconds.truncated(performedAt))
        self.planWeek = planWeek
        self.feeling = feeling
        self.runMinutes = runMinutes
        self.sets = sets
    }

    enum CodingKeys: String, CodingKey {
        case id
        case performedAt = "performed_at"
        case planWeek = "plan_week"
        case feeling
        case runMinutes = "run_minutes"
        case sets
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            performedAt: container.decode(Date.self, forKey: .performedAt),
            planWeek: container.decodeIfPresent(Int.self, forKey: .planWeek),
            feeling: container.decode(TrainingFeeling.self, forKey: .feeling),
            runMinutes: container.decodeIfPresent(Int.self, forKey: .runMinutes),
            sets: container.decode([LoggedSet].self, forKey: .sets))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(performedAt, forKey: .performedAt)
        try container.encode(planWeek, forKey: .planWeek)
        try container.encode(feeling, forKey: .feeling)
        try container.encode(runMinutes, forKey: .runMinutes)
        try container.encode(sets, forKey: .sets)
    }
}

/// Whether the person has said yes to keeping a log. Never asked is the same as no.
public struct TrainingLogConsent: Equatable, Sendable {
    public let granted: Bool
    /// When the answer last changed; nil when the person was never asked.
    public let changedAt: Date?

    public init(granted: Bool, changedAt: Date?) {
        self.granted = granted
        self.changedAt = changedAt
    }

    public static let neverAsked = TrainingLogConsent(granted: false, changedAt: nil)
}

/// Everything the log holds, in a file the person can keep: JSON, readable, with ISO dates.
public struct TrainingLogExport: Equatable, Codable, Sendable {
    public static let format = "doddy.training_log"
    public static let version = 1

    public let format: String
    public let version: Int
    public let exportedAt: Date
    public let consentGranted: Bool
    /// Oldest first.
    public let sessions: [LoggedSession]

    public init(exportedAt: Date, consentGranted: Bool, sessions: [LoggedSession]) {
        self.format = Self.format
        self.version = Self.version
        self.exportedAt = EpochMilliseconds.date(EpochMilliseconds.truncated(exportedAt))
        self.consentGranted = consentGranted
        self.sessions = sessions.sorted { ($0.performedAt, $0.id.uuidString) < ($1.performedAt, $1.id.uuidString) }
    }

    enum CodingKeys: String, CodingKey {
        case format, version, sessions
        case exportedAt = "exported_at"
        case consentGranted = "consent_granted"
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.isoString(date))
        }
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> TrainingLogExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = Self.date(fromISO: text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 date: \(text)"))
            }
            return date
        }
        return try decoder.decode(TrainingLogExport.self, from: data)
    }

    // A new formatter each time: `ISO8601DateFormatter` is not Sendable, and an export is small.
    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(fromISO text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}

/// Where logged sessions are kept. A store must refuse to write without consent, read a write back
/// before returning, and remove rows for good on delete.
public protocol TrainingLogRepository: Sendable {
    func consent() async throws -> TrainingLogConsent
    /// The person said yes to keeping a log.
    func grantConsent() async throws -> TrainingLogConsent
    /// Stop recording. What is already kept stays until `deleteAll()`: taking back a yes is not a delete.
    func withdrawConsent() async throws -> TrainingLogConsent
    /// Saves a session, or replaces the one with the same id (a correction). Throws `consentMissing`
    /// without consent, `inTheFuture` for a session more than a day ahead, `verificationFailed` if the
    /// read-back differs.
    func record(_ session: LoggedSession) async throws -> LoggedSession
    /// Newest first. `from` keeps only sessions done at or after it.
    func sessions(from: Date?) async throws -> [LoggedSession]
    func session(id: UUID) async throws -> LoggedSession?
    func delete(id: UUID) async throws
    /// Removes every session and every set. Returns how many sessions were removed. Does not change consent.
    func deleteAll() async throws -> Int
    /// Always possible, with or without consent: the person's own data is theirs to read.
    func export() async throws -> TrainingLogExport
}
