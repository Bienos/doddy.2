import Foundation

// "Śledź CPK" by voice (ADR-657; owner, 28 Oct 2026: "Ma umieć tak"). One tool, follow_news, that
// adds a follow to On my radar (ADR-656; named Following until 10 Nov 2026) on this iPhone. ASK-01: a change, so a card and a tap; the
// follow is written only after the tap and said only once it is read back from the list. Doddy's
// own feature on this iPhone, no other app or account, so it sits outside Pause all, like the
// stopwatch. What the voice hears back is the follow's name, never a story.
//
// Platforms: iPhone and iPad.

extension VoiceToolName {
    public static let followNews = "follow_news"
}

/// On my radar as the app names it (Polish "Na radarze"; "Following" / "Śledzone" until 10 Nov 2026) and where it is.
public enum RadarScreen {
    public static func name(polish: Bool) -> String { polish ? "Na radarze" : "On my radar" }

    /// "On my radar (Home › •••)" / "„Na radarze” (ekran główny › •••)".
    public static func whereItIs(polish: Bool) -> String {
        polish ? "„Na radarze” (ekran główny › •••)" : "On my radar (Home › •••)"
    }
}

/// What the person asked to follow, before the screen's language gives a topic its name.
public indirect enum NewsFollowAsk: Equatable, Sendable {
    /// A topic from the server's news catalog, by id.
    case topic(id: String)
    /// The person's own words: a name and the keywords to look for.
    case words(name: String, keywords: [String])
    /// The same follow with an alert the person asked for in the same breath ("tell me when CPK has news about
    /// the airport"). The alert is the same one the radar sheet keeps; nothing is checked until it is kept.
    case alerting(NewsFollowAsk, NewsFollowAlertAsk)

    /// The follow without any alert.
    public var base: NewsFollowAsk {
        if case .alerting(let inner, _) = self { return inner.base }
        return self
    }

    /// The alert asked for, if any.
    public var alertAsk: NewsFollowAlertAsk? {
        if case .alerting(_, let alert) = self { return alert }
        return nil
    }

    /// The ids of the server's news catalog (server/messaging/src/news/catalog.ts) with their names.
    /// A test keeps the two lists in step.
    public static let catalog: [(id: String, en: String, pl: String)] = [
        ("world", "World", "Świat"),
        ("poland", "What's happening in Poland", "Co się dzieje w Polsce"),
        ("europe", "Europe", "Europa"),
        ("technology", "Technology", "Technologia"),
        ("ai", "AI", "Sztuczna inteligencja"),
        ("business", "Business & markets", "Biznes i rynki"),
        ("science", "Science", "Nauka"),
        ("health", "Health", "Zdrowie"),
        ("sport", "Sport", "Sport"),
        ("crypto", "Crypto", "Kryptowaluty"),
    ]

    public static func topicName(_ id: String, polish: Bool) -> String? {
        catalog.first { $0.id == id }.map { polish ? $0.pl : $0.en }
    }

    /// The follow as it is kept. Poland keeps the default follow's own name, so asking for it again
    /// is recognised as the same follow.
    public func follow(polish: Bool) -> NewsFollow {
        switch self {
        case .topic(let id): .topic(id: id, label: Self.topicName(id, polish: polish) ?? id)
        case .words(let name, let keywords): .words(label: name, keywords: keywords)
        case .alerting(let inner, _): inner.follow(polish: polish)
        }
    }

    /// The card's lines: what will be followed and where it shows.
    public var cardLines: [String] { cardLines(polish: false) }

    /// `polish`: the app is shown in Polish.
    public func cardLines(polish: Bool) -> [String] {
        switch (self, polish) {
        case (.alerting(let inner, let alert), _):
            let alertLine = RadarAlert(followID: "", words: alert.words, how: alert.how, dailyTime: alert.dailyTime).summary(polish: polish)
            return inner.cardLines(polish: polish) + [alertLine]
        case (.topic(let id), false):
            return ["Topic: \(Self.topicName(id, polish: false) ?? id)", "Stories show in \(RadarScreen.whereItIs(polish: false))"]
        case (.topic(let id), true):
            return ["Temat: \(Self.topicName(id, polish: true) ?? id)", "Artykuły pojawią się w \(RadarScreen.whereItIs(polish: true))"]
        case (.words(let name, let keywords), false):
            return ["“\(name)”", "Stories with: \(keywords.joined(separator: ", "))", "Shown in \(RadarScreen.whereItIs(polish: false))"]
        case (.words(let name, let keywords), true):
            return ["„\(name)”", "Artykuły ze słowami: \(keywords.joined(separator: ", "))", "W \(RadarScreen.whereItIs(polish: true))"]
        }
    }

    /// The name the activity log and the voice reply use.
    public var name: String {
        switch self {
        case .topic(let id): Self.topicName(id, polish: false) ?? id
        case .words(let name, _): name
        case .alerting(let inner, _): inner.name
        }
    }

    /// From the model's arguments: `topic` (a catalog id) wins; otherwise `name` and `words`. Words
    /// left out mean the name itself is the word to look for ("śledź CPK" → CPK). Anything the
    /// server would refuse is refused here, so a card never offers what can't be kept.
    static func parse(
        topic: String?, name: String?, words: [String]?,
        alertWords: [String]? = nil, tellMe: String? = nil, dailyTime: String? = nil
    ) -> Result<NewsFollowAsk, NewsFollowRefusal> {
        let base = parseBase(topic: topic, name: name, words: words)
        guard case .success(let ask) = base else { return base }
        let wantsAlert = !(alertWords ?? []).isEmpty || tellMe != nil || dailyTime != nil
        guard wantsAlert else { return base }
        switch NewsFollowAlertAsk.parse(alertWords: alertWords, tellMe: tellMe, dailyTime: dailyTime, for: ask.follow(polish: false)) {
        case .success(let alert): return .success(.alerting(ask, alert))
        case .failure(let refusal): return .failure(refusal)
        }
    }

    private static func parseBase(topic: String?, name: String?, words: [String]?) -> Result<NewsFollowAsk, NewsFollowRefusal> {
        if let topic {
            let id = topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard catalog.contains(where: { $0.id == id }) else { return .failure(NewsFollowRefusal(reason: "unknown topic \(id)")) }
            return .success(.topic(id: id))
        }
        guard let name else { return .failure(NewsFollowRefusal(reason: "missing name or topic")) }
        let given = (words ?? []).joined(separator: ",")
        guard let follow = NewsFollowList.words(name: name, keywordsText: given.isEmpty ? name : given),
              case .words(let label, let keywords) = follow
        else { return .failure(NewsFollowRefusal(reason: "name must be 1 to 60 characters and words 2 to 40 characters each")) }
        return .success(.words(name: label, keywords: keywords))
    }
}

