import CoreTransferable
import DoddyCore
import DoddyDesignTokens
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Appearance › Lock Screen wallpaper (ADR-341): Doddy's paper, light or dark, with
/// one pose from the owner's pack standing clear of the clock and the controls, drawn at this
/// iPhone's own pixel size. The picture goes to the share sheet, where "Save Image" puts it in
/// Photos; iOS lets no app set the wallpaper, so the last step is the user's, in iOS Settings.
/// Nothing of the user's is in the picture.
struct WallpaperView: View {
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @State private var paper: WallpaperLayout.Paper = .light
    @State private var choice: PoseChoice = .sitting
    @State private var picture: WallpaperPicture?
    @State private var making = false
    @State private var problem: String?

    enum PoseChoice: String, CaseIterable, Identifiable {
        case none, sitting, stretching, listening, waving
        var id: String { rawValue }

        var pose: IslandPose? {
            switch self {
            case .none: nil
            case .sitting: .crosslegged
            case .stretching: .yawnStretch
            case .listening: .listening
            case .waving: .wave
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .none: "Paper only"
            case .sitting: "Sitting"
            case .stretching: "Stretching"
            case .listening: "Listening"
            case .waving: "Waving"
            }
        }
    }

    private var layout: WallpaperLayout {
        let screen = UIScreen.main
        return WallpaperLayout(canvas: WallpaperLayout.pixelSize(
            pointWidth: screen.bounds.width, pointHeight: screen.bounds.height, scale: screen.scale))
    }

    private var pose: IslandPose? { hideCharacterArt ? nil : choice.pose }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                JourneyHeading(eyebrow: "Lock Screen wallpaper", title: "Doddy's paper,\non your Lock Screen")
                preview
                Picker("Paper", selection: $paper) {
                    Text("Light paper").tag(WallpaperLayout.Paper.light)
                    Text("Dark paper").tag(WallpaperLayout.Paper.dark)
                }
                .pickerStyle(.segmented)
                if !hideCharacterArt {
                    Picker("Doddy", selection: $choice) {
                        ForEach(PoseChoice.allCases) { Text($0.title).tag($0) }
                    }
                } else {
                    Text("Character artwork is hidden in Settings, so the wallpaper is paper only.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                if let picture {
                    ShareLink(item: picture, preview: SharePreview("Doddy wallpaper", image: picture.image)) {
                        HStack { Text("Share or save the picture"); Spacer(); Image(systemName: "square.and.arrow.up") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("wallpaper.share")
                    Text("Made for this iPhone's screen: \(picture.width) × \(picture.height) pixels.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                } else {
                    Button {
                        make()
                    } label: {
                        HStack { Text("Make the picture"); Spacer(); Image(systemName: "photo") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(making)
                    .accessibilityIdentifier("wallpaper.make")
                }
                if let problem {
                    ProblemView(message: problem)
                }
                Text("Doddy can't set your wallpaper: iOS doesn't let apps do that. In the share sheet choose Save Image, then in iOS Settings › Wallpaper › Add New Wallpaper pick it from Photos. The time and widgets sit in the clear space at the top.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(24)
        }
        .background(Theme.canvas)
        .navigationTitle("Wallpaper")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: paper) { picture = nil }
        .onChange(of: choice) { picture = nil }
        .onChange(of: hideCharacterArt) { picture = nil }
    }

    /// The same drawing as the picture, scaled to fit the screen's width.
    private var preview: some View {
        let layout = layout
        let aspect = CGFloat(layout.canvas.width) / CGFloat(layout.canvas.height)
        return GeometryReader { geometry in
            let width = min(geometry.size.width, 220)
            WallpaperCanvas(layout: layout, paper: paper, pose: pose)
                .scaleEffect(width / CGFloat(layout.canvas.width), anchor: .topLeading)
                .frame(width: width, height: width / aspect, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.separator))
                .frame(maxWidth: .infinity)
        }
        .frame(height: 220 / aspect)
        .accessibilityLabel("Wallpaper preview")
    }

    /// Draws the picture at the iPhone's pixel size (one point per pixel, scale 1).
    @MainActor
    private func make() {
        making = true
        problem = nil
        defer { making = false }
        let layout = layout
        let renderer = ImageRenderer(content: WallpaperCanvas(layout: layout, paper: paper, pose: pose))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: CGFloat(layout.canvas.width), height: CGFloat(layout.canvas.height))
        guard let image = renderer.uiImage, let png = image.pngData(),
              Int(image.size.width * image.scale) == layout.canvas.width else {
            problem = NSLocalizedString("The picture couldn't be made. Try again.", comment: "")
            return
        }
        picture = WallpaperPicture(png: png, image: Image(uiImage: image), width: layout.canvas.width, height: layout.canvas.height)
    }
}

/// The wallpaper itself, in pixels: paper, a short orange rule under the clock band, and Doddy
/// standing in the lower middle. Fixed colours for the paper chosen, not the iPhone's appearance.
struct WallpaperCanvas: View {
    let layout: WallpaperLayout
    let paper: WallpaperLayout.Paper
    let pose: IslandPose?

    private var scheme: CandidateColorScheme { paper == .dark ? .dark : .light }

    private func colour(_ role: UploadedColorRole) -> Color {
        let hex = role.hex(scheme)
        return Color(red: Double(hex.red) / 255, green: Double(hex.green) / 255, blue: Double(hex.blue) / 255)
    }

    var body: some View {
        let width = CGFloat(layout.canvas.width)
        let height = CGFloat(layout.canvas.height)
        let rule = layout.accentRule()
        ZStack(alignment: .topLeading) {
            colour(.canvas)
            RoundedRectangle(cornerRadius: CGFloat(rule.height))
                .fill(colour(.orangeCue))
                .frame(width: CGFloat(rule.width), height: CGFloat(rule.height))
                .offset(x: CGFloat(rule.x), y: CGFloat(rule.y))
            if let pose {
                let box = pose.figure
                let frame = layout.figureFrame(aspect: box.width / box.height)
                IslandPoseView(pose: pose, maxSize: CGSize(width: frame.width, height: frame.height), edged: paper == .dark)
                    .frame(width: CGFloat(frame.width), height: CGFloat(frame.height))
                    .offset(x: CGFloat(frame.x), y: CGFloat(frame.y))
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// The finished picture for the share sheet, as PNG.
struct WallpaperPicture: Transferable {
    let png: Data
    let image: Image
    let width: Int
    let height: Int

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName("Doddy wallpaper.png")
    }
}
