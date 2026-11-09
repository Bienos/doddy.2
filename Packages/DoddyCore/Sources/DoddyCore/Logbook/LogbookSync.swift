import Foundation

/// Which days the iPhone sends, and when (WEB_LOGBOOK.md, "The daily summary"). A day is sent
/// again until it has been sent once after it ended; today is sent at most once an hour. The
/// server replaces a day it already has, so a retry never counts twice.
public struct LogbookSendState: Codable, Equatable, Sendable {
    /// Days sent after they were over: never sent again. The latest few only.
    public var finishedDays: [String] = []
    /// When today was last sent, and which day "today" was then.
    public var lastTodaySent: Date?
    public var lastTodayDay: String?

    public init() {}
}

public enum LogbookSchedule {
    /// How far back a missed day is still sent: as far as the iPhone keeps what it counts.
    public static let lookBackDays = 7
    /// Today is sent again after this long.
    public static let todayInterval: TimeInterval = 3_600
    private static let keptFinished = 40

    /// The days to send now, oldest first: every recent day not yet sent after it ended, then
    /// today if it hasn't been sent within the hour.
    public static func daysToSend(now: Date, state: LogbookSendState, calendar: Calendar) -> [String] {
        let today = LogbookCalendar.dayKey(now, calendar: calendar)
        var days: [String] = []
        for back in stride(from: lookBackDays, through: 1, by: -1) {
            let day = LogbookCalendar.dayKey(now, daysBefore: back, calendar: calendar)
            if !state.finishedDays.contains(day) { days.append(day) }
        }
        let todayIsStale = state.lastTodayDay != today
            || (state.lastTodaySent.map { now.timeIntervalSince($0) >= todayInterval || $0 > now } ?? true)
        if todayIsStale { days.append(today) }
        return days
    }

    /// Remembers that `day` reached the server at `now`.
    public static func recordSent(_ day: String, at now: Date, state: inout LogbookSendState, calendar: Calendar) {
        let today = LogbookCalendar.dayKey(now, calendar: calendar)
        if day < today {
            if !state.finishedDays.contains(day) { state.finishedDays.append(day) }
            state.finishedDays = Array(state.finishedDays.sorted().suffix(keptFinished))
        } else if day == today {
            state.lastTodaySent = now
            state.lastTodayDay = today
        }
    }
}

public enum LogbookError: Error, Equatable, Sendable {
    /// This build has no server, or the iPhone has no session with it.
    case notConfigured
    case unauthenticated
    /// Logbook is off on the server for this account: it stores nothing.
    case off
    case transport
    case unreadable
    case rateLimited
    /// The server isn't set up for this (a guest iPhone, or a server without the web workspace).
    case notSetUp
    /// The server refused it; its own words, which never repeat a value that was sent.
    case refused(String)
}

/// Doddy's server, as Logbook uses it (`backend/src/web/routes.ts`, Logbook routes).
public protocol LogbookClient: Sendable {
    /// Turns Logbook on or off for this account. Off deletes every stored day; returns how many went.
    func setEnabled(_ enabled: Bool) async throws(LogbookError) -> Int
    /// Sends one day. The server replaces the day if it already has it.
    func putDay(_ day: LogbookDay) async throws(LogbookError)
    /// Deletes every stored day and keeps Logbook on or off as it was. Returns how many went.
    func deleteAll() async throws(LogbookError) -> Int
}

public struct BackendLogbookClient: LogbookClient {
    private let baseURL: URL
    private let sessionToken: @Sendable () -> String?
    private let transport: any HTTPTransport

    /// `baseURL` must be https, or http on a loopback host for local development.
    public init?(baseURL: URL, sessionToken: @escaping @Sendable () -> String?, transport: any HTTPTransport) {
        guard BackendConnectedAppsClient.isAllowed(baseURL) else { return nil }
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.transport = transport
    }

    /// Same, with a token that is sent only to the server it was issued for.
    public init?(baseURL: URL, boundToken: @escaping @Sendable () -> BoundSessionToken?, transport: any HTTPTransport) {
        self.init(baseURL: baseURL, sessionToken: { boundToken()?.token(for: baseURL) }, transport: transport)
    }

