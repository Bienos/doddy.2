import DoddyCore
import SwiftUI

enum MemoryModal: String, Identifiable {
    case capture
    var id: String { rawValue }
}

enum MemoryNavigationRoute: Hashable {
    /// `query` pre-fills the search (the "Find in Doddy" shortcut); empty otherwise.
    case find(query: String)
    case note(UUID)
}

/// The guide's logo: "Doddy" in Caveat Bold, Brand Guidelines V2.2 p.18 option C (ADR-562). A vector
/// template cut from the guide's own glyphs (tools/brand/extract_wordmark.py), so no font ships; it
/// takes the ink colour, paper on night in dark appearance. Grows with Dynamic Type up to xxLarge's
/// size, as the old text did.
struct DoddyWordmark: View {
    @ScaledMetric(relativeTo: .title) private var height: CGFloat = 34

    var body: some View {
        Image("DoddyWordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: min(height, 42))
            .foregroundStyle(Theme.ink)
            .accessibilityElement()
            .accessibilityLabel("Doddy")
    }
}

struct JourneyHeading: View {
    /// Looked up in Localizable.xcstrings like a Text literal (ADR-223).
    let eyebrow: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !eyebrow.isEmpty {
                Text(LocalizedStringKey(eyebrow)).textCase(.uppercase)
                    .font(.caption2).tracking(1.2).foregroundStyle(Theme.secondaryText)
            }
            Text(LocalizedStringKey(title)).font(.largeTitle.weight(.medium)).tracking(-1)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(LocalizedStringKey(subtitle)).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// Byte-identical drawings from the owner's numbered ZIP. No invented animation.
/// Light paper backing preserves the supplied cream/black illustration in dark appearance.
struct UploadedCharacterView: View {
    let assetName: String
    var height: CGFloat = 180
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            CharacterArtImage(assetName: assetName, height: textSize.isAccessibilitySize ? min(height, 100) : height)
        }
    }
}

/// Whole Doddy (ADR-299): one of the owner's pack poses (`WholeDoddy_*`, the same as the
/// island's), cropped to the figure and drawn at `height`. A pose means the same thing in the
/// app as on the island: shrug for "not found", facepalm for "that went wrong", wave for hello.
/// In dark appearance the outline gets the island's thin cream edge instead of a paper card.
/// Hidden with "Hide Doddy's pictures"; smaller at accessibility text sizes.
struct WholeDoddyView: View {
    let pose: IslandPose
    var height: CGFloat = 180
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            let shown = textSize.isAccessibilitySize ? min(height, 100) : height
            let box = pose.figure
            // The figure's width at this height (the picture is 2:3).
            let width = shown * CGFloat(box.width / box.height) / 1.5
            IslandPoseView(pose: pose, maxSize: CGSize(width: width, height: shown), edged: colorScheme == .dark)
                .doddyArtMarker("doddy.pose.\(pose.rawValue)")
        }
    }
}

/// UI tests only (ADR-336): launched with `-doddyArtMarkers YES`, each Doddy picture becomes one
/// accessibility element named for what it shows (`doddy.pose.shrug`, `doddy.motion.pop`), so a
/// test can check which picture is on screen. Off in normal use: the pictures stay decorative
/// and hidden from VoiceOver.
enum DoddyArtMarkers {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "doddyArtMarkers") }
}

extension View {
    func doddyArtMarker(_ identifier: String) -> some View {
        modifier(DoddyArtMarker(identifier: identifier))
    }
}

private struct DoddyArtMarker: ViewModifier {
    let identifier: String

