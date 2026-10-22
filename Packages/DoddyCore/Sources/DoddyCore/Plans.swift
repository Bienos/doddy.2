import Foundation

// Plans (owner, 22 Oct 2026): the paid versions of Doddy are bought on Doddy's website, not through
// the App Store, so the app only shows what each plan includes and opens the website. Nothing here
// sells anything, checks a purchase or knows which plan the person has: Doddy has no accounts yet,
// so the app never says "your plan is X" (PlanStatus stays unknown until a server answer exists).
//
// The numbers in `PlanCatalog.proposal` are the owner's pricing sketch (docs/implementation/
// PLANS_SCREENS.md), not a decision. Prices are not in the app at all: they live on the website.

/// The tiers. Free runs Studio on the simplest model, Plus on the middle one, Pro on the best one
/// (server side, `STUDIO_TIER`); the app describes this as the quality of the research, not as a
/// model name.
public enum PlanTier: String, CaseIterable, Codable, Sendable, Hashable {
    case free, plus, pro

    /// The paid tiers, the ones the website sells.
    public var isPaid: Bool { self != .free }
}

/// What one tier includes, in the words the screens use (they are localised as `Text` literals in
/// the app; this holds only the facts).
public struct PlanOffer: Equatable, Sendable {
    public let tier: PlanTier
    /// Studio research briefs (with an infographic) a month. Nil means not decided yet.
    public let studioReportsPerMonth: Int?
    /// `simple`, `balanced` or `careful`: how thorough the research is.
    public let researchDepth: ResearchDepth

    public enum ResearchDepth: String, Sendable { case simple, balanced, careful }
}

public enum PlanCatalog {
    /// The owner's sketch of 22 Oct 2026 (2 / 6 / 8 reports a month). Change here, and in the
    /// website, when the owner decides; the tests pin these so a change is deliberate.
    public static let proposal: [PlanOffer] = [
        PlanOffer(tier: .free, studioReportsPerMonth: 2, researchDepth: .simple),
        PlanOffer(tier: .plus, studioReportsPerMonth: 6, researchDepth: .balanced),
        PlanOffer(tier: .pro, studioReportsPerMonth: 8, researchDepth: .careful),
    ]

    public static func offer(for tier: PlanTier) -> PlanOffer {
        proposal.first { $0.tier == tier }!
    }

    /// Kept free for everyone, on every plan: the person's own data is never behind a paywall
    /// (docs/product/V1_SCOPE.md: "export and delete are never paywalled").
    public static let neverLimited = ["export", "delete", "backup"]
}

/// What the app knows about the person's plan. Always `.unknown` until accounts exist and a server
/// answer says otherwise; the screens never show "Your plan" for `.unknown`.
public enum PlanStatus: Equatable, Sendable {
    case unknown
    case known(PlanTier)
}

/// The link the app opens in the browser to buy a plan. It carries only the plan asked about, that
/// it came from the app and the app's language: no account, device or memory data (DOD-11).
public enum PlanLink {
    /// `base` is the website's plans page, from the build's configuration (`DoddyPlansURL` in
    /// Info.plist). Nil unless it is an `https` address with a host and without a login in it, so a
    /// build with no address set has no button rather than a broken one.
    public static func url(base: String?, tier: PlanTier?, language: String) -> URL? {
        guard let base = base?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty,
              var parts = URLComponents(string: base),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil else { return nil }
        var items = (parts.queryItems ?? []).filter { !["plan", "from", "lang"].contains($0.name) }
        if let tier { items.append(URLQueryItem(name: "plan", value: tier.rawValue)) }
        items.append(URLQueryItem(name: "from", value: "app"))
        let code = language.lowercased().filter { $0.isLetter || $0 == "-" }
        if !code.isEmpty, code.count <= 8 { items.append(URLQueryItem(name: "lang", value: code)) }
        parts.queryItems = items
        return parts.url
    }
}
