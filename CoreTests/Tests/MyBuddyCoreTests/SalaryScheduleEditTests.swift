import XCTest
@testable import MyBuddyCore

/// Controle van de logica achter het scherm "Salaris" (App/Pages/Month/SalaryPage.swift).
final class SalaryScheduleEditTests: XCTestCase {
    private func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour
        return YearMonth.calendar.date(from: c)!
    }

    private func monthlyData() -> FinanceData {
        var d = FinanceData(startMonth: ym(2026, 8))
        d.salary.fixedMonthly = 700
        d.salary.payDay = 25
        return d
    }

    func testSwitchToWeeksUsesNextPayDateAsAnchor() {
        var d = monthlyData()
        let today = date(2026, 10, 14)
        SalaryScheduleEdit.change(&d, to: .weeks, today: today)
        XCTAssertEqual(d.salary.schedule, .weeks)
        XCTAssertEqual(d.salary.interval, 4)
        XCTAssertEqual(d.salary.anchor, CalendarDay(year: 2026, month: 10, day: 25))
        // Om de 4 weken vanaf 25 oktober, ook terug.
        XCTAssertEqual(d.salaryPayDays(in: ym(2026, 10)), [25])
        XCTAssertEqual(d.salaryPayDays(in: ym(2026, 11)), [22])
        XCTAssertEqual(d.salaryPayDays(in: ym(2026, 9)), [27])
        XCTAssertEqual(d.salaryScheduleSummary(asOf: today), "elke 4 weken, volgende op 25 oktober")
        XCTAssertEqual(SalaryScheduleText.capitalized(d.salaryScheduleSummary(asOf: today)),
                       "Elke 4 weken, volgende op 25 oktober")
    }

    func testExistingAnchorIsKeptAndSameScheduleIsNoOp() {
        var d = monthlyData()
        d.salary.anchor = CalendarDay(year: 2026, month: 10, day: 2)
        SalaryScheduleEdit.change(&d, to: .days, today: date(2026, 10, 14))
        XCTAssertEqual(d.salary.schedule, .days)
        XCTAssertEqual(d.salary.interval, 14)
        XCTAssertEqual(d.salary.anchor, CalendarDay(year: 2026, month: 10, day: 2))
        let copy = d
        SalaryScheduleEdit.change(&d, to: .days, today: date(2026, 10, 14))
        XCTAssertEqual(d, copy)
        // Om de 14 dagen vanaf 2 oktober: 2, 16 en 30 oktober.
        XCTAssertEqual(d.salaryPayDays(in: ym(2026, 10)), [2, 16, 30])
    }

    func testSwitchBackToMonthlyKeepsPayDay() {
        var d = monthlyData()
        SalaryScheduleEdit.change(&d, to: .weeks, today: date(2026, 10, 14))
        SalaryScheduleEdit.change(&d, to: .monthly, today: date(2026, 10, 14))
        XCTAssertEqual(d.salary.schedule, .monthly)
        XCTAssertEqual(d.salary.interval, 1)
        XCTAssertEqual(d.salary.payDay, 25)
        XCTAssertEqual(d.salaryPayDays(in: ym(2026, 10)), [25])
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 10)), 700)
    }

    func testMonthTotalIsSumOfPayoutsAndFeedsIncome() {
        var d = monthlyData()
        d.salary.setSchedule(.weeks, interval: 2, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        let month = ym(2026, 10)
        // 2, 16 en 30 oktober: drie keer 700.
        XCTAssertEqual(d.salaryAmount(in: month), 2100)
        XCTAssertEqual(d.income(in: month), 2100)
        XCTAssertEqual(d.salaryPayDays(in: month), [2, 16, 30])
        // November: 13 en 27.
        XCTAssertEqual(d.salaryAmount(in: ym(2026, 11)), 1400)
        let plan = d.plan(for: month)
        XCTAssertEqual(d.salaryPayouts(in: month, plan: plan).map { $0.cents }, [70_000, 70_000, 70_000])
        // De dagboekhouding en het overzicht tellen dezelfde drie uitbetalingen.
        let ledger = d.monthLedger(month, asOf: date(2026, 10, 14))
        XCTAssertEqual(ledger.planInflow, 2100)
        XCTAssertTrue(ledger.allReconciles)
        XCTAssertEqual(ledger.salaryPayoutCountForTest, 3)
        // Gemiddeld per maand, voor schattingen: 700 × 365,25 / 12 / 14.
        XCTAssertEqual(d.salary.averageMonthlyAmount(), (700 * 365.25 / 12 / 14).cents)
    }

    func testHourlyPayoutAndFormulaTexts() {
        var d = monthlyData()
        d.salary.mode = .hourly
        d.salary.hourlyRate = 15
        d.salary.hoursPerWeek = 20
        d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        XCTAssertEqual(d.salary.payoutAmount(), 1200)
        XCTAssertEqual(SalaryScheduleText.weeksText(schedule: .weeks, interval: 4), "4 weken")
        XCTAssertEqual(SalaryScheduleText.weeksText(schedule: .weeks, interval: 1), "1 week")
        XCTAssertEqual(SalaryScheduleText.weeksText(schedule: .days, interval: 10), "10 ÷ 7 weken")
        XCTAssertEqual(SalaryScheduleText.unit(schedule: .weeks, interval: 1), "week")
        XCTAssertEqual(SalaryScheduleText.unit(schedule: .weeks, interval: 2), "weken")
        XCTAssertEqual(SalaryScheduleText.unit(schedule: .days, interval: 1), "dag")
        XCTAssertEqual(SalaryScheduleText.unit(schedule: .days, interval: 30), "dagen")
        XCTAssertEqual(SalaryScheduleText.payoutCount(1), "1 uitbetaling")
        XCTAssertEqual(SalaryScheduleText.payoutCount(3), "3 uitbetalingen")
        XCTAssertEqual(SalaryScheduleText.startInterval(for: .monthly), 1)
    }

    func testUpcomingPayDatesChainAfterEachOther() throws {
        var d = monthlyData()
        d.salary.setSchedule(.weeks, interval: 2, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        let today = date(2026, 10, 14)
        var result: [Date] = []
        var cursor = today
        for _ in 0..<4 {
            guard let next = d.nextPayDate(after: cursor) else { break }
            result.append(next)
            cursor = next
        }
        XCTAssertEqual(result.count, 4)
        let days = result.map { CalendarDay(date: $0) }
        XCTAssertEqual(days, [CalendarDay(year: 2026, month: 10, day: 16), CalendarDay(year: 2026, month: 10, day: 30),
                              CalendarDay(year: 2026, month: 11, day: 13), CalendarDay(year: 2026, month: 11, day: 27)])
        // Vandaag zelf telt als gebeurd: de volgende is dan de eerstvolgende dag erna.
        XCTAssertEqual(CalendarDay(date: try XCTUnwrap(d.nextPayDate(after: date(2026, 10, 16)))),
                       CalendarDay(year: 2026, month: 10, day: 30))
    }

    // MARK: Een wijziging geldt vanaf de lopende maand

    func testChangingTheScheduleLeavesPastMonthsAlone() {
        var d = monthlyData()           // 700 per maand vanaf augustus
        d.materialize(upTo: ym(2026, 10))
        let today = date(2026, 10, 14)
        XCTAssertEqual(d.income(in: ym(2026, 8)), 700)
        SalaryScheduleEdit.change(&d, to: .weeks, today: today)
        d.salary.setSchedule(.weeks, interval: 2, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        // Augustus en september blijven 700 (zonder vastleggen zou het schema ze op 1400 of 2100 zetten).
        XCTAssertEqual(d.income(in: ym(2026, 8)), 700)
        XCTAssertEqual(d.income(in: ym(2026, 9)), 700)
        // Oktober en later volgen het nieuwe schema: 2, 16 en 30 oktober.
        XCTAssertEqual(d.income(in: ym(2026, 10)), 2_100)
        XCTAssertEqual(d.income(in: ym(2026, 11)), 1_400)
        XCTAssertTrue(d.monthLedger(ym(2026, 9), asOf: today).allReconciles)
    }

    func testEditChangesTheAmountFromThisMonthOnly() {
        var d = monthlyData()
        d.materialize(upTo: ym(2026, 10))
        let today = date(2026, 10, 14)
        SalaryScheduleEdit.edit(&d, today: today) { $0.fixedMonthly = 800 }
        XCTAssertEqual(d.income(in: ym(2026, 8)), 700)
        XCTAssertEqual(d.income(in: ym(2026, 9)), 700)
        XCTAssertEqual(d.income(in: ym(2026, 10)), 800)
        XCTAssertEqual(d.income(in: ym(2026, 12)), 800)
        // Nog een wijziging: de vastgelegde maanden blijven staan.
        SalaryScheduleEdit.edit(&d, today: today) { $0.fixedMonthly = 900 }
        XCTAssertEqual(d.income(in: ym(2026, 9)), 700)
        XCTAssertEqual(d.income(in: ym(2026, 10)), 900)
        // De salarisdag en het interval gaan er ook door.
        SalaryScheduleEdit.edit(&d, today: today) { $0.setSchedule(.days, interval: 30) }
        XCTAssertEqual(d.income(in: ym(2026, 9)), 700)
    }

    func testEditThatChangesNothingStoresNothing() {
        var d = monthlyData()
        d.materialize(upTo: ym(2026, 10))
        let before = d
        SalaryScheduleEdit.edit(&d, today: date(2026, 10, 14)) { $0.fixedMonthly = 700 }
        XCTAssertEqual(d, before)
        SalaryScheduleEdit.edit(&d, today: date(2026, 10, 14)) { _ in }
        XCTAssertEqual(d, before)
    }

    func testEditKeepsPercentageContributionsOfThePast() {
        var d = monthlyData()
        var pot = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: ym(2026, 8))
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        d.addPot(pot, openingBalance: 0, now: date(2026, 8, 1))
        d.materialize(upTo: ym(2026, 10))
        XCTAssertEqual(d.savedTotal(in: ym(2026, 9)), 70)
        SalaryScheduleEdit.edit(&d, today: date(2026, 10, 14)) { $0.fixedMonthly = 1_000 }
        XCTAssertEqual(d.savedTotal(in: ym(2026, 9)), 70, "10% van het salaris van toen")
        XCTAssertEqual(d.savedTotal(in: ym(2026, 10)), 100)
    }
}

private extension MonthLedger {
    /// Het aantal salarisgebeurtenissen in de maand (bij CashflowPages: `salaryPayoutCount`).
    var salaryPayoutCountForTest: Int {
        days.reduce(0) { total, day in total + day.events.filter { $0.kind == .salary }.count }
    }
}
