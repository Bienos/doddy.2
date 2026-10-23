import Foundation

/// A tiny reader for SVG path data (the `d` attribute), enough for the welcome's placeholder
/// scenery (the Warsaw line and the pigeon): M, L, H, V, Q, C and Z, absolute or relative, with
/// the usual implicit repeats. Arcs and the smooth commands are not supported and make `parse`
/// return nil, so a path that needs them fails loudly in a test instead of drawing wrongly.
public enum WelcomePathSegment: Equatable, Sendable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case quad(cx: Double, cy: Double, x: Double, y: Double)
    case cubic(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
    case close
}

public enum WelcomePathData {
    public static func parse(_ data: String) -> [WelcomePathSegment]? {
        let chars = Array(data)
        var index = 0
        var segments: [WelcomePathSegment] = []
        var command: Character?
        var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0

        func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" || chars[index] == "\t" {
                index += 1
            }
        }
        func number() -> Double? {
            skipSeparators()
            var end = index
            if end < chars.count, chars[end] == "-" || chars[end] == "+" { end += 1 }
            var digits = false
            var dot = false
            while end < chars.count {
                let c = chars[end]
                if c >= "0" && c <= "9" { digits = true; end += 1 } else if c == ".", !dot { dot = true; end += 1 } else { break }
            }
            guard digits, let value = Double(String(chars[index..<end])) else { return nil }
            index = end
            return value
        }
        func numbers(_ count: Int) -> [Double]? {
            var values: [Double] = []
            for _ in 0..<count {
                guard let value = number() else { return nil }
                values.append(value)
            }
            return values
        }

        while true {
            skipSeparators()
            if index >= chars.count { break }
            let c = chars[index]
            if c.isLetter {
                command = c
                index += 1
                if c == "Z" || c == "z" {
                    segments.append(.close)
                    x = startX
                    y = startY
                    command = nil
                }
                continue
            }
            guard let current = command else { return nil }
            let relative = current.isLowercase
            let dx = relative ? x : 0
            let dy = relative ? y : 0
            switch current {
            case "M", "m":
                guard let v = numbers(2) else { return nil }
                x = v[0] + dx; y = v[1] + dy
                startX = x; startY = y
                segments.append(.move(x: x, y: y))
                // Further pairs after a move are lines.
                command = relative ? "l" : "L"
            case "L", "l":
                guard let v = numbers(2) else { return nil }
                x = v[0] + dx; y = v[1] + dy
                segments.append(.line(x: x, y: y))
            case "H", "h":
                guard let v = numbers(1) else { return nil }
                x = v[0] + dx
                segments.append(.line(x: x, y: y))
            case "V", "v":
                guard let v = numbers(1) else { return nil }
                y = v[0] + dy
                segments.append(.line(x: x, y: y))
            case "Q", "q":
                guard let v = numbers(4) else { return nil }
                let cx = v[0] + dx, cy = v[1] + dy
                x = v[2] + dx; y = v[3] + dy
                segments.append(.quad(cx: cx, cy: cy, x: x, y: y))
            case "C", "c":
                guard let v = numbers(6) else { return nil }
                let c1x = v[0] + dx, c1y = v[1] + dy, c2x = v[2] + dx, c2y = v[3] + dy
                x = v[4] + dx; y = v[5] + dy
                segments.append(.cubic(c1x: c1x, c1y: c1y, c2x: c2x, c2y: c2y, x: x, y: y))
            default:
                return nil
            }
        }
        return segments.isEmpty ? nil : segments
    }
}
