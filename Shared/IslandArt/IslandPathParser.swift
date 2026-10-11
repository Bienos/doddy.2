import Foundation

/// One drawing step, in the path's own units.
enum IslandPathCommand: Equatable, Sendable {
    case move(Double, Double)
    case line(Double, Double)
    case quad(cx: Double, cy: Double, x: Double, y: Double)
    case cubic(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
    case close
}

/// Reads the absolute SVG path commands the island pack uses (M L H V Q C S A Z) into
/// `IslandPathCommand`s. Arcs become cubic curves. A path it can't read gives no commands
/// (nothing is drawn) rather than a wrong shape; `scripts/check_island_art.sh` reads every
/// path in the pack so that never happens unnoticed.
enum IslandPathParser {
    static func commands(_ d: String) -> [IslandPathCommand] {
        parse(d) ?? []
    }

    static func parse(_ d: String) -> [IslandPathCommand]? {
        var tokens = Tokens(Array(d.utf8))
        var out: [IslandPathCommand] = []
        var current = (x: 0.0, y: 0.0)
        var start = (x: 0.0, y: 0.0)
        var lastCubicControl: (x: Double, y: Double)?
        var command: UInt8?

        while true {
            tokens.skipSeparators()
            if tokens.atEnd { break }
            if let letter = tokens.letter() {
                command = letter
            } else if command == nil || command == UInt8(ascii: "Z") {
                return nil
            }
            guard let c = command else { return nil }
            var cubicControl: (x: Double, y: Double)?

            switch c {
            case UInt8(ascii: "M"):
                guard let x = tokens.number(), let y = tokens.number() else { return nil }
                out.append(.move(x, y))
                current = (x, y)
                start = current
                command = UInt8(ascii: "L")  // further pairs are lines
            case UInt8(ascii: "L"):
                guard let x = tokens.number(), let y = tokens.number() else { return nil }
                out.append(.line(x, y))
                current = (x, y)
            case UInt8(ascii: "H"):
                guard let x = tokens.number() else { return nil }
                out.append(.line(x, current.y))
                current.x = x
            case UInt8(ascii: "V"):
                guard let y = tokens.number() else { return nil }
                out.append(.line(current.x, y))
                current.y = y
            case UInt8(ascii: "Q"):
                guard let cx = tokens.number(), let cy = tokens.number(),
                      let x = tokens.number(), let y = tokens.number() else { return nil }
                out.append(.quad(cx: cx, cy: cy, x: x, y: y))
                current = (x, y)
            case UInt8(ascii: "C"):
                guard let c1x = tokens.number(), let c1y = tokens.number(),
                      let c2x = tokens.number(), let c2y = tokens.number(),
                      let x = tokens.number(), let y = tokens.number() else { return nil }
                out.append(.cubic(c1x: c1x, c1y: c1y, c2x: c2x, c2y: c2y, x: x, y: y))
                cubicControl = (c2x, c2y)
                current = (x, y)
            case UInt8(ascii: "S"):
                guard let c2x = tokens.number(), let c2y = tokens.number(),
                      let x = tokens.number(), let y = tokens.number() else { return nil }
                // First control point: the previous curve's second one reflected, else the current point.
                let c1 = lastCubicControl.map { (2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
                out.append(.cubic(c1x: c1.0, c1y: c1.1, c2x: c2x, c2y: c2y, x: x, y: y))
                cubicControl = (c2x, c2y)
                current = (x, y)
            case UInt8(ascii: "A"):
                guard let rx = tokens.number(), let ry = tokens.number(), let rotation = tokens.number(),
                      let large = tokens.flag(), let sweep = tokens.flag(),
                      let x = tokens.number(), let y = tokens.number() else { return nil }
                out += arc(from: current, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep, to: (x, y))
                current = (x, y)
            case UInt8(ascii: "Z"):
                out.append(.close)
                current = start
            default:
                return nil
            }
            lastCubicControl = cubicControl
        }
        return out
    }

    /// SVG elliptical arc (endpoint form) as cubic curves, per the SVG spec's conversion
    /// to centre form (Appendix B.2.4), one curve per quarter turn or less.
    static func arc(from p0: (x: Double, y: Double), rx rxIn: Double, ry ryIn: Double, rotation: Double,
                    large: Bool, sweep: Bool, to p1: (x: Double, y: Double)) -> [IslandPathCommand] {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 || (p0.x == p1.x && p0.y == p1.y) { return [.line(p1.x, p1.y)] }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = (max(0, num) / den).squareRoot()
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var out: [IslandPathCommand] = []
        var t = theta1
        func point(_ a: Double) -> (Double, Double) {
            let ex = rx * cos(a), ey = ry * sin(a)
            return (cosPhi * ex - sinPhi * ey + cx, sinPhi * ex + cosPhi * ey + cy)
        }
        func derivative(_ a: Double) -> (Double, Double) {
            let ex = -rx * sin(a), ey = ry * cos(a)
            return (cosPhi * ex - sinPhi * ey, sinPhi * ex + cosPhi * ey)
        }
        for i in 0..<segments {
            let t2 = t + step
            let a = point(t), b = point(t2)
            let da = derivative(t), db = derivative(t2)
            let end = i == segments - 1 ? (p1.x, p1.y) : b
            out.append(.cubic(c1x: a.0 + k * da.0, c1y: a.1 + k * da.1,
                              c2x: b.0 - k * db.0, c2y: b.1 - k * db.1, x: end.0, y: end.1))
            t = t2
        }
        return out
    }
}

/// Splits "M-11 4Q-14-2-9-4" style path data: numbers may run together when the next starts
/// with "-" or a second ".".
private struct Tokens {
    let bytes: [UInt8]
    var i = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var atEnd: Bool { i >= bytes.count }

    mutating func skipSeparators() {
        while i < bytes.count, bytes[i] == UInt8(ascii: " ") || bytes[i] == UInt8(ascii: ",")
                || bytes[i] == UInt8(ascii: "\n") || bytes[i] == UInt8(ascii: "\t") {
            i += 1
        }
    }

    mutating func letter() -> UInt8? {
        skipSeparators()
        guard i < bytes.count else { return nil }
        let b = bytes[i]
        guard (b >= 65 && b <= 90) || (b >= 97 && b <= 122), b != UInt8(ascii: "e") else { return nil }
        i += 1
        return b
    }

    mutating func number() -> Double? {
        skipSeparators()
        let begin = i
        if i < bytes.count, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") { i += 1 }
        var sawDigit = false, sawDot = false
        while i < bytes.count {
            let b = bytes[i]
            if b >= 48 && b <= 57 {
                sawDigit = true
            } else if b == UInt8(ascii: "."), !sawDot {
                sawDot = true
            } else {
                break
            }
            i += 1
        }
        if sawDigit, i < bytes.count, bytes[i] == UInt8(ascii: "e") {
            i += 1
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") { i += 1 }
            while i < bytes.count, bytes[i] >= 48 && bytes[i] <= 57 { i += 1 }
        }
        guard sawDigit, let text = String(bytes: bytes[begin..<i], encoding: .utf8), let value = Double(text),
              value.isFinite else {
            i = begin
            return nil
        }
        return value
    }

    /// Arc flags are single digits and may be written without separators ("0 1 1").
    mutating func flag() -> Bool? {
        skipSeparators()
        guard i < bytes.count else { return nil }
        switch bytes[i] {
        case UInt8(ascii: "0"): i += 1; return false
        case UInt8(ascii: "1"): i += 1; return true
        default: return nil
        }
    }
}
