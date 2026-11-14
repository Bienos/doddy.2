import SwiftUI

// The pieces the redesigned feature screens share (owner, 13 Nov 2026: Trips, On my radar, My city, Food,
// Shopping and Today "w kolorach Dodiego"): an orange hero with Doddy's question and the one field that
// matters, chips for quick answers, cream cards, small tags and section titles. Colours come only from
// `Theme` (Brand Guidelines V2.2, ADR-556): the orange is a surface and a decoration, never text; text on
// it is `Theme.inkOnOrange`. Everything wraps at large text sizes and keeps 44 pt touch targets.

/// The top of a feature screen: an orange card with a big rounded title, an optional line under it, an
/// optional Doddy pose from the owner's pack on the right, and whatever the screen puts inside (a field,
/// chips). Doddy's pose hides with "Hide Doddy's pictures", as everywhere else.
struct DoddyHero<Content: View>: View {
    let title: String
    var subtitle: String?
    var pose: IslandPose?
    @ViewBuilder var content: () -> Content
    @Environment(\.dynamicTypeSize) private var textSize

    /// `title:` and `subtitle:` literals are found by `tools/build_strings_catalog.py` (its NAMED rule).
    init(title: String, subtitle: String? = nil, pose: IslandPose? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.pose = pose
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString(title, comment: ""))
                        .font(.system(.title, design: .rounded, weight: .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(NSLocalizedString(subtitle, comment: ""))
                            .font(.subheadline.weight(.medium))
                            .opacity(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let pose, !textSize.isAccessibilitySize {
                    WholeDoddyView(pose: pose, height: 96)
                        .accessibilityHidden(true)
                }
            }
            content()
        }
        .foregroundStyle(Theme.inkOnOrange)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.orangeCue)
                .overlay(alignment: .topTrailing) {
                    // A quiet ring in the corner, the brand's round shapes; decoration only.
                    Circle()
                        .strokeBorder(Theme.inkOnOrange.opacity(0.08), lineWidth: 18)
                        .frame(width: 160, height: 160)
                        .offset(x: 50, y: -60)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        )
    }
}

extension DoddyHero where Content == EmptyView {
    init(title: String, subtitle: String? = nil, pose: IslandPose? = nil) {
        self.init(title: title, subtitle: subtitle, pose: pose) { EmptyView() }
    }
}

/// The one field on a hero: cream, round, a symbol on the left and a round send button on the right.
/// Dictation is the keyboard's microphone, as in Messages. Pass the placeholder already localized
/// (`NSLocalizedString("…", comment: "")`, so the catalog generator finds it).
struct DoddyAskField: View {
    let placeholder: String
    @Binding var text: String
    var systemImage = "magnifyingglass"
    var isBusy = false
    var identifier: String?
    let submit: () -> Void
    @FocusState private var focused: Bool

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            TextField(NSLocalizedString(placeholder, comment: ""), text: $text, axis: .vertical)
                .lineLimit(1...3)
                .foregroundStyle(Theme.ink)
                .tint(Theme.accentText)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit { if canSend { submit() } }
                .accessibilityIdentifier(identifier ?? "doddy.askField")
            Button {
                focused = false
                submit()
            } label: {
                ZStack {
                    Circle().fill(canSend ? Theme.ink : Theme.ink.opacity(0.25))
                    if isBusy {
                        ProgressView().tint(Theme.canvas)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Theme.canvas)
                    }
                }
                .frame(width: 40, height: 40)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(DoddyTapStyle())
            .disabled(!canSend)
            .accessibilityLabel(Text("Go"))
            .accessibilityIdentifier((identifier ?? "doddy.askField") + ".go")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// A quick answer or a filter. On the orange hero (`onOrange`) it is a light pill; elsewhere cream, and
/// ink when chosen.
struct DoddyChip: View {
    let title: String
    var systemImage: String?
    var isSelected = false
    var onOrange = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.footnote.weight(.semibold)) }
                Text(NSLocalizedString(title, comment: "")).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(DoddyTapStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        if isSelected { return onOrange ? Theme.orangeCue : Theme.canvas }
        return onOrange ? Theme.inkOnOrange : Theme.ink
    }

    private var background: Color {
        if isSelected { return onOrange ? Theme.inkOnOrange : Theme.ink }
        return onOrange ? Theme.canvas.opacity(0.55) : Theme.quietSurface
    }
}

/// A row of chips that scrolls sideways.
struct DoddyChipRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
        }
    }
}

/// A section's title on a redesigned screen: rounded, bold, with an optional action on the right.
struct DoddySectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail {
                Text(verbatim: detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.top, 8)
    }
}

/// A small tag: "Cheapest", "Direct", "AI summary". Accent text on a faint orange, never colour alone.
struct DoddyTag: View {
    let text: String
    var systemImage: String?
    var strong = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(verbatim: text)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(strong ? Theme.inkOnOrange : Theme.accentText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(strong ? Theme.orangeCue : Theme.orangeCue.opacity(0.14), in: Capsule())
    }
}

/// A round symbol tile in Doddy's orange, as in Settings (11 Nov 2026).
struct DoddySymbolTile: View {
    let systemImage: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Theme.inkOnOrange)
            .frame(width: size, height: size)
            .background(Theme.orangeCue, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A short honest line under a section: where the data came from, what Doddy does and doesn't do.
/// Pass the text already localized (`NSLocalizedString("…", comment: "")`).
struct DoddyFootnote: View {
    let text: String
    var systemImage = "info.circle"

    var body: some View {
        Label {
            Text(NSLocalizedString(text, comment: ""))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryText)
    }
}

/// Buttons on the redesigned screens shrink a touch while pressed (as on Home).
struct DoddyTapStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// The ink button of a card: "Book on Kiwi.com", "Open in Wolt".
struct DoddyInkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.canvas)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Theme.ink.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.3), in: Capsule())
            .contentShape(Capsule())
    }
}

/// The quiet button of a card: outlined, ink text.
struct DoddyOutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule().strokeBorder(Theme.separator, lineWidth: 1)
                    .background(configuration.isPressed ? Theme.quietSurface : .clear, in: Capsule()))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

extension View {
    /// A cream card: the surface every result sits on.
    func doddyCard(padding: CGFloat = 16, cornerRadius: CGFloat = 22) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// The canvas behind a redesigned screen, edge to edge, with ink text.
    func doddyScreen() -> some View {
        self
            .foregroundStyle(Theme.ink)
            .background(Theme.canvas.ignoresSafeArea())
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .tint(Theme.accentText)
    }
}