    func body(content: Content) -> some View {
        if DoddyArtMarkers.isOn {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(identifier)
                .accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

/// A place from Doddy's world (ADR-299): his room behind Doddy on Home, a strip of the memory
/// library on Memories and of the coffee shop on the morning check-in. The owner's pack (021-036
/// "world"), day pictures in light appearance and night pictures in dark. It never sits under
/// text (ADR-308): placed only where there is none, faint (25 %), and fading in and out at its
/// top and bottom edges into the page. It scrolls with the screen. Decoration only: hidden from
/// VoiceOver, and with "Hide Doddy's pictures" (then it takes no space).
struct SceneryBackdrop: View {
    enum Place: String {
        case home, memory, coffee
        /// The focus timer (ADR-313): the basketball court, day and night.
        case court
        /// The weekly look-back (ADR-313): the rooftop. The pack has it at night only, so it is
        /// the same picture in light and dark appearance.
        case rooftop
    }

    /// The pack's world pictures are 941 × 1672.
    static let aspect: CGFloat = 941.0 / 1672.0
    static let opacity = 0.25

    let place: Place
    var height: CGFloat = 120
    /// Which part of the picture is shown: its centre, as a fraction of the picture's height.
    var focus: CGFloat = 0.25
    /// Doddy standing in the strip (ADR-313), drawn at full strength on its bottom edge.
    var pose: IslandPose?
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            GeometryReader { geometry in
                let width = geometry.size.width
                let pictureHeight = width / Self.aspect
                // Centre on `focus`, without showing past the picture's top or bottom.
                let y = min(0, max(height - pictureHeight, height / 2 - focus * pictureHeight))
                Image(decorative: "Scenery_\(place.rawValue)")
                    .resizable()
                    .frame(width: width, height: pictureHeight)
                    .offset(y: y)
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .opacity(Self.opacity)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                                       .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottom) {
                if let pose { WholeDoddyView(pose: pose, height: height * 0.78) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The picture itself at an exact height, with the paper backing in dark appearance. Shared by
/// `UploadedCharacterView` and the opening's hand-over (ADR-225), so the opening's last frame
/// and Home's picture are drawn the same way, pixel for pixel.
struct CharacterArtImage: View {
    let assetName: String
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(decorative: assetName)
            .resizable().scaledToFit()
            .frame(height: height)
            .padding(.horizontal, colorScheme == .dark ? 12 : 0)
            .background(colorScheme == .dark ? Color(red: 245/255, green: 239/255, blue: 226/255) : .clear,
                        in: RoundedRectangle(cornerRadius: 24))
            .accessibilityHidden(true)
    }
}

struct MemoryPaperCard: View {
    let record: MemoryRecord
    var textIdentifier = "memory.text"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(record.userEdited ? "EDITED DETAIL" : "SAVED DETAIL")
                .font(.caption2).tracking(1.2).foregroundStyle(Theme.secondaryText)
            Text(record.currentText).font(.title3).textSelection(.enabled)
                .accessibilityIdentifier(textIdentifier)
            Rectangle().fill(Theme.separator).frame(height: 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(record.source.displayName)
                Text(DateText.full(record.capturedAt))
            }
            .font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.separator, lineWidth: 1))
    }
}

struct MemoryLinkCard: View {
    let record: MemoryRecord
    var matchedTerms: [String] = []
    var isPinned = false
    /// A private note before Face ID (ADR-310): its words are not shown.
    var hidesText = false
    /// Room kept free on the card's right side, from its edge (motion v2, Q5: 66 pt in Memories,
    /// where Doddy stands on the card below). 0: the usual 18 pt padding.
    var gutter: CGFloat = 0

    var body: some View {
        NavigationLink(value: MemoryNavigationRoute.note(record.id)) {
            VStack(alignment: .leading, spacing: 14) {
                if hidesText {
                    Label("Private note", systemImage: "lock.fill").font(.body).foregroundStyle(Theme.secondaryText)
                } else {
                    Text(record.currentText).lineLimit(3).font(.body)
                }
                HStack(alignment: .top) {
                    Text("\(record.source.displayName) · \(DateText.full(record.capturedAt))\(record.userEdited ? " · Edited" : "")")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 8)
                    if isPinned {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(Theme.accentText)
                            .accessibilityLabel("Pinned")
                    }
                    Image(systemName: "arrow.up.right").font(.caption).accessibilityHidden(true)
                }
                if !matchedTerms.isEmpty {
                    Text("Matched: \(matchedTerms.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(Theme.accentText)
                }
            }
            .padding(18)
            .padding(.trailing, max(0, gutter - 18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("memory.open.\(record.id.uuidString)")
    }
}

/// Home and Settings (ADR-633). Notes and lists are reached from Settings › Doddy's memory, so while
/// they are open Settings is the selected tab, and tapping it goes back there.
struct DoddyTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 4) {
            tab(.home, title: "Home", icon: "house", id: "tab.home")
            tab(.settings, title: "Settings", icon: "slider.horizontal.3", id: "tab.settings")
        }
        .padding(8).background(Theme.quietSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
        // Motion v2: the capsule's top edge is "the rail", where Doddy waits during rapid
        // switching, under the selected tab.
        .motionSurface(.rail)
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 8)
        .background(Theme.canvas)
        // Like the system tab bar, keep navigation compact; the screen's content
        // still follows the owner's full accessibility text size without a cap.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App navigation")
    }

    /// Doddy's memory belongs to Settings (ADR-633).
    private func isSelected(_ tab: AppTab) -> Bool {
        selectedTab == tab || (tab == .settings && selectedTab == .memories)
    }

    private func tab(_ tab: AppTab, title: String, icon: String, id: String) -> some View {
        Button {
            // Motion v2 (MV3): Doddy hears of the tap in the same transaction as the tab change, so
            // he leaves the old screen's surface in the frame its content goes (rule 2: the
            // interface never waits for him).
            DoddyDirector.shared.tabTapped(tab.motionScreen)
            selectedTab = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.body).accessibilityHidden(true)
                Text(LocalizedStringKey(title)).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isSelected(tab) ? Theme.ink : Theme.secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id).accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityAddTraits(isSelected(tab) ? .isSelected : [])
        // Where the rail spot under this tab is, and where his eyes go when he looks at it.
        .motionMark(id)
    }
}

#Preview("Uploaded source artwork") {
    UploadedCharacterView(assetName: "UploadedDoddy_Sitting").padding().background(Theme.canvas)
}
