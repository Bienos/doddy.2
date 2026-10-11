import Foundation

/// A still Lock Screen wallpaper (ADR-341): Doddy's paper and, if the user likes, one pose from
/// the owner's pack, drawn by the app at the iPhone's own pixel size and handed to the share
/// sheet. iOS gives no app a way to set the wallpaper, so the user saves the picture to Photos
/// and picks it under iOS Settings › Wallpaper. These are the placing rules, tested on Linux:
/// the clock and widgets sit in the top band and the two controls at the bottom, so Doddy
/// stands in the lower middle where nothing covers him.
public struct WallpaperLayout: Equatable, Sendable {
    public struct Size: Equatable, Sendable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public struct Rect: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
    }

    /// The paper, light or dark; a choice, not the iPhone's appearance, since a wallpaper
    /// doesn't follow it.
    public enum Paper: String, CaseIterable, Sendable {
        case light, dark
    }

    /// The top share of the picture kept clear for the time, date and Lock Screen widgets.
    public static let clockBand = 0.34
    /// The bottom share kept clear for the flashlight and camera controls and the home bar.
    public static let controlsBand = 0.13
    /// Doddy's height as a share of the picture's height.
    public static let figureShare = 0.26
    /// The smallest picture that is still a wallpaper and not an icon.
    public static let minimumSide = 320

    public let canvas: Size

    public init(canvas: Size) {
        self.canvas = canvas
    }

    /// The picture's size in pixels for a screen in points at a scale, rounded to whole pixels.
    public static func pixelSize(pointWidth: Double, pointHeight: Double, scale: Double) -> Size {
        Size(width: max(minimumSide, Int((pointWidth * scale).rounded())),
             height: max(minimumSide, Int((pointHeight * scale).rounded())))
    }

    /// Where a figure with this width-to-height ratio stands: centred, `figureShare` tall, its
    /// feet a little above the controls band. Always inside the picture and below the clock band.
    public func figureFrame(aspect: Double) -> Rect {
        let height = Double(canvas.height)
        let width = Double(canvas.width)
        var figureHeight = height * Self.figureShare
        var figureWidth = figureHeight * max(0.1, aspect)
        if figureWidth > width * 0.8 {
            figureWidth = width * 0.8
            figureHeight = figureWidth / max(0.1, aspect)
        }
        let bottom = height * (1 - Self.controlsBand) - height * 0.03
        return Rect(x: (width - figureWidth) / 2, y: bottom - figureHeight, width: figureWidth, height: figureHeight)
    }

    /// A short orange rule under the clock band, as on Doddy's paper cards: its left, right and
    /// vertical position.
    public func accentRule() -> Rect {
        let width = Double(canvas.width)
        let height = Double(canvas.height)
        let ruleWidth = width * 0.12
        return Rect(x: (width - ruleWidth) / 2, y: height * (Self.clockBand + 0.02),
                    width: ruleWidth, height: max(2, height * 0.0025))
    }
}
