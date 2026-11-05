import DoddyCore
import Foundation
import HealthKit

/// Sport mode step 1 (ADR-621): the only code that touches Apple Health (the guard script keeps
/// HealthKit in this folder). Read only: it asks for no write access and saves nothing to Health.
/// It reads when the "What Doddy sees" screen asks, turns the samples into DoddyCore's
/// `HealthGlance`, and keeps nothing. Nothing it reads is sent anywhere or spoken.
final class HealthReader: @unchecked Sendable {
    /// One store for the app, as Apple recommends. `@unchecked Sendable`: HKHealthStore is safe to
    /// use from any thread, and every method here is nonisolated, so nothing crosses an actor.
    static let shared = HealthReader()

    private let store = HKHealthStore()

    enum Failure: LocalizedError {
        case unavailable
        case notSetUp(String)
        case locked
        case readFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                NSLocalizedString("Health isn't available on this device.", comment: "Apple Health")
            case .notSetUp(let reason):
                String(format: NSLocalizedString("This build of Doddy can't use Health (%@).", comment: "Apple Health"), reason)
            case .locked:
                NSLocalizedString("Health can't be read while this iPhone is locked. Unlock it and try again.", comment: "Apple Health")
            case .readFailed(let reason):
                String(format: NSLocalizedString("Doddy couldn't read Health (%@).", comment: "Apple Health"), reason)
            }
        }
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// What Doddy asks to read. Nothing to write. Computed, so no non-Sendable value is stored
    /// statically.
    private static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.vo2Max),
            HKCategoryType(.sleepAnalysis),
        ]
    }

    /// Shows iOS's Health sheet the first time; after that iOS answers at once without asking.
    /// iOS never tells an app what the person allowed it to read, so success only means the
    /// question was asked.
    func requestRead() async throws {
        guard Self.isAvailable else { throw Failure.unavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
        } catch {
            // A build without the HealthKit entitlement lands here.
            throw Failure.notSetUp(error.localizedDescription)
        }
    }

    /// The last seven days as the screen shows them. Types the person didn't allow read as empty.
    func glance(now: Date, calendar: Calendar = .current) async throws -> HealthGlance {
        guard Self.isAvailable else { throw Failure.unavailable }
        let window = HealthWindow.lastDays(now: now, calendar: calendar)
        let previous = HealthWindow.previousDays(now: now, calendar: calendar)
        let night = HealthWindow.night(wakingOn: now, now: now, calendar: calendar)
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now) ?? window.start
        do {
            // Two weeks, so the summary can compare this week with the one before (ADR-622).
            let workouts = try await workouts(from: previous.start, to: window.end)
            let sleep = try await sleepSamples(from: night.start, to: night.end)
            let resting = try await readings(.restingHeartRate, from: window.start, to: window.end)
            let hrv = try await readings(.heartRateVariability, from: window.start, to: window.end)
            let vo2Max = try await readings(.vo2Max, from: ninetyDaysAgo, to: now, limit: 1)
            return HealthGlance(
                workouts: HealthWorkout.recent(workouts, in: window),
                thisWeek: WeekTotals.of(workouts, in: window),
                previousWeek: WeekTotals.of(workouts, in: previous),
                lastNight: SleepNight.summarize(sleep, window: night),
                restingHeartRate: ReadingGlance.of(resting, calendar: calendar),
                heartRateVariability: ReadingGlance.of(hrv, calendar: calendar),
                vo2Max: vo2Max.first)
        } catch let error as HKError where error.code == .errorDatabaseInaccessible {
            throw Failure.locked
        } catch {
            throw Failure.readFailed(error.localizedDescription)
        }
    }

    // MARK: Queries

    private func workouts(from start: Date, to end: Date) async throws -> [HealthWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 80)
        return try await descriptor.result(for: store).map(Self.workout)
    }

    private func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).compactMap { sample in
            Self.stage(sample.value).map { SleepSample(stage: $0, start: sample.startDate, end: sample.endDate) }
        }
    }

    private enum Measure {
        case restingHeartRate, heartRateVariability, vo2Max
    }

    private func readings(_ measure: Measure, from start: Date, to end: Date, limit: Int? = nil) async throws -> [HealthReading] {
        let type: HKQuantityType
        let unit: HKUnit
        switch measure {
        case .restingHeartRate:
            type = HKQuantityType(.restingHeartRate)
            unit = HKUnit.count().unitDivided(by: .minute())
        case .heartRateVariability:
            type = HKQuantityType(.heartRateVariabilitySDNN)
            unit = HKUnit.secondUnit(with: .milli)
        case .vo2Max:
            type = HKQuantityType(.vo2Max)
            unit = HKUnit(from: "ml/kg*min")
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: limit)
        return try await descriptor.result(for: store).map { HealthReading(value: $0.quantity.doubleValue(for: unit), date: $0.endDate) }
    }

    // MARK: Mapping to DoddyCore

    private static func workout(_ workout: HKWorkout) -> HealthWorkout {
        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        let meters = distanceTypes.lazy
            .compactMap { workout.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }
            .first
        let kilocalories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let heartRate = workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        return HealthWorkout(activity: activity(workout.workoutActivityType), start: workout.startDate, end: workout.endDate,
                             distanceMeters: meters, activeKilocalories: kilocalories, averageHeartRate: heartRate)
    }

    private static func activity(_ type: HKWorkoutActivityType) -> WorkoutActivity {
        switch type {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .cycling, .handCycling: .cycling
        case .swimming: .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: .strength
        case .highIntensityIntervalTraining: .hiit
        case .yoga: .yoga
        default: .other
        }
    }

    private static func stage(_ value: Int) -> SleepStage? {
        guard let analysis = HKCategoryValueSleepAnalysis(rawValue: value) else { return nil }
        switch analysis {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        case .asleepUnspecified: return .asleepUnspecified
        @unknown default: return nil
        }
    }
}
