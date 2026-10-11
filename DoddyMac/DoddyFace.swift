import AppKit
import SwiftUI

/// Doddy's face: a circle cut out of the owner's `listening` pose from the numbered pack
/// (`WholeDoddy_listening`, docs/design/UPLOADED_MEMORY_ASSETS.md). Nothing is redrawn or
/// recoloured. The crop uses the same head position as the iPhone's Dynamic Island face
/// (`IslandPose.head` for `.listening`: centre 205/400, 152/600, diameter 172/400).
struct DoddyFace: View {
    let size: CGFloat

    var body: some View {
        let head = (x: 205.0 / 400, y: 152.0 / 600, diameter: 172.0 / 400)
        let width = size / CGFloat(head.diameter * 1.06)
        let height = width * 1.5
        Image("WholeDoddy_listening")
            .resizable()
            .frame(width: width, height: height)
            .offset(x: size / 2 - CGFloat(head.x) * width, y: size / 2 - CGFloat(head.y) * height)
            .frame(width: size, height: size, alignment: .topLeading)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// The menu-bar item's picture. A menu-bar label can't draw a cropped view directly, so the face
/// is rendered once to an image; if that fails, a plain system symbol is shown instead.
@MainActor
enum MenuBarIcon {
    static func image() -> Image {
        let renderer = ImageRenderer(content: DoddyFace(size: 18))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let picture = renderer.nsImage else { return Image(systemName: "face.smiling") }
        picture.isTemplate = false
        return Image(nsImage: picture)
    }
}
