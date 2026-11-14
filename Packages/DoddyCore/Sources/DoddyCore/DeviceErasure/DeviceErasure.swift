import Foundation

// "Erase everything on this iPhone" (DOD-08: never say something was erased without a verified storage operation).
// The plan is a list of steps, one per store (`DeviceStoreID`). Each step has an erase and a read-back, and a store
// counts as erased only when its read-back says nothing of the person's is left. Every step runs even when an earlier
// one failed, a store with no step is never reported erased, and running the plan again is harmless. UI-free and
// tested on Linux with in-memory stores; the app (`EraseThisIPhone.swift`) supplies the real ones.

/// How far the erase goes, for what ties this iPhone to Doddy's servers.
public enum DeviceErasureScope: String, Sendable, CaseIterable {
    /// The default: the signed-in Doddy account stays signed in, with what this iPhone needs to reach its servers (the
    /// Keychain sign-in items, `doddyAccount.*` and the voice id in preferences). Signing out and deleting the account
    /// are their own steps, offered next. This is also what lets an account that finds another account's data on this
    /// iPhone erase it and take the empty iPhone over (decision 2026-11-12-local-data-owner).
    case keepSignIn
    /// Right after a Doddy account was deleted and confirmed: nothing on this iPhone ties it to that account any more,
    /// so the sign-in items, the server ties and the switches that mirrored server copies go as well.
    case afterAccountDeleted

    public var keepsSignIn: Bool { self == .keepSignIn }

    /// The stores a plan must have a step for, in this scope.
    public var requiredStores: Set<DeviceStoreID> {
        switch self {
        case .keepSignIn: Set(DeviceStoreID.allCases).subtracting([.keychainServerHandles])
        case .afterAccountDeleted: Set(DeviceStoreID.allCases)
        }
    }
}

/// One store's erase and its read-back.
public struct DeviceErasureStep: Sendable {
    public let store: DeviceStoreID
    /// Removes what the store holds. Should be safe to run again on an empty store; a store that is already empty
    /// may throw nothing and do nothing.
    public let erase: @Sendable () async throws -> Void
    /// Reads the store back: true only when nothing of the person's is left. Not "the erase said it worked".
    public let verifyEmpty: @Sendable () async throws -> Bool

    public init(
        store: DeviceStoreID,
        erase: @escaping @Sendable () async throws -> Void,
        verifyEmpty: @escaping @Sendable () async throws -> Bool
    ) {
        self.store = store
        self.erase = erase
        self.verifyEmpty = verifyEmpty
    }
}

/// Why a store is not confirmed erased.
public enum DeviceErasureFailure: Equatable, Sendable {
    /// The erase failed and the read-back did not show the store empty. The text is for logs, not for the person.
    case eraseFailed(String)
    /// The erase ran, and reading the store back still showed something.
    case notEmpty
    /// The store couldn't be read back, so nobody knows whether it is empty. The text is for logs.
    case couldNotVerify(String)
    /// The plan has no step for this store.
    case notInPlan
}

public enum DeviceStoreOutcome: Equatable, Sendable {
    case erased
    case notConfirmed(DeviceErasureFailure)
}

public enum DeviceErasureResult: Equatable, Sendable {
    /// Every required store was read back as empty.
    case erased
    /// These stores were not confirmed, in the order of `DeviceStoreID.allCases`. Everything else was erased.
    case notConfirmed([DeviceStoreID])
}

public struct DeviceErasureReport: Equatable, Sendable {
    public let outcomes: [DeviceStoreID: DeviceStoreOutcome]
    /// The stores the plan had to cover.
    public let required: Set<DeviceStoreID>

    public init(outcomes: [DeviceStoreID: DeviceStoreOutcome], required: Set<DeviceStoreID>) {
        self.outcomes = outcomes
        self.required = required
    }

    /// Stores not confirmed erased, in the order of the inventory.
    public var notConfirmed: [DeviceStoreID] {
        DeviceStoreID.allCases.filter { id in
            guard required.contains(id) else { return false }
            if case .notConfirmed = outcomes[id] { return true }
            return outcomes[id] == nil
        }
    }

    public var result: DeviceErasureResult {
        let failed = notConfirmed
        return failed.isEmpty ? .erased : .notConfirmed(failed)
    }

    public var isErased: Bool { result == .erased }
}

public enum DeviceErasure {
    /// Runs every step in the order given, each erase followed by its read-back. A failure is recorded and the next
    /// step still runs. `required` are the stores the plan must cover (default: all of them); one with no step is
    /// reported `.notInPlan`. Two steps for the same store both have to be confirmed.
    public static func run(
        steps: [DeviceErasureStep], required: Set<DeviceStoreID> = Set(DeviceStoreID.allCases)
    ) async -> DeviceErasureReport {
        var outcomes: [DeviceStoreID: DeviceStoreOutcome] = [:]
        for step in steps {
            let outcome = await run(step)
            if case .notConfirmed = outcomes[step.store] { continue } // The first failure stays the reason.
            outcomes[step.store] = outcome
        }
        for id in required where outcomes[id] == nil {
            outcomes[id] = .notConfirmed(.notInPlan)
        }
        return DeviceErasureReport(outcomes: outcomes, required: required)
    }

    private static func run(_ step: DeviceErasureStep) async -> DeviceStoreOutcome {
        var eraseError: String?
        do {
            try await step.erase()
        } catch {
            eraseError = describe(error)
        }
        do {
            if try await step.verifyEmpty() { return .erased }
            return .notConfirmed(eraseError.map(DeviceErasureFailure.eraseFailed) ?? .notEmpty)
        } catch {
            return .notConfirmed(eraseError.map(DeviceErasureFailure.eraseFailed) ?? .couldNotVerify(describe(error)))
        }
    }

    private static func describe(_ error: any Error) -> String {
        let text = String(describing: error)
        return text.isEmpty ? "unknown error" : text
    }
}
