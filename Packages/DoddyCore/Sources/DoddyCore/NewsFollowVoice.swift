import Foundation

// "Śledź CPK" by voice (ADR-657; owner, 28 Oct 2026: "Ma umieć tak"). One tool, follow_news, that
// adds a follow to Following (ADR-656) on this iPhone. ASK-01: a change, so a card and a tap; the
// follow is written only after the tap and said only once it is read back from the list. Doddy's
// own feature on this iPhone, no other app or account, so it sits outside Pause all, like the
// stopwatch. What the voice hears back is the follow's name, never a story.
//
// Platforms: iPhone and iPad.

extension VoiceToolName {
    public static let followNews = "follow_news"
}

/// What the person asked to follow, before the screen's language gives a topic its name.
public enum NewsFollowAsk: Equatable, Sendable {
    /// A topic from the server's news catalog, by id.
    case topic(id: String)
    /// The person's own words: a name and the keywords to look for.
    case words(name: String, keywords: [String])

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
        }
    }

    /// The card's lines: what will be followed and where it shows.
    public var cardLines: [String] {
        switch self {
        case .topic(let id):
            return ["Topic: \(Self.topicName(id, polish: false) ?? id)", "Stories show in Following, in Home's menu"]
        case .words(let name, let keywords):
            return ["“\(name)”", "Stories with: \(keywords.joined(separator: ", "))", "Shown in Following, in Home's menu"]
        }
    }

    /// The name the activity log and the voice reply use.
    public var name: String {
        switch self {
        case .topic(let id): Self.topicName(id, polish: false) ?? id
        case .words(let name, _): name
        }
    }

    /// From the model's arguments: `topic` (a catalog id) wins; otherwise `name` and `words`. Words
    /// left out mean the name itself is the word to look for ("śledź CPK" → CPK). Anything the
    /// server would refuse is refused here, so a card never offers what can't be kept.
    static func parse(topic: String?, name: String?, words: [String]?) -> Result<NewsFollowAsk, NewsFollowRefusal> {
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
    public static func newsFollow(_ outcome: NewsFollowOutcome) -> String {
        switch outcome {
        case .added(let follow):
            "added: now following this in Following (Home's menu, then Following). Its stories show there; nothing is sent to the user. Name:\n"
                + ToolData.block([quoted("Name", follow.label)])
        case .alreadyFollowing(let follow):
            "failed: the user already follows this. Nothing changed. Name:\n" + ToolData.block([quoted("Name", follow.label)])
        case .full:
            "failed: the user already follows \(NewsFollowList.maxFollows) things, the most there can be. Nothing was added. They can remove one in Following, Edit."
        case .notKept:
            "failed: the follow couldn't be kept on this iPhone. Nothing was added. Say so in one short sentence."
        }
    }
}
