import Foundation

// Sums and unit conversions on the iPhone (ADR-266). Language models get arithmetic wrong, so the
// agent passes the sum or the conversion and reads back the app's answer instead of working it
// out. Everything runs here: no network, no account, no permission, nothing stored or logged.
// Only + − × ÷, powers, brackets and percent; no names, variables or functions, so nothing in an
// expression can do anything but arithmetic. Currencies are not converted (they need live rates
// from an outside service, an owner decision).

extension VoiceToolName {
    public static let calculate = "calculate"
    public static let convertUnits = "convert_units"
}

// MARK: Arithmetic

public enum CalculationError: Error, Equatable, Sendable {
    case empty
    case tooLong
    case unexpected(String)
    case unbalanced
    case divisionByZero
    case notFinite
}

public enum Calculator {
    public static let maxLength = 200
    static let maxDepth = 20

    public struct Result: Equatable, Sendable {
        /// The sum as read, e.g. "12 × 7.5".
        public let expression: String
        public let value: Double
    }

    /// Evaluates `+ - * / ^ ( ) %` on decimal numbers written with a dot. `×`, `÷` and `−` are
    /// accepted too. `%` after a number divides it by 100. Powers bind tighter than a leading
    /// minus (-2^2 is -4) and group from the right (2^3^2 is 2^9).
    public static func evaluate(_ text: String) throws(CalculationError) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard trimmed.count <= maxLength else { throw .tooLong }
        var parser = Parser(tokens: try tokens(trimmed))
        let value = try parser.expression(depth: 0)
        guard parser.index == parser.tokens.count else { throw .unexpected(parser.tokens[parser.index].text) }
        guard value.isFinite else { throw .notFinite }
        return Result(expression: parser.tokens.map(\.text).joined(separator: " "), value: value == 0 ? 0 : value)
    }

    struct Token: Equatable {
        enum Kind: Equatable { case number(Double), plus, minus, times, divide, power, percent, open, close }
        let kind: Kind
        let text: String
    }

    static func tokens(_ text: String) throws(CalculationError) -> [Token] {
        var result: [Token] = []
        var chars = Array(text)[...]
        while let char = chars.first {
            if char.isWhitespace { chars.removeFirst(); continue }
            if char.isASCII, char.isNumber || char == "." {
                var digits = ""
                while let next = chars.first, next.isASCII, next.isNumber || next == "." {
                    digits.append(next)
                    chars.removeFirst()
                }
                guard digits.filter({ $0 == "." }).count <= 1, digits != ".", let number = Double(digits) else {
                    throw .unexpected(digits)
                }
                result.append(Token(kind: .number(number), text: digits))
                continue
            }
            let kind: Token.Kind
            let shown: String
            switch char {
            case "+": kind = .plus; shown = "+"
            case "-", "−", "–": kind = .minus; shown = "-"
            case "*", "×", "·": kind = .times; shown = "×"
            case "/", "÷": kind = .divide; shown = "÷"
            case "^": kind = .power; shown = "^"
            case "%": kind = .percent; shown = "%"
            case "(": kind = .open; shown = "("
            case ")": kind = .close; shown = ")"
            default: throw .unexpected(String(char))
            }
            result.append(Token(kind: kind, text: shown))
            chars.removeFirst()
        }
        return result
    }

    struct Parser {
        let tokens: [Token]
        var index = 0

        private var next: Token.Kind? { index < tokens.count ? tokens[index].kind : nil }

        private mutating func take(_ kind: Token.Kind) -> Bool {
            guard next == kind else { return false }
            index += 1
            return true
        }

        mutating func expression(depth: Int) throws(CalculationError) -> Double {
            guard depth <= Calculator.maxDepth else { throw .tooLong }
            var value = try term(depth: depth)
            while true {
                if take(.plus) { value += try term(depth: depth) }
                else if take(.minus) { value -= try term(depth: depth) }
                else { return value }
            }
        }

        private mutating func term(depth: Int) throws(CalculationError) -> Double {
            var value = try unary(depth: depth)
            while true {
                if take(.times) { value *= try unary(depth: depth) }
                else if take(.divide) {
                    let divisor = try unary(depth: depth)
                    guard divisor != 0 else { throw .divisionByZero }
                    value /= divisor
                } else { return value }
            }
        }

        private mutating func unary(depth: Int) throws(CalculationError) -> Double {
            guard depth <= Calculator.maxDepth else { throw .tooLong }
            if take(.minus) { return -(try unary(depth: depth + 1)) }
            if take(.plus) { return try unary(depth: depth + 1) }
            return try power(depth: depth)
        }

        private mutating func power(depth: Int) throws(CalculationError) -> Double {
            let base = try postfix(depth: depth)
            guard take(.power) else { return base }
            let exponent = try unary(depth: depth + 1)
            let value = pow(base, exponent)
            guard value.isFinite else { throw .notFinite }
            return value
        }

        private mutating func postfix(depth: Int) throws(CalculationError) -> Double {
            var value = try primary(depth: depth)
            while take(.percent) { value /= 100 }
            return value
        }

        private mutating func primary(depth: Int) throws(CalculationError) -> Double {
            guard let kind = next else { throw .unexpected("end") }
            if case .number(let number) = kind {
                index += 1
                return number
            }
            if take(.open) {
                let value = try expression(depth: depth + 1)
                guard take(.close) else { throw .unbalanced }
                return value
            }
            if kind == .close { throw .unbalanced }
            throw .unexpected(tokens[index].text)
        }
    }

    /// Up to `digits` significant digits, no trailing zeros, no exponent for everyday sizes.
    public static func text(_ value: Double, digits: Int = 10) -> String {
        let value = value == 0 ? 0 : value
        let magnitude = abs(value)
        if magnitude != 0, magnitude < 1e-6 || magnitude >= 1e15 {
            return String(format: "%.\(digits - 1)e", value).replacingOccurrences(of: #"\.?0+e"#, with: "e", options: .regularExpression)
        }
        let decimals = magnitude == 0 ? 0 : max(0, digits - 1 - Int(floor(log10(magnitude))))
        var out = String(format: "%.\(min(decimals, 15))f", value)
        if out.contains(".") {
            while out.hasSuffix("0") { out.removeLast() }
            if out.hasSuffix(".") { out.removeLast() }
        }
        return out == "-0" ? "0" : out
    }
}

