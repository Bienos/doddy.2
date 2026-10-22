import DoddyCore
import SwiftUI

// Plans (owner, 22 Oct 2026): the paid versions of Doddy are bought on Doddy's website, not through
// the App Store. These two screens, the list and one plan, only describe what each plan includes
// and open the website in the browser. They sell nothing, check no purchase and never say which
// plan the person has (Doddy has no accounts yet: PlanStatus is unknown). They are reached from
// Settings and from Studio, never from the first conversation or the intro.
// Not compiled here (no Xcode): the first Mac build is their first compile.

/// Where the website's plans page is, from this build's configuration. Nothing is hard-coded:
/// with no address set (as in this build) there is no button, and the screen says so.
enum PlansWebsite {
    static var baseAddress: String? { Bundle.main.object(forInfoDictionaryKey: "DoddyPlansURL") as? String }

    /// The language Doddy's screens use, as the website's `lang`.
    static var language: String {
        AppLanguage.matching(Locale.preferredLanguages.first ?? "")?.rawValue ?? AppLanguage.default.rawValue
    }

    static func url(for tier: PlanTier?) -> URL? {
        PlanLink.url(base: baseAddress, tier: tier, language: language)
    }
}

struct PlansView: View {
    var body: some View {
        Form {
            Section {
                Text("Doddy's paid plans are bought on Doddy's website, not in the app. Nothing is bought here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if PlansWebsite.url(for: nil) == nil {
                    Label("The website address isn't set in this build, so the plans can't be opened yet.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                        .accessibilityIdentifier("plans.notConfigured")
                }
            }
            Section {
                ForEach(PlanTier.allCases, id: \.self) { tier in
                    NavigationLink {
                        PlanDetailView(tier: tier)
                    } label: {
                        PlanRow(tier: tier)
                    }
                    .accessibilityIdentifier("plans.row.\(tier.rawValue)")
                }
            } header: {
                Text("Plans")
            } footer: {
                Text("Your own notes and memories are never behind a plan. You can always export, back up and delete them.")
            }
        }
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A plan's name, as a view so each name is one translatable literal.
private struct PlanName: View {
    let tier: PlanTier

    var body: some View {
        switch tier {
        case .free: Text("Free")
        case .plus: Text("Plus")
        case .pro: Text("Pro")
        }
    }
}

private struct PlanDepthText: View {
    let depth: PlanOffer.ResearchDepth

    var body: some View {
        switch depth {
        case .simple: Text("Simple")
        case .balanced: Text("Balanced")
        case .careful: Text("Careful")
        }
    }
}

private struct PlanRow: View {
    let tier: PlanTier

    var body: some View {
        let offer = PlanCatalog.offer(for: tier)
        VStack(alignment: .leading, spacing: 4) {
            PlanName(tier: tier).font(.headline).foregroundStyle(Theme.ink)
            Group {
                switch tier {
                case .free: Text("A taste of Doddy's research, included.")
                case .plus: Text("More research briefs, with better research.")
                case .pro: Text("The most briefs and the most careful research.")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            if let reports = offer.studioReportsPerMonth {
                LabeledContent("Research briefs a month") { Text("\(reports)") }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PlanDetailView: View {
    let tier: PlanTier

    var body: some View {
        let offer = PlanCatalog.offer(for: tier)
        Form {
            Section {
                PlanName(tier: tier).font(.title2.bold()).foregroundStyle(Theme.ink)
            }
            Section("What's included") {
                if let reports = offer.studioReportsPerMonth {
                    LabeledContent("Research briefs a month") { Text("\(reports)") }
                }
                LabeledContent("Research") { PlanDepthText(depth: offer.researchDepth) }
                Text("Each brief comes with an infographic and the sources it used.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Section {
                if tier.isPaid {
                    if let url = PlansWebsite.url(for: tier) {
                        Link(destination: url) {
                            switch tier {
                            case .plus: Label("Get Plus on Doddy's website", systemImage: "safari")
                            default: Label("Get Pro on Doddy's website", systemImage: "safari")
                            }
                        }
                        .accessibilityIdentifier("plans.buy.\(tier.rawValue)")
                    } else {
                        Label("The website address isn't set in this build.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                } else {
                    Text("This plan is included. There is nothing to buy.")
                        .foregroundStyle(Theme.secondaryText)
                }
            } footer: {
                if tier.isPaid {
                    Text("Opens Doddy's website in your browser. You pay there, not in the app. Nothing from the app is sent except which plan you looked at and the app's language.")
                }
            }
        }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}
