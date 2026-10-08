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

// MARK: - Dagen in de maand

final class YearMonthDayTests: XCTestCase {
    func testDayCountIncludingLeapYears() {
        XCTAssertEqual(YearMonth(year: 2026, month: 1).dayCount, 31)
        XCTAssertEqual(YearMonth(year: 2026, month: 2).dayCount, 28)
        XCTAssertEqual(YearMonth(year: 2028, month: 2).dayCount, 29)
        XCTAssertEqual(YearMonth(year: 2100, month: 2).dayCount, 28, "1900 en 2100 zijn geen schrikkeljaren")
        XCTAssertEqual(YearMonth(year: 2000, month: 2).dayCount, 29)
        XCTAssertEqual(YearMonth(year: 2026, month: 4).dayCount, 30)
        XCTAssertEqual(YearMonth(year: 2026, month: 9).dayCount, 30)
        XCTAssertEqual(YearMonth(year: 2026, month: 12).dayCount, 31)
        // Klopt met de kalender zelf.
        for m in YearMonth(year: 2024, month: 1).range(count: 48) {
            let days = YearMonth.calendar.range(of: .day, in: .month, for: m.firstDay)?.count
            XCTAssertEqual(m.dayCount, days, m.key)
        }
    }

    func testDateOfADayIsNoonAndClampedToTheMonth() {
        let cal = YearMonth.calendar
        let feb = YearMonth(year: 2027, month: 2)
        let thirtyFirst = cal.dateComponents([.year, .month, .day, .hour, .minute], from: feb.date(day: 31))
        XCTAssertEqual(thirtyFirst.year, 2027)
        XCTAssertEqual(thirtyFirst.month, 2)
        XCTAssertEqual(thirtyFirst.day, 28, "31 in februari is de laatste dag")
        XCTAssertEqual(thirtyFirst.hour, 12)
        XCTAssertEqual(thirtyFirst.minute, 0)
        XCTAssertEqual(engDayNumber(engFeb2028.date(day: 30)), 29)
        XCTAssertEqual(engDayNumber(feb.date(day: 0)), 1)
        XCTAssertEqual(engDayNumber(feb.date(day: -4)), 1)
        XCTAssertEqual(engDayNumber(oct2026.date(day: 17)), 17)
        XCTAssertEqual(YearMonth(date: oct2026.date(day: 31)), oct2026)
        XCTAssertEqual(oct2026.date(day: 12), oct2026.date(day: 12, calendar: cal))
        XCTAssertLessThan(oct2026.date(day: 1), oct2026.date(day: 2))
    }

    func testClampedDay() {
        XCTAssertEqual(YearMonth.clampedDay(0), 1)
        XCTAssertEqual(YearMonth.clampedDay(-5), 1)
        XCTAssertEqual(YearMonth.clampedDay(1), 1)
        XCTAssertEqual(YearMonth.clampedDay(17), 17)
        XCTAssertEqual(YearMonth.clampedDay(31), 31)
        XCTAssertEqual(YearMonth.clampedDay(32), 31)
        XCTAssertEqual(YearMonth.clampedDay(1_000), 31)
    }

    func testDayMath() {
        let cal = YearMonth.calendar
        let next = DayMath.nextDayStart(after: day(oct2026, 8))
        XCTAssertEqual(cal.dateComponents([.day, .hour, .minute], from: next).day, 9)
        XCTAssertEqual(cal.component(.hour, from: next), 0)
        XCTAssertEqual(DayMath.nextDayStart(after: engTime(oct2026, 8, hour: 0.1)), next)
        XCTAssertEqual(DayMath.nextDayStart(after: engTime(oct2026, 8, hour: 23.9)), next)
        XCTAssertEqual(DayMath.nextDayStart(after: day(oct2026, 31)), YearMonth(year: 2026, month: 11).firstDay)
        XCTAssertEqual(DayMath.dayNumber(of: day(oct2026, 8)), 8)
    }
}

// MARK: - Nieuwe velden: oude bestanden en round-trip

final class NewFieldsCodableTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testOldPotWithoutInterestFieldsGetsDefaults() throws {
        let pot = try decode(Pot.self, #"{"id":"5F2A8B0C-1111-4C4C-9999-000000000001","name":"Buffer","startMonth":"2026-08","monthlyContribution":150}"#)
        XCTAssertEqual(pot.name, "Buffer")
        XCTAssertEqual(pot.monthlyContribution, 150)
        XCTAssertEqual(pot.interestRate, 0)
        XCTAssertEqual(pot.interestPayout, .yearly)
        XCTAssertEqual(pot.interestPayoutDay, 1)
        XCTAssertEqual(pot.interestPayoutMonth, 1)
        XCTAssertNil(pot.transferDay)
    }