// MARK: Units

public enum UnitKind: String, Sendable {
    case length, mass, volume, temperature, speed, area, time
}

public struct ConversionUnit: Equatable, Sendable {
    public let symbol: String
    public let kind: UnitKind
    /// Multiply by this to get the kind's base unit (metre, kilogram, litre, m/s, m², second).
    /// Not used for temperature.
    let toBase: Double
}

public enum UnitConversion {
    /// Symbols and the names the agent may pass, lower-cased. US customary for cups, pints,
    /// gallons and fluid ounces; "imperial gallon" (uk gal) separately.
    static let table: [(ConversionUnit, [String])] = [
        (ConversionUnit(symbol: "mm", kind: .length, toBase: 0.001), ["mm", "millimetre", "millimetres", "millimeter", "millimeters"]),
        (ConversionUnit(symbol: "cm", kind: .length, toBase: 0.01), ["cm", "centimetre", "centimetres", "centimeter", "centimeters"]),
        (ConversionUnit(symbol: "m", kind: .length, toBase: 1), ["m", "metre", "metres", "meter", "meters"]),
        (ConversionUnit(symbol: "km", kind: .length, toBase: 1_000), ["km", "kilometre", "kilometres", "kilometer", "kilometers"]),
        (ConversionUnit(symbol: "in", kind: .length, toBase: 0.0254), ["in", "inch", "inches", "\""]),
        (ConversionUnit(symbol: "ft", kind: .length, toBase: 0.3048), ["ft", "foot", "feet", "'"]),
        (ConversionUnit(symbol: "yd", kind: .length, toBase: 0.9144), ["yd", "yard", "yards"]),
        (ConversionUnit(symbol: "mi", kind: .length, toBase: 1_609.344), ["mi", "mile", "miles"]),
        (ConversionUnit(symbol: "nmi", kind: .length, toBase: 1_852), ["nmi", "nautical mile", "nautical miles"]),

        (ConversionUnit(symbol: "mg", kind: .mass, toBase: 0.000_001), ["mg", "milligram", "milligrams"]),
        (ConversionUnit(symbol: "g", kind: .mass, toBase: 0.001), ["g", "gram", "grams", "gramme", "grammes"]),
        (ConversionUnit(symbol: "kg", kind: .mass, toBase: 1), ["kg", "kilogram", "kilograms", "kilo", "kilos"]),
        (ConversionUnit(symbol: "t", kind: .mass, toBase: 1_000), ["t", "tonne", "tonnes", "metric ton", "metric tons"]),
        (ConversionUnit(symbol: "oz", kind: .mass, toBase: 0.028_349_523_125), ["oz", "ounce", "ounces"]),
        (ConversionUnit(symbol: "lb", kind: .mass, toBase: 0.453_592_37), ["lb", "lbs", "pound", "pounds"]),
        (ConversionUnit(symbol: "st", kind: .mass, toBase: 6.350_293_18), ["st", "stone", "stones"]),

        (ConversionUnit(symbol: "ml", kind: .volume, toBase: 0.001), ["ml", "millilitre", "millilitres", "milliliter", "milliliters"]),
        (ConversionUnit(symbol: "l", kind: .volume, toBase: 1), ["l", "litre", "litres", "liter", "liters"]),
        (ConversionUnit(symbol: "tsp", kind: .volume, toBase: 0.004_928_921_593_75), ["tsp", "teaspoon", "teaspoons"]),
        (ConversionUnit(symbol: "tbsp", kind: .volume, toBase: 0.014_786_764_781_25), ["tbsp", "tablespoon", "tablespoons"]),
        (ConversionUnit(symbol: "fl oz", kind: .volume, toBase: 0.029_573_529_562_5), ["fl oz", "floz", "fluid ounce", "fluid ounces"]),
        (ConversionUnit(symbol: "cup", kind: .volume, toBase: 0.236_588_236_5), ["cup", "cups"]),
        (ConversionUnit(symbol: "pt", kind: .volume, toBase: 0.473_176_473), ["pt", "pint", "pints"]),
        (ConversionUnit(symbol: "gal", kind: .volume, toBase: 3.785_411_784), ["gal", "gallon", "gallons", "us gallon", "us gallons"]),
        (ConversionUnit(symbol: "uk gal", kind: .volume, toBase: 4.546_09), ["uk gal", "imperial gallon", "imperial gallons"]),

        (ConversionUnit(symbol: "°C", kind: .temperature, toBase: 1), ["c", "°c", "celsius", "degrees celsius"]),
        (ConversionUnit(symbol: "°F", kind: .temperature, toBase: 1), ["f", "°f", "fahrenheit", "degrees fahrenheit"]),
        (ConversionUnit(symbol: "K", kind: .temperature, toBase: 1), ["k", "kelvin", "kelvins"]),

        (ConversionUnit(symbol: "m/s", kind: .speed, toBase: 1), ["m/s", "metres per second", "meters per second"]),
        (ConversionUnit(symbol: "km/h", kind: .speed, toBase: 1_000.0 / 3_600), ["km/h", "kmh", "kph", "kilometres per hour", "kilometers per hour"]),
        (ConversionUnit(symbol: "mph", kind: .speed, toBase: 1_609.344 / 3_600), ["mph", "miles per hour"]),
        (ConversionUnit(symbol: "kn", kind: .speed, toBase: 1_852.0 / 3_600), ["kn", "knot", "knots"]),

        (ConversionUnit(symbol: "m²", kind: .area, toBase: 1), ["m2", "m²", "sq m", "square metre", "square metres", "square meter", "square meters"]),
        (ConversionUnit(symbol: "km²", kind: .area, toBase: 1_000_000), ["km2", "km²", "sq km", "square kilometre", "square kilometres", "square kilometer", "square kilometers"]),
        (ConversionUnit(symbol: "ft²", kind: .area, toBase: 0.092_903_04), ["ft2", "ft²", "sq ft", "square foot", "square feet"]),
        (ConversionUnit(symbol: "ha", kind: .area, toBase: 10_000), ["ha", "hectare", "hectares"]),
        (ConversionUnit(symbol: "acre", kind: .area, toBase: 4_046.856_422_4), ["acre", "acres", "ac"]),

        (ConversionUnit(symbol: "s", kind: .time, toBase: 1), ["s", "sec", "second", "seconds"]),
        (ConversionUnit(symbol: "min", kind: .time, toBase: 60), ["min", "mins", "minute", "minutes"]),
        (ConversionUnit(symbol: "h", kind: .time, toBase: 3_600), ["h", "hr", "hrs", "hour", "hours"]),
        (ConversionUnit(symbol: "day", kind: .time, toBase: 86_400), ["d", "day", "days"]),
        (ConversionUnit(symbol: "week", kind: .time, toBase: 604_800), ["wk", "week", "weeks"]),
    ]

