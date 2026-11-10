import Foundation

/// A voice token fetched before the person asks to talk (owner, 10 Nov 2026: "bilet do rozmowy z
/// wyprzedzeniem"), so pressing Talk or the Action Button only has to connect. Decision
/// `2026-11-10-voice-token-ahead`.
///
/// The rules, kept here so they are tested on Linux:
/// - A token is used at most once, only by the same account it was fetched for and only for the
///   same token server, and only while it is young (`maxAge`). ElevenLabs doesn't publish how long a
///   conversation token lives; its signed URLs live 15 minutes, so a few minutes is well inside.
/// - Fetching ahead costs the same as a start: the token server counts every token (30 an hour and
///   150 a day per person, 100 an hour for everyone). So it fetches ahead only when nothing usable is
///   held, and after a token went unused it waits `idleCooldown` before fetching ahead again.
/// - A token that fails to connect is never retried: the start fetches a fresh one (the app's job).
public struct VoiceTokenShelf: Equatable, Sendable {
    public static let maxAge: TimeInterval = 4 * 60
    public static let idleCooldown: TimeInterval = 15 * 60

    struct Held: Equatable, Sendable {
        let token: String
        let endpoint: URL
        let owner: String
        let fetchedAt: Date
    }

    private(set) var held: Held?
    /// When the last fetch ahead was asked for, and whether what it brought was used.
    private(set) var lastWarmAt: Date?
    private(set) var lastWarmUsed = true

    public init() {}

    /// Whether to fetch a token ahead now. `owner` names the signed-in account (any stable id; never
    /// sent anywhere); nil means nobody is signed in, and nothing is fetched.
    public func shouldWarm(endpoint: URL, owner: String?, now: Date) -> Bool {
        guard let owner, !owner.isEmpty else { return false }
        if let held, held.endpoint == endpoint, held.owner == owner, now.timeIntervalSince(held.fetchedAt) < Self.maxAge {
            return false
        }
        guard let lastWarmAt else { return true }
        if lastWarmUsed { return true }
        return now.timeIntervalSince(lastWarmAt) >= Self.idleCooldown
    }

    /// Notes that a fetch ahead started, before its answer, so two triggers don't both fetch.
    public mutating func warmStarted(now: Date) {
        lastWarmAt = now
        lastWarmUsed = false
        held = nil
    }

    /// Keeps the token a fetch ahead brought. A failed fetch keeps nothing.
    public mutating func store(_ token: String, endpoint: URL, owner: String, fetchedAt: Date) {
        guard !token.isEmpty, !owner.isEmpty else { return }
        held = Held(token: token, endpoint: endpoint, owner: owner, fetchedAt: fetchedAt)
    }

    /// The held token, if it is still good for this start, and it is gone from the shelf either way
    /// once taken. A token for another account or server, or too old, is thrown away and nil returned.
    public mutating func take(endpoint: URL, owner: String?, now: Date) -> String? {
        guard let current = held else { return nil }
        held = nil
        guard let owner, current.owner == owner, current.endpoint == endpoint,
              now.timeIntervalSince(current.fetchedAt) >= 0,
              now.timeIntervalSince(current.fetchedAt) < Self.maxAge else { return nil }
        lastWarmUsed = true
        return current.token
    }

    /// Sign-out, account change, Pause all or the voice consent withdrawn: nothing held survives.
    public mutating func clear() {
        held = nil
    }

    /// Whether a token is on the shelf (for tests and the log; says nothing about its value).
    public var isHolding: Bool { held != nil }
}
