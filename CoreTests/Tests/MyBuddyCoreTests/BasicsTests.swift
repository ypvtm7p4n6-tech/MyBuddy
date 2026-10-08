import XCTest
@testable import MyBuddyCore

final class YearMonthTests: XCTestCase {
    func testAddingAcrossYears() {
        XCTAssertEqual(oct2026.adding(3), YearMonth(year: 2027, month: 1))
        XCTAssertEqual(oct2026.adding(-10), YearMonth(year: 2025, month: 12))
        XCTAssertEqual(YearMonth(year: 2026, month: 1).adding(-1), YearMonth(year: 2025, month: 12))
        XCTAssertEqual(aug2026.months(to: oct2026), 2)
        XCTAssertEqual(oct2026.months(to: aug2026), -2)
    }

    func testOverflowingMonthNormalises() {
        XCTAssertEqual(YearMonth(year: 2026, month: 13), YearMonth(year: 2027, month: 1))
    }

    func testKeyRoundTrip() {
        XCTAssertEqual(aug2026.key, "2026-08")
        XCTAssertEqual(YearMonth(key: "2026-08"), aug2026)
        XCTAssertNil(YearMonth(key: "2026-13"))
        XCTAssertNil(YearMonth(key: "kapot"))
    }

    func testOrderingAndRange() {
        XCTAssertTrue(aug2026 < oct2026)
        XCTAssertEqual(aug2026.range(count: 3), [aug2026, sep2026, oct2026])
        XCTAssertEqual(aug2026.range(count: 0), [])
    }

    func testPeriods() {
        XCTAssertEqual(PeriodMode.month.months(containing: oct2026), [oct2026])
        XCTAssertEqual(PeriodMode.halfYear.months(containing: oct2026).first, YearMonth(year: 2026, month: 7))
        XCTAssertEqual(PeriodMode.halfYear.months(containing: oct2026).count, 6)
        XCTAssertEqual(PeriodMode.halfYear.months(containing: aug2026).last, YearMonth(year: 2026, month: 12))
        XCTAssertEqual(PeriodMode.year.months(containing: oct2026).first, YearMonth(year: 2026, month: 1))
        XCTAssertEqual(PeriodMode.year.months(containing: oct2026).count, 12)
    }

    func testDateMembership() {
        XCTAssertTrue(oct2026.contains(day(oct2026, 15)))
        XCTAssertFalse(oct2026.contains(day(sep2026, 28)))
        XCTAssertEqual(YearMonth(date: day(sep2026, 30)), sep2026)
    }

    func testCodable() throws {
        let data = try JSONEncoder().encode([oct2026])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"2026-10\"]")
        XCTAssertEqual(try JSONDecoder().decode([YearMonth].self, from: data), [oct2026])
    }
}

final class AmountParserTests: XCTestCase {
    func testDutchInput() {
        XCTAssertEqual(AmountParser.parse("12,5"), 12.5)
        XCTAssertEqual(AmountParser.parse("1.234,56"), 1234.56)
        XCTAssertEqual(AmountParser.parse("€ 99"), 99)
        XCTAssertEqual(AmountParser.parse("6,5%"), 6.5)
    }

    func testDotInput() {
        XCTAssertEqual(AmountParser.parse("12.5"), 12.5)
        XCTAssertEqual(AmountParser.parse("1.234"), 1234)
        XCTAssertEqual(AmountParser.parse("1.234.567"), 1234567)
        XCTAssertEqual(AmountParser.parse("0.125"), 0.125)
    }

    func testGarbage() {
        XCTAssertNil(AmountParser.parse(""))
        XCTAssertNil(AmountParser.parse("abc"))
        XCTAssertNil(AmountParser.parse("  "))
    }
}

final class FormattingTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(Fmt.duration(months: 0), "nu al bereikt")
        XCTAssertEqual(Fmt.duration(months: 1), "1 maand")
        XCTAssertEqual(Fmt.duration(months: 5), "5 maanden")
        XCTAssertEqual(Fmt.duration(months: 12), "1 jaar")
        XCTAssertEqual(Fmt.duration(months: 40), "3 jaar en 4 maanden")
    }

    func testMonthNames() {
        XCTAssertEqual(Fmt.month(oct2026), "oktober 2026")
        XCTAssertEqual(Fmt.shortMonth(aug2026), "aug")
        XCTAssertEqual(Fmt.period(.halfYear, containing: oct2026), "2e halfjaar 2026")
        XCTAssertEqual(Fmt.period(.year, containing: oct2026), "2026")
    }

    func testPercent() {
        XCTAssertTrue(Fmt.percent(0.065).contains("6,5"))
    }
}