    public static func unit(named name: String) -> ConversionUnit? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return table.first { $0.1.contains(key) }?.0
    }

    public enum Failure: Error, Equatable, Sendable {
        case unknownUnit(String)
        case differentKinds(ConversionUnit, ConversionUnit)
        case notFinite
        /// Below absolute zero, or a negative length, mass, volume, area or time.
        case impossible
    }

    public static func convert(_ value: Double, from: String, to: String) -> Swift.Result<Double, Failure> {
        guard let source = unit(named: from) else { return .failure(.unknownUnit(from)) }
        guard let target = unit(named: to) else { return .failure(.unknownUnit(to)) }
        guard source.kind == target.kind else { return .failure(.differentKinds(source, target)) }
        guard value.isFinite else { return .failure(.notFinite) }
        let result: Double
        if source.kind == .temperature {
            let kelvin: Double
            switch source.symbol {
            case "°C": kelvin = value + 273.15
            case "°F": kelvin = (value - 32) * 5 / 9 + 273.15
            default: kelvin = value
            }
            guard kelvin >= -1e-9 else { return .failure(.impossible) }
            switch target.symbol {
            case "°C": result = kelvin - 273.15
            case "°F": result = (kelvin - 273.15) * 9 / 5 + 32
            default: result = kelvin
            }
        } else {
            guard value >= 0 || source.kind == .speed else { return .failure(.impossible) }
            result = value * source.toBase / target.toBase
        }
        guard result.isFinite else { return .failure(.notFinite) }
        return .success(abs(result) < 1e-12 ? 0 : result)
    }
}