    public func setEnabled(_ enabled: Bool) async throws(LogbookError) -> Int {
        let body = try Self.json(StateBody(enabled: enabled))
        let reply: StateReply = try await call("PUT", "v1/web/logbook/state", body: body)
        guard reply.enabled == enabled else { throw .unreadable }
        return reply.deletedDays ?? 0
    }

    public func putDay(_ day: LogbookDay) async throws(LogbookError) {
        guard LogbookCalendar.isCalendarDay(day.day) else { throw .refused("The day isn't a calendar day.") }
        let body: Data
        do { body = try day.encoded() } catch { throw .unreadable }
        let reply: StoredReply = try await call("PUT", "v1/web/logbook/days/\(day.day)", body: body)
        guard reply.stored, reply.day == day.day else { throw .unreadable }
    }

    public func deleteAll() async throws(LogbookError) -> Int {
        let reply: DeletedReply = try await call("DELETE", "v1/web/logbook", body: nil)
        return reply.deletedDays
    }

    private struct StateBody: Encodable { let enabled: Bool }
    struct StateReply: Decodable { let enabled: Bool; let deletedDays: Int? }
    struct StoredReply: Decodable { let stored: Bool; let day: String }
    struct DeletedReply: Decodable { let deletedDays: Int }

    private static func json<Body: Encodable>(_ body: Body) throws(LogbookError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do { return try encoder.encode(body) } catch { throw .unreadable }
    }

    private func call<Response: Decodable>(_ method: String, _ path: String, body: Data?) async throws(LogbookError) -> Response {
        guard let token = sessionToken(), !token.isEmpty else { throw .notConfigured }
        var headers = ["authorization": "Bearer \(token)", "accept": "application/json"]
        if body != nil { headers["content-type"] = "application/json" }
        let request = HTTPRequest(method: method, url: baseURL.appendingPathComponent(path), headers: headers, body: body)
        let status: Int
        let payload: Data
        do {
            (status, payload) = try await transport.send(request)
        } catch {
            throw .transport
        }
        return try Self.decode(status: status, data: payload)
    }

    static func decode<Response: Decodable>(status: Int, data: Data) throws(LogbookError) -> Response {
        if (200..<300).contains(status) {
            do { return try JSONDecoder().decode(Response.self, from: data) } catch { throw .unreadable }
        }
        if status == 401 { throw .unauthenticated }
        guard let body = try? JSONDecoder().decode(OnlineErrorBody.self, from: data) else { throw .unreadable }
        if status == 429 || body.error.code == "rate_limited" { throw .rateLimited }
        if status == 403 && body.error.code == "capability_disabled" { throw .off }
        if status == 503 && body.error.code == "live_not_configured" { throw .notSetUp }
        throw .refused(body.error.message)
    }
}

/// Sends what is due: the days the schedule names, each built from the iPhone's records. Stops at
/// the first failure and leaves that day for next time; a day counts as sent only after the server
/// said it stored it.
public enum LogbookUpload {
    public struct Result: Equatable, Sendable {
        public var sent: [String] = []
        public var failure: LogbookError?
    }

    public static func run(
        client: any LogbookClient, sources: LogbookSources, state: inout LogbookSendState,
        now: Date, calendar: Calendar, toolNames: Set<String> = LogbookBuilder.toolNames
    ) async -> Result {
        var result = Result()
        for dayKey in LogbookSchedule.daysToSend(now: now, state: state, calendar: calendar) {
            let day = LogbookBuilder.day(dayKey, from: sources, calendar: calendar, toolNames: toolNames)
            // A day the server would refuse is not sent; it would be refused whole anyway.
            guard day.problems(toolNames: toolNames).isEmpty else { continue }
            do throws(LogbookError) {
                try await client.putDay(day)
                LogbookSchedule.recordSent(dayKey, at: now, state: &state, calendar: calendar)
                result.sent.append(dayKey)
            } catch {
                result.failure = error
                return result
            }
        }
        return result
    }
}
