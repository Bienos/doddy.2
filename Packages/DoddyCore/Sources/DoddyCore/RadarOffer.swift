import Foundation

// What On my radar offers about "tell me when", from what Doddy's server last said (owner's review, 12 Nov 2026,
// docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md section 6: "Alerty są wyłączone na serwerze, a przycisk „Daj znać…”
// i tak jest widoczny i oferuje tylko „Tylko tutaj”"). Decision 2026-11-13-radar-fixes.
//
// The rule: an alert Doddy's server would check is offered only when the server's own answer said it checks follows
// (`GET /v1/news/radar` → `available`). No answer is not a yes. What the person already set (flag words, or a check the
// server once took) can still be changed, so nothing is left that can't be turned off.
//
// Platforms: iPhone and iPad.

/// Whether Doddy's server checks follows, as its last answer said.
public enum RadarAlertsAvailability: Equatable, Sendable {
    /// No answer yet, or none could be had. Nothing that needs the server is offered.
    case unknown
    /// The server said it doesn't check follows for anyone (`RADAR_ALERTS_ENABLED` off).
    case off
    /// The server said it checks follows.
    case on

    public init(_ state: RadarServerState?) {
        guard let state else {
            self = .unknown
            return
        }
        self = state.available ? .on : .off
    }
}

public enum RadarTellMe {
    /// "Tell me…" under a follow: when the server said it checks follows, or when the follow already has something to
    /// change (its flag words, or a server check kept on this iPhone that can be turned off). Otherwise it would open a
    /// sheet whose only choice is "Here only".
    public static func showsButton(_ availability: RadarAlertsAvailability, alert: RadarAlert) -> Bool {
        availability == .on || !alert.words.isEmpty || alert.serverChecks
    }

    /// The add sheet's "tell me when" part, and the three ways with the server switch in a follow's own sheet: only when
    /// the server said it checks follows.
    public static func offersServerChecks(_ availability: RadarAlertsAvailability) -> Bool {
        availability == .on
    }

    /// How an alert is kept when it is saved now. Once the server said it checks nothing, only here. With no answer the
    /// way of telling is left as it was set (the sheet hides its controls, so only the words change) and the server's
    /// answer to the save decides, as `FollowingModel.apply` always did; nothing is turned off by a missing answer.
    public static func kept(_ alert: RadarAlert, _ availability: RadarAlertsAvailability) -> RadarAlert {
        guard alert.serverChecks, availability == .off else { return alert }
        return RadarAlert(followID: alert.followID, words: alert.words, how: .app, dailyTime: alert.dailyTime)
    }

    /// The line under a follow's name, or nil when it would only say "Shown here only" with nothing else to choose.
    /// A check the server once took is said to be off once the server says it checks nothing; with no answer, the
    /// line is what the server confirmed when the check was saved (`FollowingModel.apply` keeps nothing else).
    public static func line(_ alert: RadarAlert, _ availability: RadarAlertsAvailability, polish: Bool) -> String? {
        guard showsButton(availability, alert: alert) else { return nil }
        if availability == .off && alert.serverChecks {
            let hereOnly = RadarAlert(followID: alert.followID, words: alert.words, how: .app, dailyTime: alert.dailyTime)
            return hereOnly.summary(polish: polish)
        }
        return alert.summary(polish: polish)
    }

    /// Why a sheet offers only "here", in the sheet's footer, or nil when it offers all three ways.
    public static func hereOnlyReason(_ availability: RadarAlertsAvailability) -> HereOnlyReason? {
        switch availability {
        case .on: nil
        case .off: .serverDoesNotCheck
        case .unknown: .noAnswer
        }
    }

    public enum HereOnlyReason: Equatable, Sendable {
        /// The server said it checks nobody's follows yet: saving keeps the alert here only.
        case serverDoesNotCheck
        /// The server hasn't answered (yet): only the words can be changed now.
        case noAnswer
    }
}
