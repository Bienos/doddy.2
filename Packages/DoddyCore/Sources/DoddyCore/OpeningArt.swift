import Foundation

// The character drawings for the opening (ADR-225), read from the supplied v1.3-r1 SVGs
// (`design/interface-v1.2/assets/doddy-pose-basketball-*-light-v1.3-r1.svg (deleted 20 Oct 2026, ADR-548; see git history)`, copied into the
// app bundle). They are line art: a few dozen stroked paths, circles and ellipses in nested
// groups with translate/scale/rotate transforms, in three colours. Reading them as paths lets
// the app draw Doddy stroke by stroke, like a pen, and recolour him for dark appearance. The
// reader covers exactly what those files use and refuses anything else, so a changed drawing
// is caught by the tests rather than drawn wrong.

/// A colour in the drawings, by role rather than value, so each appearance picks its own.
public enum ArtColor: Equatable, Sendable {
    /// The ink lines (`#171715` in the light files).
    case ink
    /// The paper-coloured fills: head, hands, trainers (`#FFF7E9`).
    case paper
    /// The basketball (`#F58A24`).
    case orange
}

/// One segment of a path, in the drawing's own coordinates (0…`DoddyDrawing.size`), with every
/// group transform already applied.
public enum PathCommand: Equatable, Sendable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case quad(cx: Double, cy: Double, x: Double, y: Double)
    case cubic(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
    case close
}

/// One drawn element: a path, circle or ellipse with its stroke and fill.
public struct DrawnStroke: Equatable, Sendable {
    public let commands: [PathCommand]
    /// Line width in drawing units, scaled by the groups the element sits in; 0 when not stroked.
    public let lineWidth: Double
    public let stroke: ArtColor?
    public let fill: ArtColor?
    /// The ids of the groups around the element, outermost first, plus the element's own id if it
    /// has one (e.g. `["doddy-basketball-shot", "prop", "basketball"]`, `[…, "head-and-face", "head-contour"]`).
    public let groups: [String]

    public var isInGroup: (String) -> Bool { { id in groups.contains(id) } }
}

public struct DoddyDrawing: Equatable, Sendable {
    /// The square the coordinates live in (512 for the v1.3-r1 files).
    public let size: Double
    /// In document order, which is also a sensible order to draw them in: limbs, then trainers
    /// and hands, then the head and face.
    public let strokes: [DrawnStroke]

    public init(size: Double, strokes: [DrawnStroke]) {
        self.size = size
        self.strokes = strokes
    }

    /// The drawing without the elements inside a group, e.g. without the `basketball` so the
    /// opening can draw its own ball.
    public func without(group id: String) -> DoddyDrawing {
        DoddyDrawing(size: size, strokes: strokes.filter { !$0.groups.contains(id) })
    }

    public func contains(group id: String) -> Bool {
        strokes.contains { $0.groups.contains(id) }
    }
}

public enum SVGPoseReaderError: Error, Equatable {
    case notAnSVG
    case unsupportedElement(String)
    case unsupportedTransform(String)
    case unsupportedPathCommand(Character)
    case malformedPath(String)
    case unknownColor(String)
    case missingAttribute(String)
}

/// Reads one of the supplied pose SVGs into a `DoddyDrawing`.
public enum SVGPoseReader {
    public static func read(_ svg: String) throws -> DoddyDrawing {
        var reader = Reader(text: svg)
        return try reader.read()
    }

    // MARK: - The reader

    private struct Transform {
        /// Applied right to left, as SVG does: `translate(…) scale(…) rotate(…)` rotates first.
        enum Op { case translate(Double, Double), scale(Double, Double), rotate(Double) }
        var ops: [Op]

        func apply(_ p: (Double, Double)) -> (Double, Double) {
            var (x, y) = p
            for op in ops.reversed() {
                switch op {
                case .translate(let tx, let ty): x += tx; y += ty
                case .scale(let sx, let sy): x *= sx; y *= sy
                case .rotate(let degrees):
                    let r = degrees * .pi / 180
                    (x, y) = (x * cos(r) - y * sin(r), x * sin(r) + y * cos(r))
                }
            }
            return (x, y)
        }

        /// Uniform scale factor for line widths (the files only scale uniformly).
        var lineScale: Double {
            ops.reduce(1) { if case .scale(let sx, _) = $1 { $0 * sx } else { $0 } }
        }
    }

    private struct Frame {
        var transform: Transform
        var id: String?
    }

    private struct Reader {
        let text: String
        var strokes: [DrawnStroke] = []
        var stack: [Frame] = []
        var size: Double = 0

        init(text: String) { self.text = text }