// MARK: Tool calls

public struct UnitConversionRequest: Equatable, Sendable {
    public let value: Double
    public let from: String
    public let to: String
}

extension VoiceToolRequest {
    static func parseCalculate(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let expression = args.text("expression") else { return .invalid(name: name, reason: "missing expression") }
        return .calculate(expression: expression)
    }

    static func parseConversion(_ args: Arguments, name: String) -> VoiceToolRequest {
        let value = args.number("value") ?? args.text("value").flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard let value, value.isFinite else { return .invalid(name: name, reason: "value must be a number written with a dot, e.g. 2.5") }
        guard let from = args.text("from") else { return .invalid(name: name, reason: "missing from") }
        guard let to = args.text("to") else { return .invalid(name: name, reason: "missing to") }
        return .convertUnits(UnitConversionRequest(value: value, from: from, to: to))
    }
}

extension VoiceToolReply {
    public static func calculation(_ expression: String) -> String {
        do {
            let result = try Calculator.evaluate(expression)
            return "result: \(result.expression) = \(Calculator.text(result.value)). Calculated by the app; say this number, don't work it out again."
        } catch {
            let reason: String
            switch error {
            case .empty: reason = "the expression is empty"
            case .tooLong: reason = "the expression is too long or nested too deeply"
            case .unexpected(let text): reason = "it can't read \"\(text)\"; use only numbers with a dot for decimals, + - * / ^ % and brackets"
            case .unbalanced: reason = "the brackets don't match"
            case .divisionByZero: reason = "it divides by zero"
            case .notFinite: reason = "the result is too large"
            }
            return "failed: not calculated, \(reason). Fix the expression and try again, or tell the user."
        }
    }

    public static func conversion(_ request: UnitConversionRequest) -> String {
        switch UnitConversion.convert(request.value, from: request.from, to: request.to) {
        case .success(let result):
            let from = UnitConversion.unit(named: request.from)?.symbol ?? request.from
            let to = UnitConversion.unit(named: request.to)?.symbol ?? request.to
            return "converted: \(Calculator.text(request.value)) \(from) = \(Calculator.text(result, digits: 7)) \(to). Calculated by the app; say this number, don't work it out again."
        case .failure(.unknownUnit(let name)):
            return "failed: the app doesn't know the unit \"\(name)\". Use a standard symbol such as km, mi, kg, lb, l, cup, °C, °F, km/h, m², h. Currencies can't be converted."
        case .failure(.differentKinds(let a, let b)):
            return "failed: \(a.symbol) is a \(a.kind.rawValue) and \(b.symbol) is a \(b.kind.rawValue); they can't be converted into each other."
        case .failure(.notFinite):
            return "failed: the number is too large to convert."
        case .failure(.impossible):
            return "failed: that value isn't possible (below absolute zero, or a negative amount). Nothing was converted."
        }
    }
}