    func testOldSalaryWithoutPayDayIsThe25th() throws {
        let salary = try decode(SalarySettings.self, #"{"mode":"fixed","fixedMonthly":3000,"hourlyRate":0,"hoursPerWeek":0}"#)
        XCTAssertEqual(salary.payDay, 25)
        XCTAssertEqual(salary.fixedMonthly, 3000)
    }

    func testOldMonthPlanAndLinesHaveNoDaysOrShares() throws {
        let plan = try decode(MonthPlan.self, #"{"extraIncome":[{"name":"Toeslag","amount":100,"isRecurring":true}],"expenses":[{"name":"Huur","amount":1000}],"allocations":{}}"#)
        XCTAssertNil(plan.transferDay)
        XCTAssertNil(plan.expenses[0].day)
        XCTAssertTrue(plan.expenses[0].potShares.isEmpty)
        XCTAssertNil(plan.extraIncome[0].day)
    }

    func testOldHoldingWithoutTransferDay() throws {
        let holding = Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, monthlyContribution: 50, startMonth: aug2026)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(holding)) as? [String: Any] ?? [:]
        object.removeValue(forKey: "transferDay")
        let old = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(Holding.self, from: old)
        XCTAssertNil(back.transferDay)
        XCTAssertEqual(back, holding)
    }

    func testWholeOldFileStillLoadsAndCalculates() throws {
        let json = """
        {"startMonth":"2026-08","salary":{"mode":"fixed","fixedMonthly":3000,"hourlyRate":0,"hoursPerWeek":0},
         "pots":[{"name":"Spaar","startMonth":"2026-08","monthlyContribution":200}],
         "months":{"2026-08":{"extraIncome":[{"name":"Toeslag","amount":100,"isRecurring":true}],
                              "expenses":[{"name":"Huur","amount":1000,"isRecurring":true}],"allocations":{}}}}
        """
        let d = try decode(FinanceData.self, json)
        XCTAssertEqual(d.salary.payDay, 25)
        XCTAssertTrue(d.appliedAccelerators.isEmpty)
        XCTAssertNil(d.modifiedAt)
        XCTAssertEqual(d.settings.blockOrder, [:])
        // 3000 + 100 - 1000 - 200 (de pot krijgt zijn standaardinleg).
        XCTAssertEqual(d.remaining(in: aug2026), 1_900)
        XCTAssertEqual(d.dayEvents(in: aug2026, asOf: day(aug2026, 1)).map(\.day), [1, 25, 25, 25])
        XCTAssertEqual(d.potBalance(d.pots[0].id, at: sep2026), 400, accuracy: 0.001)
    }

    func testPotEntryKindsInterestAndExpense() throws {
        XCTAssertEqual(PotEntryKind.interest.rawValue, "interest")
        XCTAssertEqual(PotEntryKind.expense.rawValue, "expense")
        XCTAssertEqual(PotEntryKind.interest.title, "Rente")
        XCTAssertEqual(PotEntryKind.expense.title, "Uitgave betaald")
        let entry = PotEntry(potID: UUID(), date: day(oct2026, 1), amount: 2.01, kind: .interest, note: "Rente")
        let back = try JSONDecoder().decode(PotEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(back, entry)
        XCTAssertEqual(try decode(PotEntryKind.self, "\"expense\""), .expense)
    }

    func testEveryNewFieldSurvivesARoundTrip() throws {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 28)
        var pot = Pot(name: "Spaar", monthlyContribution: 100, startMonth: aug2026)
        pot.interestRate = 0.0275
        pot.interestPayout = .halfYearly
        pot.interestPayoutDay = 31
        pot.interestPayoutMonth = 6
        pot.transferDay = 12
        var holding = Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, monthlyContribution: 50, startMonth: aug2026)
        holding.transferDay = 5
        d.addPot(pot, openingBalance: 100, now: day(aug2026, 1))
        d.addHolding(holding)
        var plan = MonthPlan()
        plan.transferDay = 14
        plan.expenses = [MoneyLine(name: "Tandarts", amount: 150, day: 12, potShares: [PotShare(potID: pot.id, amount: 100)])]
        plan.extraIncome = [MoneyLine(name: "Toeslag", amount: 120, isRecurring: true, day: 20)]
        d.months[aug2026.key] = plan
        d.potEntries.append(PotEntry(id: InterestRules.entryID(for: pot.id, month: oct2026), potID: pot.id,
                                     date: day(oct2026, 31), amount: 12.5, kind: .interest, note: "Rente"))

        let back = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
        XCTAssertEqual(back.salary.payDay, 28)
        XCTAssertEqual(back.pots[0].interestRate, 0.0275)
        XCTAssertEqual(back.pots[0].interestPayout, .halfYearly)
        XCTAssertEqual(back.pots[0].interestPayoutDay, 31)
        XCTAssertEqual(back.pots[0].interestPayoutMonth, 6)
        XCTAssertEqual(back.pots[0].transferDay, 12)
        XCTAssertEqual(back.holdings[0].transferDay, 5)
        XCTAssertEqual(back.months[aug2026.key]?.transferDay, 14)
        XCTAssertEqual(back.months[aug2026.key]?.expenses[0].day, 12)
        XCTAssertEqual(back.months[aug2026.key]?.expenses[0].potShares.first?.potID, pot.id)
        XCTAssertEqual(back.months[aug2026.key]?.extraIncome[0].day, 20)
        XCTAssertEqual(back.potEntries.last?.kind, .interest)
        // En de uitkomsten blijven gelijk.
        XCTAssertEqual(back.remaining(in: aug2026), d.remaining(in: aug2026))
        XCTAssertEqual(back.potBalance(pot.id, at: engDec2026), d.potBalance(pot.id, at: engDec2026))
        XCTAssertEqual(back.dayEvents(in: aug2026, asOf: day(aug2026, 1)), d.dayEvents(in: aug2026, asOf: day(aug2026, 1)))
    }
}
