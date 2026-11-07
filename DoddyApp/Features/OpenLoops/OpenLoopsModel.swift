import DoddyCore
import Foundation
import Observation

/// The "Na oku" page's state (ADR-756), without the views, so it is type-checked and tested on Linux. It
/// stores nothing and sends nothing: it asks a source provider for what the app already holds, builds the
/// list with `OpenLoopsBuilder`, and keeps the last list for the screen. The provider is the only place
/// that reads the stores (Calendar, Reminders, tasks, watches, parcels, reminders on notes) and it decides
/// what each source may show: a private note's words come back as `.hidden`, and a source it could not
/// read comes back in `unavailable`.
@MainActor
@Observable
final class OpenLoopsModel {
    enum Phase: Equatable {
        /// Nothing has been read yet. The screen shows a progress view, not "nothing waiting".
        case loading
        case ready(OpenLoopsAgenda)
    }

    typealias Provider = @MainActor () async -> OpenLoopsInput

    private(set) var phase: Phase = .loading
    /// Reading is in progress now (the first load or a refresh).
    private(set) var isRefreshing = false
    /// When the list on screen was built.
    private(set) var refreshedAt: Date?

    private let provider: Provider
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let limitPerSection: Int
    private var pending = false

    init(provider: @escaping Provider, now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current,
         limitPerSection: Int = OpenLoopsAgenda.defaultLimit) {
        self.provider = provider
        self.now = now
        self.calendar = calendar
        self.limitPerSection = limitPerSection
    }

    var agenda: OpenLoopsAgenda? {
        if case .ready(let agenda) = phase { return agenda }
        return nil
    }

    /// Reads every source again. One read at a time: a call made while another runs is folded into one more
    /// read after it, so the list never shows the older of two overlapping reads.
    func refresh() async {
        if isRefreshing {
            pending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            pending = false
            let input = await provider()
            guard !Task.isCancelled else { return }
            let at = now()
            phase = .ready(OpenLoopsBuilder.build(input, now: at, calendar: calendar, limitPerSection: limitPerSection))
            refreshedAt = at
        } while pending
    }
}