        mutating func read() throws -> DoddyDrawing {
            guard let svgTag = tags().first(where: { $0.name == "svg" }) else { throw SVGPoseReaderError.notAnSVG }
            let viewBox = (svgTag.attributes["viewBox"] ?? "").split(separator: " ").compactMap { Double($0) }
            size = viewBox.count == 4 ? viewBox[3] : Double(svgTag.attributes["height"] ?? "") ?? 0
            guard size > 0 else { throw SVGPoseReaderError.missingAttribute("viewBox") }
            for tag in tags() {
                switch (tag.name, tag.isClosing) {
                case ("g", false):
                    stack.append(Frame(transform: try transform(tag.attributes["transform"]), id: tag.attributes["id"]))
                case ("g", true):
                    _ = stack.popLast()
                case ("path", false):
                    try add(commands: try pathCommands(tag.attributes["d"] ?? ""), attributes: tag.attributes)
                case ("circle", false):
                    let cx = try number(tag.attributes, "cx"), cy = try number(tag.attributes, "cy"), r = try number(tag.attributes, "r")
                    try add(commands: ellipse(cx: cx, cy: cy, rx: r, ry: r), attributes: tag.attributes)
                case ("ellipse", false):
                    let cx = try number(tag.attributes, "cx"), cy = try number(tag.attributes, "cy")
                    try add(commands: ellipse(cx: cx, cy: cy, rx: try number(tag.attributes, "rx"), ry: try number(tag.attributes, "ry")), attributes: tag.attributes)
                case ("svg", _), ("metadata", _), ("title", _):
                    break
                case (let name, false):
                    throw SVGPoseReaderError.unsupportedElement(name)
                default:
                    break
                }
            }
            return DoddyDrawing(size: size, strokes: strokes)
        }

        private mutating func add(commands: [PathCommand], attributes: [String: String]) throws {
            let placed = commands.map(place)
            let lineScale = stack.reduce(1) { $0 * $1.transform.lineScale }
            let stroke = try color(attributes["stroke"])
            let width = stroke == nil ? 0 : (Double(attributes["stroke-width"] ?? "1") ?? 1) * lineScale
            // An element's own id (the head's circle, the eyes) counts as its innermost group.
            strokes.append(DrawnStroke(
                commands: placed, lineWidth: width, stroke: stroke, fill: try color(attributes["fill"]),
                groups: stack.compactMap(\.id) + (attributes["id"].map { [$0] } ?? [])))
        }

        private func place(_ command: PathCommand) -> PathCommand {
            func p(_ x: Double, _ y: Double) -> (Double, Double) {
                var point = (x, y)
                for frame in stack.reversed() { point = frame.transform.apply(point) }
                return point
            }
            switch command {
            case .move(let x, let y): let (px, py) = p(x, y); return .move(x: px, y: py)
            case .line(let x, let y): let (px, py) = p(x, y); return .line(x: px, y: py)
            case .quad(let cx, let cy, let x, let y):
                let (pcx, pcy) = p(cx, cy), (px, py) = p(x, y)
                return .quad(cx: pcx, cy: pcy, x: px, y: py)
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                let (p1x, p1y) = p(c1x, c1y), (p2x, p2y) = p(c2x, c2y), (px, py) = p(x, y)
                return .cubic(c1x: p1x, c1y: p1y, c2x: p2x, c2y: p2y, x: px, y: py)
            case .close: return .close
            }
        }

        private func color(_ value: String?) throws -> ArtColor? {
            switch value?.uppercased() {
            case nil, "NONE": nil
            case "#171715", "#171E29", "#080808": .ink
            case "#FFF7E9", "#F5EFE2": .paper
            case "#F58A24", "#EC803F": .orange
            case .some(let other): throw SVGPoseReaderError.unknownColor(other)
            }
        }

        private func number(_ attributes: [String: String], _ name: String) throws -> Double {
            guard let value = attributes[name], let number = Double(value) else { throw SVGPoseReaderError.missingAttribute(name) }
            return number
        }

        private func transform(_ value: String?) throws -> Transform {
            guard let value, !value.isEmpty else { return Transform(ops: []) }
            var ops: [Transform.Op] = []
            let scanner = value.replacingOccurrences(of: ",", with: " ")
            var rest = Substring(scanner)
            while let open = rest.firstIndex(of: "(") {
                let name = rest[..<open].trimmingCharacters(in: .whitespaces)
                guard let close = rest[open...].firstIndex(of: ")") else { throw SVGPoseReaderError.unsupportedTransform(value) }
                let numbers = rest[rest.index(after: open)..<close].split(separator: " ").compactMap { Double($0) }
                switch (name, numbers.count) {
                case ("translate", 2): ops.append(.translate(numbers[0], numbers[1]))
                case ("translate", 1): ops.append(.translate(numbers[0], 0))
                case ("scale", 1): ops.append(.scale(numbers[0], numbers[0]))
                case ("scale", 2): ops.append(.scale(numbers[0], numbers[1]))
                case ("rotate", 1): ops.append(.rotate(numbers[0]))
                case ("rotate", 3):
                    // About a point: move it to the origin, turn, move back (applied right to left).
                    ops.append(.translate(numbers[1], numbers[2]))
                    ops.append(.rotate(numbers[0]))
                    ops.append(.translate(-numbers[1], -numbers[2]))
                default: throw SVGPoseReaderError.unsupportedTransform(value)
                }
                rest = rest[rest.index(after: close)...]
            }
            return Transform(ops: ops)
        }

