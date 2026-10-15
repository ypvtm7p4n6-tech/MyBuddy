import XCTest
@testable import MyBuddyCore

/// De bank-blokken ("saldo nu", "eindsaldo", "verwachting") tonen dezelfde dagwaarden als de dagpagina.
final class SavingsBankConsistencyTests: XCTestCase {
    private func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour; c.minute = minute
        return YearMonth.calendar.date(from: c)!
    }

    private func fixture() -> FinanceData {
        var d = FinanceData(startMonth: ym(2026, 8))
        d.salary.fixedMonthly = 3000
        d.salary.payDay = 14          // vandaag is salarisdag: telt de hele dag mee
        d.pots = [Pot(name: "Vakantie", monthlyContribution: 250, startMonth: ym(2026, 8))]
        d.holdings = [Holding(name: "ETF", monthlyContribution: 150, startMonth: ym(2026, 8))]
        d.materialize(upTo: ym(2026, 10))
        d.editPlan(ym(2026, 10)) { plan in
            plan.expenses.append(MoneyLine(name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 14))
            plan.expenses.append(MoneyLine(name: "Boodschappen", amount: 120, kind: .variable, day: 20))
            plan.extraIncome.append(MoneyLine(name: "Toeslag", amount: 80, day: 18))
        }
        // Een ingevuld saldo vanochtend, en een opname vanmiddag.
        d.bankSnapshots.append(BankSnapshot(date: date(2026, 10, 14, 8, 30), balance: 4000))
        d.bankEntries.append(BankEntry(date: date(2026, 10, 14, 9, 15), amount: -60, kind: .withdrawal, note: "Pinnen"))
        return d
    }

    func testBalanceNowEqualsTodaysDayBalance() throws {
        let d = fixture()
        let today = date(2026, 10, 14, 14, 0)
        let now = ym(2026, 10)
        let known = try XCTUnwrap(d.bankBalanceNowIfKnown(current: now, today: today))
        let day = d.dayTotals(on: today, asOf: today)
        XCTAssertEqual(day.bankBalance, known)
        XCTAssertTrue(d.hasBankBalanceNow(current: now, today: today))
        XCTAssertEqual(d.bankBalanceNow(current: now, today: today), known)
    }

    func testMonthEndEqualsLedgerClosingAndForecastPoint() throws {
        let d = fixture()
        let today = date(2026, 10, 14, 14, 0)
        let now = ym(2026, 10)
        let ledger = d.monthLedger(now, asOf: today)
        XCTAssertEqual(d.bankBalance(at: now), ledger.closingBank)
        let series = d.bankSeries(from: now.adding(-3), count: 16, current: now)
        let point = try XCTUnwrap(series.first { $0.month == now })
        XCTAssertEqual(point.balance, ledger.closingBank)
        XCTAssertTrue(ledger.allReconciles)
        // De laatste dag van de maand heeft hetzelfde eindsaldo.
        XCTAssertEqual(ledger.days.last?.bankBalance, ledger.closingBank)
    }

    func testBalanceNowIsUnknownBeforeFirstMeasurement() {
        var d = fixture()
        d.bankSnapshots = [BankSnapshot(date: date(2026, 11, 3, 10, 0), balance: 100)]
        d.bankEntries = []
        let today = date(2026, 10, 14, 14, 0)
        XCTAssertNil(d.bankBalanceNowIfKnown(current: ym(2026, 10), today: today))
        XCTAssertFalse(d.hasBankBalanceNow(current: ym(2026, 10), today: today))
        XCTAssertTrue(d.hasBankBalance)
    }

    func testFlowTotalsMatchOverview() {
        let d = fixture()
        let now = ym(2026, 10)
        let figures = d.monthFigures(now)
        let overview = d.expenseOverview(in: now)
        XCTAssertEqual(CentsMath.value(CentsMath.add(figures.saved, figures.invested)), overview.toPots + overview.toInvestments)
        XCTAssertEqual(overview.leftAfterTransfers, d.remaining(in: now))
        // De delen van de uitgaven die van de bank gaan, per soort, tellen op tot de uitgaven van de bank.
        var bank = 0
        for kind in ExpenseKind.allCases {
            bank += CentsMath.sum(d.expenseLines(in: now, kind: kind).map { CentsMath.int(d.fromBank(of: $0)) })
        }
        XCTAssertEqual(CentsMath.value(bank), d.expensesFromBank(in: now))
    }

    func testPayoutNoteForTwoPayoutsInOneMonth() {
        var d = FinanceData(startMonth: ym(2026, 8))
        d.salary.fixedMonthly = 1000
        d.salary.setSchedule(.weeks, interval: 2, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        // 2 en 16 en 30 oktober: drie uitbetalingen.
        let month = ym(2026, 10)
        let payouts = d.salaryPayouts(in: month, plan: d.plan(for: month)).filter { $0.cents != 0 }
        XCTAssertEqual(payouts.count, 3)
        XCTAssertEqual(d.salaryPayoutDaysText(in: month), "de 2e, de 16e en de 30e")
        XCTAssertEqual(d.salaryAmount(in: month), 3000)
        XCTAssertEqual(d.income(in: month), 3000)
        XCTAssertEqual(d.salaryDay(in: month), 2)
    }
}
