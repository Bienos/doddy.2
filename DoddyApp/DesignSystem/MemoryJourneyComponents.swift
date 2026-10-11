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

struct DoddyWordmark: View {
    var body: some View {
        (Text("doddy").foregroundColor(Theme.ink) + Text(".").foregroundColor(Theme.accentText))
            .font(.title.weight(.medium))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .tracking(-1.5)
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
        }
    }
}

/// A place from Doddy's world behind the top of a screen (ADR-299): his room on Home, the
/// memory library on Memories, the coffee shop for the morning check-in. The owner's pack
/// (021-036 "world"), day pictures in light appearance and night pictures in dark. Faint and
/// fading into the canvas, so text over it keeps its contrast; it scrolls with the screen.
/// Decoration only: hidden from VoiceOver, and with "Hide Doddy's pictures".
struct SceneryBackdrop: View {
    enum Place: String {
        case home, memory, coffee
    }

    let place: Place
    var height: CGFloat = 380
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            Color.clear
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    Image(decorative: "Scenery_\(place.rawValue)")
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .opacity(0.4)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.5),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
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
    /// A private note before Face ID (ADR-308): its words are not shown.
    var hidesText = false

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
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("memory.open.\(record.id.uuidString)")
    }
}

struct DoddyTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 4) {
            tab(.home, title: "Home", icon: "house", id: "tab.home")
            tab(.memories, title: "Memories", icon: "book.closed", id: "tab.memories")
            tab(.settings, title: "Settings", icon: "slider.horizontal.3", id: "tab.settings")
        }
        .padding(8).background(Theme.quietSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 8)
        .background(Theme.canvas)
        // Like the system tab bar, keep navigation compact; the screen's content
        // still follows the owner's full accessibility text size without a cap.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App navigation")
    }

    private func tab(_ tab: AppTab, title: String, icon: String, id: String) -> some View {
        Button { selectedTab = tab } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.body).accessibilityHidden(true)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selectedTab == tab ? Theme.ink : Theme.secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id).accessibilityLabel(title)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }
}

#Preview("Uploaded source artwork") {
    UploadedCharacterView(assetName: "UploadedDoddy_Sitting").padding().background(Theme.canvas)
}