        private func pathCommands(_ d: String) throws -> [PathCommand] {
            var commands: [PathCommand] = []
            var numbers: [Double] = []
            var current: Character?
            func flush() throws {
                guard let command = current else { return }
                let needed: Int
                switch command {
                case "M", "L": needed = 2
                case "Q": needed = 4
                case "C": needed = 6
                case "Z": needed = 0
                default: throw SVGPoseReaderError.unsupportedPathCommand(command)
                }
                if needed == 0 {
                    guard numbers.isEmpty else { throw SVGPoseReaderError.malformedPath(d) }
                    commands.append(.close)
                    return
                }
                guard !numbers.isEmpty, numbers.count % needed == 0 else { throw SVGPoseReaderError.malformedPath(d) }
                var first = true
                for chunk in stride(from: 0, to: numbers.count, by: needed) {
                    let n = Array(numbers[chunk..<chunk + needed])
                    switch command {
                    case "M": commands.append(first ? .move(x: n[0], y: n[1]) : .line(x: n[0], y: n[1]))
                    case "L": commands.append(.line(x: n[0], y: n[1]))
                    case "Q": commands.append(.quad(cx: n[0], cy: n[1], x: n[2], y: n[3]))
                    case "C": commands.append(.cubic(c1x: n[0], c1y: n[1], c2x: n[2], c2y: n[3], x: n[4], y: n[5]))
                    default: break
                    }
                    first = false
                }
                numbers = []
            }
            var token = ""
            func endToken() throws {
                guard !token.isEmpty else { return }
                guard let value = Double(token) else { throw SVGPoseReaderError.malformedPath(d) }
                numbers.append(value)
                token = ""
            }
            for character in d {
                if character.isLetter {
                    try endToken()
                    try flush()
                    current = character
                } else if character == "," || character.isWhitespace {
                    try endToken()
                } else if character == "-" && !token.isEmpty && !token.hasSuffix("e") {
                    try endToken()
                    token = "-"
                } else {
                    token.append(character)
                }
            }
            try endToken()
            try flush()
            return commands
        }

        /// Four cubic arcs, the usual approximation.
        private func ellipse(cx: Double, cy: Double, rx: Double, ry: Double) -> [PathCommand] {
            let k = 0.5522847498
            return [
                .move(x: cx + rx, y: cy),
                .cubic(c1x: cx + rx, c1y: cy + ry * k, c2x: cx + rx * k, c2y: cy + ry, x: cx, y: cy + ry),
                .cubic(c1x: cx - rx * k, c1y: cy + ry, c2x: cx - rx, c2y: cy + ry * k, x: cx - rx, y: cy),
                .cubic(c1x: cx - rx, c1y: cy - ry * k, c2x: cx - rx * k, c2y: cy - ry, x: cx, y: cy - ry),
                .cubic(c1x: cx + rx * k, c1y: cy - ry, c2x: cx + rx, c2y: cy - ry * k, x: cx + rx, y: cy),
                .close,
            ]
        }

        // MARK: Tags

        struct Tag {
            let name: String
            let isClosing: Bool
            let attributes: [String: String]
        }

        /// Every `<…>` in the file, in order, with its attributes. Enough for these files: no
        /// comments, CDATA or entities to worry about beyond the metadata text, which is skipped.
        private func tags() -> [Tag] {
            var result: [Tag] = []
            var rest = Substring(text)
            while let open = rest.firstIndex(of: "<") {
                guard let close = rest[open...].firstIndex(of: ">") else { break }
                let inner = rest[rest.index(after: open)..<close]
                rest = rest[rest.index(after: close)...]
                var body = Substring(inner)
                var closing = false
                if body.hasPrefix("/") { closing = true; body = body.dropFirst() }
                if body.hasPrefix("?") || body.hasPrefix("!") { continue }
                let selfClosing = body.hasSuffix("/")
                if selfClosing { body = body.dropLast() }
                let nameEnd = body.firstIndex(where: { $0.isWhitespace }) ?? body.endIndex
                let name = String(body[..<nameEnd])
                var attributes: [String: String] = [:]
                var attrs = body[nameEnd...]
                while let eq = attrs.firstIndex(of: "=") {
                    let key = attrs[..<eq].trimmingCharacters(in: .whitespaces)
                    let afterEq = attrs.index(after: eq)
                    guard afterEq < attrs.endIndex, attrs[afterEq] == "\"",
                          let end = attrs[attrs.index(after: afterEq)...].firstIndex(of: "\"") else { break }
                    attributes[key] = String(attrs[attrs.index(after: afterEq)..<end])
                    attrs = attrs[attrs.index(after: end)...]
                }
                result.append(Tag(name: name, isClosing: closing, attributes: attributes))
                // A self-closing element opens and closes at once; `<g/>` would be odd but harmless.
                if selfClosing && name == "g" { result.append(Tag(name: "g", isClosing: true, attributes: [:])) }
            }
            return result
        }
    }
}