/// An alert asked for by voice with a follow. The words, how to be told and the daily time are the radar sheet's own
/// (`RadarAlert`); a combination the sheet would refuse is refused here, so a card never offers what can't be kept.
public struct NewsFollowAlertAsk: Equatable, Sendable {
    public let words: [String]
    public let how: RadarHow
    public let dailyTime: String

    public func alert(followID: String) -> RadarAlert {
        RadarAlert(followID: followID, words: words, how: how, dailyTime: dailyTime)
    }

    /// `tell_me`: "instant" (as it happens), "daily" (one summary a day) or "app" (flag in the feed only). Without it,
    /// words mean "as it happens" and a time alone means "daily".
    static func parse(alertWords: [String]?, tellMe: String?, dailyTime: String?, for follow: NewsFollow) -> Result<NewsFollowAlertAsk, NewsFollowRefusal> {
        var words: [String] = []
        for raw in alertWords ?? [] {
            let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...40).contains(word.count) else {
                return .failure(NewsFollowRefusal(reason: "alert words must be 2 to 40 characters each"))
            }
            if !words.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) { words.append(word) }
        }
        guard words.count <= 10 else { return .failure(NewsFollowRefusal(reason: "at most 10 alert words")) }
        let how: RadarHow
        switch tellMe?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "instant"?: how = .instant
        case "daily"?: how = .daily
        case "app"?: how = .app
        case nil: how = dailyTime != nil && words.isEmpty ? .daily : (words.isEmpty ? .app : .instant)
        default: return .failure(NewsFollowRefusal(reason: "tell_me must be instant, daily or app"))
        }
        let alert = NewsFollowAlertAsk(words: words, how: how, dailyTime: (dailyTime ?? "18:00").trimmingCharacters(in: .whitespaces))
        switch alert.alert(followID: follow.id).problem(for: follow) {
        case .wordsNeeded?: return .failure(NewsFollowRefusal(reason: "an alert as it happens needs alert_words to look for"))
        case .timeNeeded?: return .failure(NewsFollowRefusal(reason: "daily_time must be HH:MM, 24-hour"))
        case nil: return .success(alert)
        }
    }
}

