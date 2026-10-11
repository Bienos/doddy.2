import XCTest
@testable import DoddyCore

/// Sums and unit conversions on the iPhone (ADR-266): arithmetic only, exact factors, and a
/// reply the agent reads back instead of working the numbers out itself.
final class CalculatorTests: XCTestCase {
    private func value(_ text: String) throws -> Double {
        try Calculator.evaluate(text).value
    }

    private func error(_ text: String) -> CalculationError? {
        do {
            _ = try Calculator.evaluate(text)
            return nil
        } catch {
            return error
        }
    }

    // MARK: Arithmetic

    func testOrderOfOperationsBracketsPowersAndPercent() throws {
        XCTAssertEqual(try value("2 + 3 * 4"), 14)
        XCTAssertEqual(try value("(2 + 3) * 4"), 20)
        XCTAssertEqual(try value("10 - 4 - 3"), 3)
        XCTAssertEqual(try value("100 / 10 / 5"), 2)
        XCTAssertEqual(try value("2^3^2"), 512)
        XCTAssertEqual(try value("-2^2"), -4)
        XCTAssertEqual(try value("(-2)^2"), 4)
        XCTAssertEqual(try value("2^-1"), 0.5)
        XCTAssertEqual(try value("--3"), 3)
        XCTAssertEqual(try value("80 * 15%"), 12)
        XCTAssertEqual(try value("50%"), 0.5)
        XCTAssertEqual(try value("(124.50 + 37) / 3"), 53.833333333333336)
        XCTAssertEqual(try value(".5 + 1"), 1.5)
        XCTAssertEqual(try value("12 × 7.5 ÷ 3 − 1"), 29)
    }

    func testTheReplyShowsTheSumAsReadAndARoundedResult() {
        XCTAssertEqual(
            VoiceToolReply.calculation("(124.50+37)/3"),
            "result: ( 124.50 + 37 ) ÷ 3 = 53.83333333. Calculated by the app; say this number, don't work it out again.")
        XCTAssertEqual(
            VoiceToolReply.calculation("0.1 + 0.2"),
            "result: 0.1 + 0.2 = 0.3. Calculated by the app; say this number, don't work it out again.")
        XCTAssertTrue(VoiceToolReply.calculation("1 - 1").contains("= 0."))
    }

    func testAnythingButArithmeticIsRefused() {
        XCTAssertEqual(error(""), .empty)
        XCTAssertEqual(error("   "), .empty)
        XCTAssertEqual(error("2 +"), .unexpected("end"))
        XCTAssertEqual(error("2 3"), .unexpected("3"))
        XCTAssertEqual(error("(2 + 3"), .unbalanced)
        XCTAssertEqual(error("2 + 3)"), .unexpected(")"))
        XCTAssertEqual(error("1.2.3"), .unexpected("1.2.3"))
        XCTAssertEqual(error("1,5 + 2"), .unexpected(","))
        XCTAssertEqual(error("12:30"), .unexpected(":"))
        XCTAssertEqual(error("sqrt(4)"), .unexpected("s"))
        XCTAssertEqual(error("$5 + 2"), .unexpected("$"))
        XCTAssertEqual(error("1 / 0"), .divisionByZero)
        XCTAssertEqual(error("1 / (2 - 2)"), .divisionByZero)
        XCTAssertEqual(error("10^400"), .notFinite)
        XCTAssertEqual(error(String(repeating: "1+", count: 101) + "1"), .tooLong)
        XCTAssertEqual(error(String(repeating: "(", count: 30) + "1" + String(repeating: ")", count: 30)), .tooLong)
        XCTAssertEqual(error(String(repeating: "-", count: 30) + "1"), .tooLong)

        XCTAssertEqual(
            VoiceToolReply.calculation("1/0"),
            "failed: not calculated, it divides by zero. Fix the expression and try again, or tell the user.")
        XCTAssertTrue(VoiceToolReply.calculation("five plus 2").hasPrefix("failed: not calculated, it can't read \"f\""))
    }

    func testNumbersAreWrittenPlainly() {
        XCTAssertEqual(Calculator.text(90), "90")
        XCTAssertEqual(Calculator.text(-0.0), "0")
        XCTAssertEqual(Calculator.text(1_234_567.891), "1234567.891")
        XCTAssertEqual(Calculator.text(2.0 / 3), "0.6666666667")
        XCTAssertEqual(Calculator.text(8.046_72, digits: 7), "8.04672")
        XCTAssertEqual(Calculator.text(-12.5), "-12.5")
        XCTAssertEqual(Calculator.text(1e20), "1e+20")
        XCTAssertEqual(Calculator.text(2.5e-9), "2.5e-09")
    }

    // MARK: Units

    private func convert(_ value: Double, _ from: String, _ to: String) -> Double? {
        try? UnitConversion.convert(value, from: from, to: to).get()
    }

