import SwiftUI

// Doddy's screen kit (owner, 13 Nov 2026: "w kolorach Dodiego, a nie w tym, co jest teraz"). The pieces the
// redesigned Trips, On my radar, My city, Food, Shopping and Today screens share, so they read as one app:
// cream canvas, ink text, warm quiet cards, and the brand orange as the accent.
//
// Colour rules (DoddyDesignTokens, brand V2.2): orange is a fill and a decoration, never text on the canvas.
// Words and icons drawn ON the orange use `Theme.inkOnOrange` (6.4:1, the same as Messages' bubbles).
// Every string parameter is named `title:`, `subtitle:` or `eyebrow:` and typed `LocalizedStringKey`, so a
// literal at the call site is collected into the string catalog (tools/build_strings_catalog.py, NAMED) and
// looked up when shown. Text that is data (a city, a price) goes in with `Text(verbatim:)` through the
// view-builder variants.

/// A scrolling page on Doddy's canvas.
struct DoddyPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }
}

/// The big heading at the top of a page: a small eyebrow, the title with the orange underline, a line under it,
/// and optionally one of Doddy's poses on the right (hidden with "Hide Doddy's pictures").
struct DoddyPageHeader: View {
    var eyebrow: LocalizedStringKey?
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var pose: IslandPose?

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if let eyebrow {
                    Text(eyebrow).textCase(.uppercase)
                        .font(.caption2.weight(.semibold)).tracking(1.2)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .background(alignment: .bottomLeading) {
                        Capsule().fill(Theme.orangeCue).frame(width: 44, height: 5).offset(y: 6)
                            .accessibilityHidden(true)
                    }
                    .padding(.bottom, 6)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let pose {
                WholeDoddyView(pose: pose, height: 96).accessibilityHidden(true)
            }
        }
    }
}

/// A section title inside a page, with an optional trailing control.
struct DoddySectionTitle<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 4)
    }
}

extension DoddySectionTitle where Trailing == EmptyView {
    init(title: LocalizedStringKey) {
        self.title = title
        self.trailing = EmptyView()
    }
}

extension View {
    /// A warm card: Doddy's quiet surface, rounded, with room inside.
    func doddyCard(padding: CGFloat = 16, accent: Bool = false) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .leading) {
                if accent {
                    UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, style: .continuous)
                        .fill(Theme.orangeCue)
                        .frame(width: 6)
                        .accessibilityHidden(true)
                }
            }
    }

    /// A field on the canvas: rounded, with the separator line, big enough to tap.
    func doddyField() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1) }
    }
}

/// An icon on an orange disc (decoration; the glyph is drawn in the ink that reads on orange).
struct DoddyIconBadge: View {
    let systemName: String
    var size: CGFloat = 40
    var filled = true

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(filled ? Theme.inkOnOrange : Theme.ink)
            .frame(width: size, height: size)
            .background(filled ? Theme.orangeCue : Theme.canvas, in: Circle())
            .overlay { if !filled { Circle().strokeBorder(Theme.separator, lineWidth: 1) } }
            .accessibilityHidden(true)
    }
}

/// The main call to action in Doddy's colours: orange, ink words.
struct DoddyAccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.inkOnOrange)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.orangeCue.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A choice in a row of choices (cities, categories, filters). Selected: ink fill; otherwise an outline.
struct DoddyChip: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.footnote.weight(.semibold)) }
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.canvas : Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(isSelected ? Theme.ink : Theme.canvas, in: Capsule())
            .overlay { if !isSelected { Capsule().strokeBorder(Theme.separator, lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row that opens something: icon, title, a line under it, and an arrow.
struct DoddyLinkRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var external = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                DoddyIconBadge(systemName: systemImage, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: external ? "arrow.up.right" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .doddyCard(padding: 14)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

/// A short notice inside a page: information, or a problem (error colour, with its own icon so colour is never
/// the only signal).
struct DoddyNotice: View {
    let text: Text
    var isProblem = false

    var body: some View {
        Label { text.font(.subheadline) } icon: {
            Image(systemName: isProblem ? "exclamationmark.triangle.fill" : "info.circle")
        }
        .foregroundStyle(isProblem ? Theme.error : Theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.quietSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The small print at the bottom of a page: what leaves the iPhone, where data comes from.
struct DoddyFinePrint: View {
    let text: Text

    var body: some View {
        text
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