/// How an alert asked for by voice ended, read back from what is kept (never assumed).
public enum NewsFollowAlertResult: Equatable, Sendable {
    /// Kept as asked. For a server check, Doddy's server lists it.
    case kept(RadarAlert)
    /// The follow is kept but the alert shows on this iPhone only, and why.
    case hereOnly(reason: String)
}

/// Why the model's arguments can't make a follow; the agent hears the reason as `invalid`.
public struct NewsFollowRefusal: Error, Equatable, Sendable {
    public let reason: String
}

/// How adding a follow ended, read back from the list after the tap.
public enum NewsFollowOutcome: Equatable, Sendable {
    case added(NewsFollow)
    case alreadyFollowing(NewsFollow)
    case full
    /// Added, but the read-back didn't find it (a failed write). Never said as followed.
    case notKept

    /// Applies the ask to the list and reports only what the list then says.
    public static func apply(_ follow: NewsFollow, to list: inout NewsFollowList) -> NewsFollowOutcome {
        if list.follows.contains(where: { $0.id == follow.id }) { return .alreadyFollowing(follow) }
        if list.isFull { return .full }
        list.add(follow)
        return list.follows.contains(where: { $0.id == follow.id }) ? .added(follow) : .notKept
    }
}

extension VoiceToolReply {
    /// The follow's result plus, when an alert was asked for, what the alert ended as.
    public static func newsFollow(_ outcome: NewsFollowOutcome, alert: NewsFollowAlertResult?) -> String {
        let base = newsFollow(outcome)
        guard let alert else { return base }
        switch (outcome, alert) {
        case (.added, .kept(let kept)), (.alreadyFollowing, .kept(let kept)):
            let how: String
            switch kept.how {
            case .instant: how = "Doddy's server checks and sends a notification when a story mentions the words"
            case .daily: how = "Doddy's server sends one summary a day at \(kept.dailyTime)"
            case .app: how = "stories that mention the words get a flag on On my radar; no notification is sent"
            }
            return base + "\nalert kept: " + how + ". Never promise a time or a story."
        case (.added, .hereOnly(let reason)), (.alreadyFollowing, .hereOnly(let reason)):
            return base + "\nalert not on the server: it shows on On my radar on this iPhone only (" + reason + "). Say so in one short sentence; never say it will notify."
        default:
            return base
        }
    }

    /// Where the screen is, for the voice. The app shows it as "On my radar", in Polish "Na radarze" (it was "Following"
    /// until 10 Nov 2026), so the agent names it as the person sees it in either language.
    static let radarForVoice = "the On my radar screen (in Polish \"Na radarze\"; Home, the ••• menu, then On my radar)"

    public static func newsFollow(_ outcome: NewsFollowOutcome) -> String {
        switch outcome {
        case .added(let follow):
            // The next step is said, not done (owner's review, 12 Nov 2026): no voice tool opens a screen, so Doddy says
            // where to look and never that he opened it.
            "added: now on the user's radar, kept on this iPhone. Its stories show on \(radarForVoice); nothing is sent to the user. "
                + "Next step to offer in the same short sentence: they can look there now. Never promise a story; you can't open the screen for them, so never say you did. Name:\n"
                + ToolData.block([quoted("Name", follow.label)])
        case .alreadyFollowing(let follow):
            "failed: the user already follows this on \(radarForVoice). Nothing changed. Name:\n" + ToolData.block([quoted("Name", follow.label)])
        case .full:
            "failed: the user already follows \(NewsFollowList.maxFollows) things, the most there can be. Nothing was added. They can remove one on \(radarForVoice), with Edit."
        case .notKept:
            "failed: the follow couldn't be kept on this iPhone. Nothing was added. Say so in one short sentence."
        }
    }
}
