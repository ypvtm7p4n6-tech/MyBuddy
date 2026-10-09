import XCTest
@testable import MyBuddyCore

/// `Fmt.euro` (bedragen onder 1 euro met centen) en de strikte `AmountParser`.
final class FmtEuroSmallAmountTests: XCTestCase {
    /// Zonder spaties (de formatter gebruikt harde spaties) en zonder de volgorde van teken en euroteken.
    private func compact(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private func assertEuro(_ value: Double, _ digits: String, negative: Bool = false,
                            file: StaticString = #filePath, line: UInt = #line) {
        let shown = compact(Fmt.euro(value))
        let expected = negative ? ["€-\(digits)", "-€\(digits)"] : ["€\(digits)"]
        XCTAssertTrue(expected.contains(shown), "\(value): \(shown), verwacht \(expected)", file: file, line: line)
    }

    func testAmountsUnderOneEuroShowTheirCents() {
        assertEuro(0.4, "0,40")
        assertEuro(0.5, "0,50")
        assertEuro(0.99, "0,99")
        assertEuro(0.01, "0,01")
        assertEuro(0.05, "0,05")
        assertEuro(-0.4, "0,40", negative: true)
        assertEuro(-0.99, "0,99", negative: true)
    }

    func testWholeEurosStayWholeEuros() {
        assertEuro(1.4, "1")
        assertEuro(1.5, "2")
        assertEuro(2.49, "2")
        assertEuro(1234.56, "1.235")
        assertEuro(1_000_000, "1.000.000")
        assertEuro(-1234.56, "1.235", negative: true)
        assertEuro(-1.5, "2", negative: true)
    }

    func testZeroAndTinyAmountsAreNeverMinusZero() {
        assertEuro(0, "0")
        assertEuro(-0.0, "0")
        // Minder dan een halve cent rondt af op niets.
        assertEuro(0.0001, "0")
        assertEuro(-0.0001, "0")
        assertEuro(0.004, "0")
        assertEuro(-0.004, "0")
        XCTAssertFalse(Fmt.euro(-0.0001).contains("-"))
        // Net genoeg voor een cent.
        assertEuro(0.006, "0,01")
    }

    func testAnAmountThatRoundsUpToOneEuroIsOneEuro() {
        assertEuro(0.996, "1")
        assertEuro(-0.996, "1", negative: true)
    }

    func testOtherFormattersKeepTheirBehaviour() {
        XCTAssertEqual(compact(Fmt.euroWhole(0.4)), "€0")
        XCTAssertEqual(compact(Fmt.euroWhole(0.5)), "€1")
        XCTAssertEqual(compact(Fmt.euroExact(0.4)), "€0,40")
        XCTAssertEqual(compact(Fmt.euroExact(1234.5)), "€1.234,50")
    }
}

final class StrictAmountParserTests: XCTestCase {
    func testGoodInputStillWorks() {
        XCTAssertEqual(AmountParser.parse("1.234,56"), 1234.56)
        XCTAssertEqual(AmountParser.parse("-5"), -5)
        XCTAssertEqual(AmountParser.parse("€ 12,5"), 12.5)
        XCTAssertEqual(AmountParser.parse("1 234,5"), 1234.5)
        XCTAssertEqual(AmountParser.parse("12,5"), 12.5)
        XCTAssertEqual(AmountParser.parse("12.5"), 12.5)
        XCTAssertEqual(AmountParser.parse("1.234"), 1234)
        XCTAssertEqual(AmountParser.parse("1.234.567"), 1_234_567)
        XCTAssertEqual(AmountParser.parse("0"), 0)
        XCTAssertEqual(AmountParser.parse("-€ 1.000,25"), -1000.25)
        XCTAssertEqual(AmountParser.parse("  42  "), 42)
        XCTAssertEqual(AmountParser.parse(",5"), 0.5)
        // Harde spaties zoals in een opgemaakt bedrag, ook de smalle.
        XCTAssertEqual(AmountParser.parse("€\u{00A0}1.235"), 1235)
        XCTAssertEqual(AmountParser.parse("1\u{202F}234,5"), 1234.5)
        // Het procentteken (procentvelden) wordt genegeerd.
        XCTAssertEqual(AmountParser.parse("6,5%"), 6.5)
    }

    func testLettersAreRejected() {
        for text in ["inf", "-inf", "Inf", "infinity", "nan", "NaN", "-nan", "1e999", "1e3", "1E3", "1e-3", "e", "0x10", "0X1F", "0b11",
                     "abc", "12abc", "abc12", "1,5 euro", "€12k", "1_000", "٣٤"] {
            XCTAssertNil(AmountParser.parse(text), text)
        }
    }

    func testOtherCharactersAreRejected() {
        for text in ["+5", "5+3", "(5)", "5/2", "5*2", "1;2", "'5'", "\"5\"", "5!", "−5", "5-", "--5", "1-2", "-", ".", ",", "-.", "€", "%"] {
            XCTAssertNil(AmountParser.parse(text), text)
        }
    }

    func testEmptyInputIsRejected() {
        XCTAssertNil(AmountParser.parse(""))
        XCTAssertNil(AmountParser.parse("   "))
        XCTAssertNil(AmountParser.parse("\n"))
        XCTAssertNil(AmountParser.parse("€ "))
    }

    func testResultIsAlwaysFiniteAndBelowATrillion() {
        XCTAssertEqual(AmountParser.parse("1000000000000"), 1e12)
        XCTAssertEqual(AmountParser.parse("-1000000000000"), -1e12)
        XCTAssertEqual(AmountParser.parse("1.000.000.000.000"), 1e12)
        XCTAssertEqual(AmountParser.parse("999999999999,99"), 999_999_999_999.99)
        XCTAssertNil(AmountParser.parse("1000000000001"))
        XCTAssertNil(AmountParser.parse("-1000000000001"))
        XCTAssertNil(AmountParser.parse("1.000.000.000.001"))
        XCTAssertNil(AmountParser.parse("9999999999999999999999"))
        // Een absurd lange reeks cijfers rekent niet door naar oneindig.
        XCTAssertNil(AmountParser.parse(String(repeating: "9", count: 400)))
        XCTAssertNil(AmountParser.parse("-" + String(repeating: "9", count: 400)))
        XCTAssertNil(AmountParser.parse(String(repeating: "9", count: 400) + ",5"))
        XCTAssertEqual(AmountParser.maxAbsolute, 1e12)
    }

    func testAcceptedValuesCanAlwaysBeSaved() throws {
        // Wat de parser teruggeeft, kan door de JSON-codering (die niet-eindige getallen weigert).
        for text in ["12,5", "-5", "1.234,56", "1000000000000", "0"] {
            let value = try XCTUnwrap(AmountParser.parse(text), text)
            var d = FinanceData(startMonth: oct2026)
            d.salary.fixedMonthly = value
            XCTAssertNoThrow(try FinanceStorage.makeFileEncoder().encode(d), text)
        }
    }
}