    func testExactFactorsAcrossKinds() {
        XCTAssertEqual(convert(5, "mi", "km")!, 8.04672, accuracy: 1e-9)
        XCTAssertEqual(convert(1, "inch", "cm")!, 2.54, accuracy: 1e-12)
        XCTAssertEqual(convert(10, "Kilograms", "lb")!, 22.046226218, accuracy: 1e-8)
        XCTAssertEqual(convert(1, "cup", "ml")!, 236.5882365, accuracy: 1e-7)
        XCTAssertEqual(convert(1, "uk gal", "l")!, 4.54609, accuracy: 1e-9)
        XCTAssertEqual(convert(100, "km/h", "mph")!, 62.137119224, accuracy: 1e-8)
        XCTAssertEqual(convert(1, "ha", "m2")!, 10_000, accuracy: 1e-9)
        XCTAssertEqual(convert(90, "min", "h")!, 1.5, accuracy: 1e-12)
        XCTAssertEqual(convert(1, "nautical mile", "m")!, 1_852, accuracy: 1e-9)
    }

    func testTemperatureIsNotAFactor() {
        XCTAssertEqual(convert(100, "C", "F")!, 212, accuracy: 1e-9)
        XCTAssertEqual(convert(-40, "°F", "celsius")!, -40, accuracy: 1e-9)
        XCTAssertEqual(convert(0, "K", "C")!, -273.15, accuracy: 1e-9)
        XCTAssertEqual(convert(350, "fahrenheit", "C")!, 176.666666667, accuracy: 1e-8)
        XCTAssertEqual(UnitConversion.convert(-300, from: "C", to: "K"), .failure(.impossible))
    }

    func testUnknownUnitsMismatchesAndImpossibleAmounts() {
        XCTAssertEqual(UnitConversion.convert(5, from: "furlong", to: "m"), .failure(.unknownUnit("furlong")))
        XCTAssertEqual(UnitConversion.convert(5, from: "USD", to: "EUR"), .failure(.unknownUnit("USD")))
        guard case .failure(.differentKinds(let a, let b)) = UnitConversion.convert(5, from: "kg", to: "l") else {
            return XCTFail("kg to l must be refused")
        }
        XCTAssertEqual([a.symbol, b.symbol], ["kg", "l"])
        XCTAssertEqual(UnitConversion.convert(-5, from: "kg", to: "lb"), .failure(.impossible))
        XCTAssertNotNil(convert(-10, "km/h", "m/s"))
    }

    func testTheReplyNamesTheUnitsAndRoundsForReading() {
        XCTAssertEqual(
            VoiceToolReply.conversion(UnitConversionRequest(value: 5, from: "miles", to: "kilometres")),
            "converted: 5 mi = 8.04672 km. Calculated by the app; say this number, don't work it out again.")
        XCTAssertEqual(
            VoiceToolReply.conversion(UnitConversionRequest(value: 350, from: "F", to: "C")),
            "converted: 350 °F = 176.6667 °C. Calculated by the app; say this number, don't work it out again.")
        XCTAssertEqual(
            VoiceToolReply.conversion(UnitConversionRequest(value: 5, from: "kg", to: "cup")),
            "failed: kg is a mass and cup is a volume; they can't be converted into each other.")
        XCTAssertTrue(VoiceToolReply.conversion(UnitConversionRequest(value: 20, from: "PLN", to: "EUR")).contains("Currencies can't be converted."))
    }

    // MARK: Tool calls

    func testParsingAndThatNoAppIsUsed() {
        func parse(_ name: String, _ json: String) -> VoiceToolRequest {
            VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8))
        }
        XCTAssertEqual(parse("calculate", #"{"expression":"2+2"}"#), .calculate(expression: "2+2"))
        XCTAssertEqual(parse("calculate", "{}"), .invalid(name: "calculate", reason: "missing expression"))
        XCTAssertEqual(
            parse("convert_units", #"{"value":2.5,"from":"kg","to":"lb"}"#),
            .convertUnits(UnitConversionRequest(value: 2.5, from: "kg", to: "lb")))
        XCTAssertEqual(
            parse("convert_units", #"{"value":"3","from":"mi","to":"km"}"#),
            .convertUnits(UnitConversionRequest(value: 3, from: "mi", to: "km")))
        XCTAssertEqual(
            parse("convert_units", #"{"value":"lots","from":"mi","to":"km"}"#),
            .invalid(name: "convert_units", reason: "value must be a number written with a dot, e.g. 2.5"))
        XCTAssertEqual(parse("convert_units", #"{"value":1,"to":"km"}"#), .invalid(name: "convert_units", reason: "missing from"))

        let sum = VoiceToolRequest.calculate(expression: "1+1")
        XCTAssertFalse(ConnectionPause.applies(to: sum))
        XCTAssertNil(ActivityRequest.describe(sum, calendar: .current))
        XCTAssertNil(VoiceConnection.serving("calculate"))
        XCTAssertNil(VoiceConnection.serving("convert_units"))
        // Translator mode runs no tools, sums included.
        XCTAssertFalse(TranslatorPolicy.allows(sum))
    }
}
