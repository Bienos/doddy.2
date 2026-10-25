import XCTest
@testable import DoddyCore

/// Shopping list+ stage 1 (ADR-631): quantities read from an item's words, never rewritten.
final class ListQuantityTests: XCTestCase {
    private func read(_ text: String) -> ListItemWords { ListItemWords.read(text) }

    private func assertQuantity(
        _ text: String, product: String, amount: Decimal, unit: ListUnit?, expectQuantity: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let words = read(text)
        XCTAssertEqual(words.product, product, "product of \(text)", file: file, line: line)
        XCTAssertEqual(words.quantity, expectQuantity ? ListQuantity(amount: amount, unit: unit) : nil, "quantity of \(text)", file: file, line: line)
    }

    private func d(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    private func assertNoQuantity(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let words = read(text)
        XCTAssertNil(words.quantity, "\(text) should have no quantity", file: file, line: line)
        XCTAssertEqual(words.product, ListText.cleaned(text) ?? text, file: file, line: line)
    }

    func testNumberFirstWithUnit() {
        assertQuantity("2 l mleka", product: "mleka", amount: 2, unit: .litre)
        assertQuantity("500g mąki", product: "mąki", amount: 500, unit: .gram)
        assertQuantity("1,5 kg ziemniaków", product: "ziemniaków", amount: 1.5, unit: .kilogram)
        assertQuantity("1.5 kg potatoes", product: "potatoes", amount: 1.5, unit: .kilogram)
        assertQuantity("20 dag szynki", product: "szynki", amount: 20, unit: .decagram)
        assertQuantity("330 ml soku", product: "soku", amount: 330, unit: .millilitre)
        assertQuantity("2 opakowania makaronu", product: "makaronu", amount: 2, unit: .pack)
        assertQuantity("6 puszek pomidorów", product: "pomidorów", amount: 6, unit: .can)
        assertQuantity("2 butelki wody", product: "wody", amount: 2, unit: .bottle)
        assertQuantity("10 szt. jajek", product: "jajek", amount: 10, unit: .piece)
        assertQuantity("2 packs of bananas", product: "bananas", amount: 2, unit: .pack)
    }

    func testBareCountAndMultiplierFirst() {
        assertQuantity("3 jajka", product: "jajka", amount: 3, unit: nil)
        assertQuantity("2x mleko", product: "mleko", amount: 2, unit: nil)
        assertQuantity("2 x mleko", product: "mleko", amount: 2, unit: nil)
        assertQuantity("2 × mleko", product: "mleko", amount: 2, unit: nil)
        assertQuantity("2X Milk", product: "Milk", amount: 2, unit: nil)
    }

    func testNumberWords() {
        assertQuantity("dwa mleka", product: "mleka", amount: 2, unit: nil)
        assertQuantity("dwie paczki makaronu", product: "makaronu", amount: 2, unit: .pack)
        assertQuantity("pół kilo sera", product: "sera", amount: 0.5, unit: .kilogram)
        assertQuantity("półtorej kilo mąki", product: "mąki", amount: 1.5, unit: .kilogram)
    }

    func testFractionWithoutUnitIsNotACount() {
        // "pół sera" has no unit: half of a cheese is not a count. Nor is "1,5 mleka".
        assertNoQuantity("pół sera")
        assertNoQuantity("1,5 mleka")
        // "litra" (genitive) is not a unit word, so "półtora" has no unit and is no count.
        assertNoQuantity("półtora litra mleka")
    }

    func testUnitOrMultiplierLast() {
        assertQuantity("mleko 2 l", product: "mleko", amount: 2, unit: .litre)
        assertQuantity("mleko 2l", product: "mleko", amount: 2, unit: .litre)
        assertQuantity("jajka 10 szt.", product: "jajka", amount: 10, unit: .piece)
        assertQuantity("mleko x2", product: "mleko", amount: 2, unit: nil)
        assertQuantity("mleko ×2", product: "mleko", amount: 2, unit: nil)
        assertQuantity("mleko x 2", product: "mleko", amount: 2, unit: nil)
        assertQuantity("mleko 2x", product: "mleko", amount: 2, unit: nil)
        assertQuantity("Pepsi 2,25 l", product: "Pepsi", amount: 2.25, unit: .litre)
        assertQuantity("Nivea krem 50 ml", product: "Nivea krem", amount: 50, unit: .millilitre)
    }

    func testNamesWithNumbersAreNotQuantities() {
        assertNoQuantity("7up")
        assertNoQuantity("7up zero")
        assertNoQuantity("WD-40")
        assertNoQuantity("iPhone 15")
        assertNoQuantity("Nivea 50")
        assertNoQuantity("mleko 3,2%")
        assertNoQuantity("mleko 3,2 %")
        assertNoQuantity("3D puzzle")
        assertNoQuantity("1000 wysp sos")
        assertNoQuantity("koszulka xl")
        assertNoQuantity("2024 kalendarz")
    }

    func testNothingButAQuantityIsLeftAlone() {
        assertNoQuantity("2 litry")
        assertNoQuantity("2")
        assertNoQuantity("x2")
        assertNoQuantity("2 kg 3")
        assertNoQuantity("mleko")
    }

    func testLimits() {
        assertNoQuantity("0 jajek")
        assertNoQuantity("10000 g mąki")
        assertNoQuantity("1,2345 kg mąki")
        assertNoQuantity("12345 g mąki")
        assertQuantity("9999 g mąki", product: "mąki", amount: 9999, unit: .gram)
        assertQuantity("99 jajek", product: "jajek", amount: 99, unit: nil)
        assertNoQuantity("100 jajek")
    }

    func testProductKeepsTheUsersWords() {
        // Only the quantity is taken out; case, accents and word order stay.
        assertQuantity("2 l Mleka Łaciatego", product: "Mleka Łaciatego", amount: 2, unit: .litre)
        assertQuantity("  2 l   mleka  ", product: "mleka", amount: 2, unit: .litre)
    }

    func testDisplay() {
        XCTAssertEqual(ListQuantity(amount: 2, unit: .litre).display(polish: true), "2 l")
        XCTAssertEqual(ListQuantity(amount: 1.5, unit: .kilogram).display(polish: true), "1,5 kg")
        XCTAssertEqual(ListQuantity(amount: 1.5, unit: .kilogram).display(polish: false), "1.5 kg")
        XCTAssertEqual(ListQuantity(amount: 3, unit: nil).display(polish: true), "×3")
        XCTAssertEqual(ListQuantity(amount: 10, unit: .piece).display(polish: true), "10 szt.")
        XCTAssertEqual(ListQuantity(amount: 10, unit: .piece).display(polish: false), "10 pcs")
        XCTAssertEqual(ListQuantity(amount: 2, unit: .pack).display(polish: true), "2 op.")
    }

    func testTotalAddsOnlyTheSameKind() {
        let total = ListQuantity.total([
            ListQuantity(amount: 500, unit: .gram),
            ListQuantity(amount: 1, unit: .kilogram),
            ListQuantity(amount: 2, unit: .litre),
            ListQuantity(amount: 250, unit: .millilitre),
            ListQuantity(amount: 3, unit: nil),
            ListQuantity(amount: 2, unit: .piece),
            ListQuantity(amount: 1, unit: .pack),
            ListQuantity(amount: 20, unit: .decagram),
        ])
        XCTAssertEqual(total, [
            ListQuantity(amount: d("1.7"), unit: .kilogram),
            ListQuantity(amount: 2.25, unit: .litre),
            ListQuantity(amount: 5, unit: .piece),
            ListQuantity(amount: 1, unit: .pack),
        ])
        XCTAssertEqual(ListQuantity.total([ListQuantity(amount: 300, unit: .gram), ListQuantity(amount: 200, unit: .gram)]),
                       [ListQuantity(amount: 500, unit: .gram)])
        XCTAssertEqual(ListQuantity.total([]), [])
    }

    func testUnitWordsIgnoreCaseAccentsAndADot() {
        XCTAssertEqual(ListUnit.named("KG"), .kilogram)
        XCTAssertEqual(ListUnit.named("szt."), .piece)
        XCTAssertEqual(ListUnit.named("Gramów"), .gram)
        XCTAssertEqual(ListUnit.named("opakowań"), .pack)
        XCTAssertNil(ListUnit.named("xl"))
        XCTAssertNil(ListUnit.named("%"))
    }
}
