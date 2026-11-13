import DoddyCore
import SwiftUI

// "Cheapest this week" while it waits and when it has nothing (the look-and-motion pass of 13 Nov 2026). Only states
// the code really has (Brand Guidelines V2.2 p.40, "every state tells the truth"):
//   - Checking: one request is pending (`DealsModel.Phase.checking`). The card names the leaflets the request asked
//     for (`DealsRequest.leafletsAsked`), as plain badges, with the system's own spinner. There is no per-shop
//     progress, no percentage and no count: the server answers once, with every shop at the same time.
//   - Answered: which leaflets the answer says were read, and which weren't (`DealsResult.chainsRead`, `chainsNotRead`).
//   - Nothing found: not one item has an offer, a promotion or a similar product (`DealsResult.foundNothing`). It says
//     so, without alarm, and points to the next step: online shops just below when the code offers them
//     (`ShoppingRoute.onlineNext`; never for groceries), otherwise other words or more shops.

/// Doddy at the top of "Cheapest this week": he inspects, and over an answer with nothing in it he shrugs (the pack's
/// pose for "not found", as on the island; `WholeDoddy_*`, the owner's art). The change is a brief dissolve, which
/// the guide allows under Reduce Motion too (p.31). Hidden with "Hide Doddy's pictures"; the figure is hidden from
/// VoiceOver by `IslandFigureView`.
struct DealsHeroDoddy: View {
    let nothingFound: Bool

    private var pose: IslandPose { nothingFound ? .shrug : .kneelingInspect }

    var body: some View {
        // The ZStack stays while the pose inside it is swapped, so the dissolve has a place to play.
        ZStack(alignment: .bottom) {
            WholeDoddyView(pose: pose, height: 104)
                .id(pose)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.3), value: pose)
    }
}

/// The pending check: what it asked for, and that it takes up to half a minute.
struct LeafletsCheckingCard: View {
    let asked: [DealsChain]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading the leaflets…").font(.headline)
                    Text("This takes up to half a minute.").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            if !asked.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Leaflets asked for").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    ChipFlow(spacing: 6) {
                        ForEach(asked, id: \.rawValue) { chain in
                            ShopBadge(name: chain.name, style: 1)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(String(format: NSLocalizedString("Leaflets asked for: %@", comment: "the chains a pending leaflet check asked for"),
                                                asked.map(\.name).joined(separator: ", "))))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityIdentifier("deals.checking")
    }
}

/// Under "Where to go": the leaflets the answer read, and those it couldn't, in words with an icon each.
struct LeafletsReadLine: View {
    let read: [DealsChain]
    let notRead: [DealsChain]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !read.isEmpty {
                Label {
                    Text(String(format: NSLocalizedString("Leaflets read: %@", comment: "the chains whose leaflets an answer read"),
                                read.map(\.name).joined(separator: ", ")))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.confirmed)
                }
                .foregroundStyle(Theme.ink)
            }
            if !notRead.isEmpty {
                Label {
                    Text(String(format: NSLocalizedString("Not read this time: %@", comment: "the chains whose leaflets an answer couldn't read"),
                                notRead.map(\.name).joined(separator: ", ")))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "minus.circle").foregroundStyle(Theme.secondaryText)
                }
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("deals.read")
    }
}

/// Nothing at all in the leaflets that were read: said plainly, with the next step.
struct NothingFoundCard: View {
    let items: [String]
    /// Online shops are offered just below (`OnlineNextCard`).
    let onlineBelow: Bool
    let chooseShops: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Not in this week's leaflets", systemImage: "newspaper")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(String(format: NSLocalizedString("The leaflets Doddy read have nothing for %@.", comment: "the items of a leaflet check that found nothing"),
                        items.joined(separator: ", ")))
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if onlineBelow {
                Label("Online shops can be searched next, just below.", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Try other words, or more shops.")
                    .font(.subheadline).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: chooseShops) {
                    Label("Choose shops", systemImage: "storefront")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("deals.nothingFound.shops")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityIdentifier("deals.nothingFound")
    }
}
