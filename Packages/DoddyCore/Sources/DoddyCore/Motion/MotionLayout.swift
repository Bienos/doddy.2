import Foundation

// Motion v2, MV2 (docs/design/MOTION_V2_PLAN.md section 1): where Doddy stands on each of the
// app's surfaces, worked out from the frames the screens report. Pure geometry in window points
// (y grows downwards), so it is tested on Linux; the app only measures views and calls these.
// On the brief's 390 × 844 canvas every function gives the brief's own numbers (MotionLayoutTests).

/// A rectangle in window points.
public struct MotionRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// Whether the two overlap by more than a hair (touching edges don't count).
    public func overlaps(_ other: MotionRect) -> Bool {
        min(maxX, other.maxX) - max(minX, other.minX) > 0.5 && min(maxY, other.maxY) - max(minY, other.minY) > 0.5
    }

    /// Grown by `d` on every side (negative shrinks).
    public func outset(by d: Double) -> MotionRect {
        MotionRect(x: x - d, y: y - d, width: width + 2 * d, height: height + 2 * d)
    }
}

/// The app's numbers for Doddy's world: his size, his clear zone and how each surface is laid out
/// for him (plan section 1 and the owner's answers to Q5 and Q12).
public enum MotionLayout {
    /// His height at 1.0× (brief: 96 pt).
    public static let height = 96.0
    /// The box above his soles that stays empty, at 1.0× (brief: 48 × 108 pt; 67 × 151 at 1.4×).
    public static let zoneWidth = 48.0
    public static let zoneHeight = 108.0
    /// Home's stage line (brief: 140 pt wide, his soles at its centre).
    public static let stageLineWidth = 140.0
    /// Memories cards keep this much of their right side free of text and icons, so he can stand
    /// on the card below without covering this one (Q5, recommended: the 66 pt right gutter).
    public static let cardGutter = 66.0
    /// His soles on a card's top edge: this far in from its right end, so his zone (48 pt) ends
    /// 12 pt inside the card and starts 6 pt clear of the text column.
    public static let cardSpotInset = 36.0
    /// Scrolling lists end with this much empty space, so their last item can always scroll clear
    /// of him (brief: 108 pt bottom inset).
    public static let listBottomInset = 108.0
    /// Keep-clear distances from his zone (brief rule 8): Send and "Review ›" 24 pt, links 16 pt.
    public static let sendClearance = 24.0
    public static let linkClearance = 16.0
    /// Nearest he stands to a bar's or composer's leading end (the reference's 44 pt on a 16 pt
    /// inset composer).
    public static let leadingInset = 28.0

    /// His clear zone for soles at `spot` and size `scale`.
    public static func zone(soles spot: MotionPoint, scale: Double) -> MotionRect {
        let w = zoneWidth * scale, h = zoneHeight * scale
        return MotionRect(x: spot.x - w / 2, y: spot.y - h, width: w, height: h)
    }

    /// Home's stage line: the centre of the line.
    public static func stageSpotX(line: MotionRect) -> Double { line.midX }

    /// Where on the stage line his soles may be: its middle, so his whole zone stays over it.
    public static func stageStandRange(line: MotionRect, scale: Double) -> ClosedRange<Double> {
        let half = zoneWidth * scale / 2
        let lo = line.minX + half, hi = line.maxX - half
        return lo <= hi ? lo...hi : line.midX...line.midX
    }

    /// A Memories card's top edge (a "rule"): the right end, in the gutter.
    public static func cardSpotX(card: MotionRect) -> Double { card.maxX - cardSpotInset }

    /// On a card he may move only inside the gutter, never over the text column.
    public static func cardStandRange(card: MotionRect) -> ClosedRange<Double> {
        let lo = card.maxX - cardGutter + zoneWidth / 2, hi = card.maxX - zoneWidth / 2
        return lo <= hi ? lo...hi : cardSpotX(card: card)...cardSpotX(card: card)
    }

    /// The note page's card (`MemoryPaperCard`): its top edge at the right end, clear of the
    /// left-aligned heading above it (plan, "Detail page").
    public static func detailSpotX(card: MotionRect) -> Double { card.maxX - cardSpotInset }

    /// Ask's composer: left of Send, his zone at least 24 pt from it (brief: x 250, centre never
    /// past 284 on the 390 pt canvas). Nil `send`: the composer's own right end is the limit.
    public static func composerStandRange(composer: MotionRect, send: MotionRect?) -> ClosedRange<Double> {
        let lo = composer.minX + leadingInset
        let hi = (send?.minX ?? composer.maxX) - sendClearance - zoneWidth / 2
        return lo <= hi ? lo...hi : lo...lo
    }

    /// His Ask spot: where the brief's 250 pt sits on its 16…374 pt composer, kept in range.
    public static func composerSpotX(composer: MotionRect, send: MotionRect?) -> Double {
        let range = composerStandRange(composer: composer, send: send)
        let x = composer.minX + composer.width * ((250.0 - 16) / (374.0 - 16))
        return MotionMath.clamp(x, range.lowerBound, range.upperBound)
    }

    /// The rail (the tab bar's top edge) under a tab: that tab's centre, kept on the bar.
    public static func railSpotX(tabCenter: Double, bar: MotionRect) -> Double {
        MotionMath.clamp(tabCenter, bar.minX + zoneWidth / 2, bar.maxX - zoneWidth / 2)
    }

    public static func railStandRange(bar: MotionRect) -> ClosedRange<Double> {
        let lo = bar.minX + zoneWidth / 2, hi = bar.maxX - zoneWidth / 2
        return lo <= hi ? lo...hi : bar.midX...bar.midX
    }

    /// A bar that comes and goes above the tab bar (the undo bar, "the strip if showing"): left
    /// of its action button, his zone 24 pt from it, as the brief keeps him clear of "Review ›".
    public static func barStandRange(bar: MotionRect, action: MotionRect?) -> ClosedRange<Double> {
        let lo = bar.minX + leadingInset
        let hi = (action?.minX ?? bar.maxX) - sendClearance - zoneWidth / 2
        return lo <= hi ? lo...hi : lo...lo
    }

    public static func barSpotX(bar: MotionRect, action: MotionRect?) -> Double {
        barStandRange(bar: bar, action: action).upperBound
    }

    /// A ledge (Settings' spot, the empty Memories line): its centre.
    public static func ledgeSpotX(ledge: MotionRect) -> Double { ledge.midX }

    /// What his zone would cover among `obstacles` (text, buttons, hit areas), each grown by
    /// `clearance` first. Empty: the spot keeps rule 8.
    public static func blocked(zone: MotionRect, by obstacles: [MotionRect], clearance: Double = 0) -> [MotionRect] {
        obstacles.filter { zone.overlaps($0.outset(by: clearance)) }
    }
}
