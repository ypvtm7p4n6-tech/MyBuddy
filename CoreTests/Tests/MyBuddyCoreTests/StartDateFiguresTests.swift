import XCTest
import Foundation
@testable import MyBuddyCore

/// Wat er in de cijfers meetelt met een startdatum (docs/work/plan.md par. 2.1, R1 t/m R8): salaris, extra inkomsten, uitgaven en
/// inleg tellen alleen vanaf de startdag; het schema (salarisdag, overschrijfdag) volgt niet de startdag. Alle bedragen zijn
/// met de hand uitgerekend uit `startBaseData()`: salaris 3.000 op de 25e, huur 900 (1e), boodschappen 350 (10e), abonnement 20 (1e),
/// toeslag 120 (20e), bijverdienste 200 (salarisdag).
final class StartDateFiguresTests: XCTestCase {
    private let nov2026 = YearMonth(year: 2026, month: 11)

    private func started(_ day: Int) -> FinanceData {
        var d = startBaseData()
        d.setStart(startOct(day))
        return d
    }

    private func figures(_ d: FinanceData, _ month: YearMonth = oct2026) -> StartFigures {
        StartFigures(d, month)
    }

    // MARK: Gewone maand en startdag 1

    func testWithoutAStartDateEverythingCounts() {
        XCTAssertEqual(figures(startBaseData()), StartFigures(income: 3_320, expenses: 1_270))
    }

    func testStartingOnTheFirstEqualsNoStartDate() {
        let plain = startBaseData()
        let first = started(1)
        for month in [oct2026, nov2026] {
            XCTAssertEqual(first.monthFigures(month), plain.monthFigures(month), month.key)
            XCTAssertEqual(first.expenseOverview(in: month), plain.expenseOverview(in: month), month.key)
        }
    }

    // MARK: Een startdatum midden in de maand (monatelijk salaris)

    func testStartingOnTheTenthKeepsTheTenthButNotTheFirst() {
        // Huur en abonnement vallen op de 1e (weg), boodschappen op de 10e (blijft); alle inkomsten vallen na de 10e.
        XCTAssertEqual(figures(started(10)), StartFigures(income: 3_320, expenses: 350))
    }

    func testStartingOnTheFifteenthDropsAllExpenses() {
        XCTAssertEqual(figures(started(15)), StartFigures(income: 3_320, expenses: 0))
    }

    func testStartingOnTheTwentyFirstDropsTheBenefit() {
        // De toeslag valt op de 20e: weg. Het salaris en de bijverdienste (de salarisdag) vallen op de 25e.
        XCTAssertEqual(figures(started(21)), StartFigures(income: 3_200, expenses: 0))
    }

    func testTheStartDayItselfCounts() {
        XCTAssertEqual(figures(started(25)), StartFigures(income: 3_200, expenses: 0), "de 25e: het salaris telt nog mee")
        XCTAssertEqual(figures(started(20)).income, 3_320, "de 20e: de toeslag telt nog mee")
        XCTAssertEqual(figures(started(10)).expenses, 350, "de 10e: de boodschappen tellen nog mee")
    }

    func testStartingAfterThePayDayDropsTheSalaryOfThatMonth() {
        // Valt de salarisdag vóór de startdag, dan telt het salaris van die maand niet: het zit in je beginsaldo.
        let d = started(26)
        XCTAssertEqual(figures(d), StartFigures(income: 0, expenses: 0))
        XCTAssertEqual(d.salaryAmount(in: oct2026), 0)
        XCTAssertEqual(d.scheduledSalary(in: oct2026), 0)
        XCTAssertEqual(d.salaryPayouts(in: oct2026, plan: d.plan(for: oct2026)).count, 0)
        XCTAssertEqual(d.salaryPayoutDaysText(in: oct2026), "")
    }

    func testTheMonthsAfterTheStartMonthAreWholeMonths() {
        let plain = startBaseData()
        for day in [1, 10, 15, 21, 26, 31] {
            let d = started(day)
            XCTAssertEqual(figures(d, nov2026), figures(plain, nov2026), "start \(day) oktober, november")
            XCTAssertEqual(figures(d, nov2026), StartFigures(income: 3_120, expenses: 1_270))
        }
    }

    func testMonthsBeforeTheStartMonthStillCountNothing() {
        var d = startBaseData()
        d.setStart(CalendarDay(year: 2026, month: 11, day: 10))
        XCTAssertEqual(d.monthFigures(oct2026), MonthFigures())
        XCTAssertEqual(d.expenseOverview(in: oct2026), ExpenseOverview(income: 0, fixed: 0, variable: 0, toPots: 0, toInvestments: 0))
        XCTAssertEqual(d.salaryAmount(in: oct2026), 0)
        XCTAssertEqual(d.planEvents(in: oct2026).count, 0)
        // De startmaand zelf (november) is een deelmaand: de huur van de 1e valt weg.
        XCTAssertEqual(figures(d, nov2026), StartFigures(income: 3_120, expenses: 350))
    }

    func testExpenseOverviewFollowsTheCountedLines() {
        let d = started(10)
        let overview = d.expenseOverview(in: oct2026)
        XCTAssertEqual(overview.fixed, 0, "huur en abonnement vallen op de 1e")
        XCTAssertEqual(overview.variable, 350)
        XCTAssertEqual(overview.income, 3_320)
        XCTAssertEqual(overview.leftAfterTransfers, d.remaining(in: oct2026))
        XCTAssertEqual(d.remaining(in: oct2026), 2_970)
        XCTAssertEqual(d.countedExpenseLines(in: oct2026, kind: .fixed).count, 0)
        XCTAssertEqual(d.countedExpenseLines(in: oct2026, kind: .variable).map { $0.name }, ["Boodschappen"])
        XCTAssertEqual(d.expenseLines(in: oct2026, kind: .fixed).count, 2, "de regels zelf blijven bewaard")
    }

    func testTheExtraIncomeTotalFollowsTheCountedLines() {
        XCTAssertEqual(started(10).extraIncomeTotal(in: oct2026), 320)
        XCTAssertEqual(started(21).extraIncomeTotal(in: oct2026), 200)
        XCTAssertEqual(started(26).extraIncomeTotal(in: oct2026), 0)
    }

    func testPlanEventsHaveNoDayBeforeTheStartDay() {
        for day in [3, 10, 15, 21, 25, 26] {
            let d = started(day)
            let events = d.planEvents(in: oct2026)
            XCTAssertTrue(events.allSatisfy { $0.day >= day }, "start \(day) oktober: \(events.map { $0.day })")
            let income = events.filter { $0.kind == .salary || $0.kind == .income }
            XCTAssertEqual(CentsMath.sum(income.map { CentsMath.int($0.bankAmount) }), CentsMath.int(d.income(in: oct2026)))
        }
    }

    // MARK: Inleg

    private func dataWithPercentPot(basis: IncomeBasis, percent: Double = 10) -> FinanceData {
        var d = startBaseData()
        var pot = Pot(name: "Percentage", monthlyContribution: 0, startMonth: oct2026)
        pot.contributionMode = .percentage
        pot.contributionPercent = percent
        pot.contributionBasis = basis
        d.addPot(pot)
        return d
    }

    func testAPercentageContributionCalculatesOverTheIncomeThatCounts() {
        var d = dataWithPercentPot(basis: .salary)
        let id = d.pots[0].id
        XCTAssertEqual(d.allocation(id, in: oct2026), 300, "zonder startdatum: 10% van 3.000")
        d.setStart(startOct(21))
        XCTAssertEqual(d.allocation(id, in: oct2026), 300, "de salarisdag (de overschrijfdag) valt op de 25e: telt mee")
        XCTAssertEqual(d.monthFigures(oct2026).saved, 30_000)
        d.setStart(startOct(26))
        XCTAssertEqual(d.allocation(id, in: oct2026), 0, "de overschrijfdag (de 25e) valt vóór de startdag")
        XCTAssertEqual(d.allocationCents(id, in: oct2026), 0)
        XCTAssertEqual(d.monthFigures(oct2026).saved, 0)
    }

    func testAPercentageOfAllIncomeUsesTheCountedExtraIncome() {
        var d = dataWithPercentPot(basis: .allIncome)
        let id = d.pots[0].id
        d.setStart(startOct(21))
        // Salaris 3.000 en bijverdienste 200 tellen; de toeslag (20e) niet: 10% van 3.200.
        XCTAssertEqual(d.allocation(id, in: oct2026), 320)
        XCTAssertEqual(d.incomeBases(in: oct2026), IncomeBases(salary: 300_000, all: 320_000))
        XCTAssertEqual(d.percentAmount(10, of: .allIncome, in: oct2026), 320)
    }

    func testAPercentageOfAnOverriddenSalaryUsesTheTotalThatCounts() {
        var d = dataWithPercentPot(basis: .salary)
        let id = d.pots[0].id
        d.setStart(startOct(21))
        d.editPlan(oct2026) { $0.salaryOverride = 2_000 }
        XCTAssertEqual(d.salaryAmount(in: oct2026), 2_000, "een eigen salaris is het totaal dat telt")
        XCTAssertEqual(d.allocation(id, in: oct2026), 200)
    }

    func testAContributionWithAnEarlierTransferDayDoesNotCount() {
        var d = startBaseData()
        var pot = Pot(name: "Vakantie", monthlyContribution: 100, startMonth: oct2026)
        pot.transferDay = 5
        d.addPot(pot)
        var holding = Holding(name: "Fonds", kind: .etf, monthlyContribution: 50, startMonth: oct2026)
        holding.transferDay = 12
        d.holdings = [holding]
        let potID = pot.id
        XCTAssertEqual(figures(d).saved, 100)
        XCTAssertEqual(figures(d).invested, 50)

        d.setStart(startOct(10))
        XCTAssertEqual(d.allocation(potID, in: oct2026), 0, "overschrijfdag de 5e, startdatum de 10e")
        XCTAssertEqual(d.allocation(holding.id, in: oct2026), 50, "overschrijfdag de 12e: telt mee")
        XCTAssertEqual(figures(d).saved, 0)
        XCTAssertEqual(figures(d).invested, 50)
        // De regel zelf blijft zoals hij is; alleen het bedrag dat meetelt is 0.
        let effective = d.effectiveAllocation(potID, in: oct2026)
        XCTAssertEqual(effective.amount, 0)
        XCTAssertEqual(effective.rule, .amount(100))
        XCTAssertFalse(effective.isOverride)
        XCTAssertFalse(d.transferCounts(potID, in: oct2026))
        XCTAssertTrue(d.transferCounts(holding.id, in: oct2026))
        // Geen overschrijving van de pot in de gebeurtenissen en geen boeking in het saldo van de pot.
        XCTAssertFalse(d.planEvents(in: oct2026).contains { $0.kind == .toPot })
        XCTAssertEqual(d.potBalance(potID, at: oct2026), 0)
        // De maanden erna zijn gewoon.
        XCTAssertEqual(d.allocation(potID, in: nov2026), 100)
    }

    func testAContributionOnTheStartDayCounts() {
        var d = startBaseData()
        var pot = Pot(name: "Vakantie", monthlyContribution: 100, startMonth: oct2026)
        pot.transferDay = 5
        d.addPot(pot)
        d.setStart(startOct(5))
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 100)
        XCTAssertTrue(d.planEvents(in: oct2026).contains { $0.kind == .toPot && $0.day == 5 })
    }

    // MARK: Schema om de zoveel weken

    private func weeklyData(hourly: Bool = false) -> FinanceData {
        var d = startBaseData()
        if hourly {
            d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 20, payDay: 25)
        } else {
            d.salary = SalarySettings(mode: .fixed, fixedMonthly: 1_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        }
        d.salary.setSchedule(.weeks, interval: 2, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        return d
    }

    func testOnlyThePayoutsFromTheStartDayCount() {
        var d = weeklyData()
        XCTAssertEqual(d.salaryPayDays(in: oct2026), [2, 16, 30])
        XCTAssertEqual(d.salaryAmount(in: oct2026), 3_000)
        d.setStart(startOct(10))
        XCTAssertEqual(d.salaryPayDays(in: oct2026), [2, 16, 30], "het schema volgt de startdag niet")
        XCTAssertEqual(d.countedSalaryPayDays(in: oct2026), [16, 30])
        XCTAssertEqual(d.salaryAmount(in: oct2026), 2_000)
        XCTAssertEqual(d.scheduledSalary(in: oct2026), 2_000)
        XCTAssertEqual(d.salaryPayouts(in: oct2026, plan: d.plan(for: oct2026)).map { $0.day }, [16, 30])
        XCTAssertEqual(d.salaryPayoutDaysText(in: oct2026), "de 16e en de 30e")
        // De volgende maand is gewoon: 13 en 27 november.
        XCTAssertEqual(d.countedSalaryPayDays(in: nov2026), [13, 27])
        XCTAssertEqual(d.salaryAmount(in: nov2026), 2_000)
    }

    func testTheStartDayCountsForAPayout() {
        var d = weeklyData()
        d.setStart(startOct(16))
        XCTAssertEqual(d.countedSalaryPayDays(in: oct2026), [16, 30])
        d.setStart(startOct(17))
        XCTAssertEqual(d.countedSalaryPayDays(in: oct2026), [30])
        XCTAssertEqual(d.salaryAmount(in: oct2026), 1_000)
    }

    func testExtraIncomeWithoutADayFollowsTheScheduleNotTheStartDay() {
        var d = weeklyData()
        d.setStart(startOct(10))
        // De bijverdienste heeft geen eigen dag: dat is de eerste uitbetaling van de maand (de 2e), vóór de startdatum.
        XCTAssertEqual(d.salaryDay(in: oct2026), 2)
        XCTAssertEqual(figures(d).income, 2_120, "salaris 2.000 en toeslag 120; de bijverdienste (de 2e) valt weg")
        XCTAssertEqual(d.extraIncomeTotal(in: oct2026), 120)
    }

    func testAnOverriddenSalaryIsSpreadOverThePayoutsFromTheStartDay() {
        var d = weeklyData()
        d.setStart(startOct(10))
        d.editPlan(oct2026) { $0.salaryOverride = 1_001.01 }
        let payouts = d.salaryPayouts(in: oct2026, plan: d.plan(for: oct2026))
        XCTAssertEqual(payouts.map { $0.day }, [16, 30])
        XCTAssertEqual(payouts.map { $0.cents }, [50_051, 50_050], "het totaal gelijk verdeeld, de restcent naar de eerste")
        XCTAssertEqual(d.salaryAmount(in: oct2026), 1_001.01)
    }

    func testAnOverriddenSalaryWithoutAPayoutFromTheStartDayFallsBackOnlyWhenTheFallbackDayCounts() {
        var d = weeklyData()
        d.setStart(startOct(31))
        XCTAssertEqual(d.countedSalaryPayDays(in: oct2026), [], "de laatste uitbetaling is de 30e")
        d.editPlan(oct2026) { $0.salaryOverride = 900 }
        // De terugvaldag is de salarisdag (de 25e): vóór de startdatum, dus er is geen salaris.
        XCTAssertEqual(d.salaryAmount(in: oct2026), 0)
        // Met een eerdere startdag komt de terugvaldag niet in beeld (er zijn gewoon uitbetalingen).
        var other = weeklyData()
        other.setStart(startOct(20))
        other.editPlan(oct2026) { $0.salaryOverride = 900 }
        XCTAssertEqual(other.salaryPayouts(in: oct2026, plan: other.plan(for: oct2026)).map { $0.day }, [30])
        XCTAssertEqual(other.salaryAmount(in: oct2026), 900)
    }

    func testHourlyWagesFollowThePayoutsAndTheHours() {
        var d = weeklyData(hourly: true)
        XCTAssertEqual(d.salaryAmount(in: oct2026), 2_400, "drie uitbetalingen van 20 x 40 uur")
        XCTAssertEqual(d.salaryHours(in: oct2026), 120)
        d.setStart(startOct(10))
        XCTAssertEqual(d.salaryAmount(in: oct2026), 1_600)
        XCTAssertEqual(d.salaryHours(in: oct2026), 80, "twee uitbetalingen van 40 uur")
        XCTAssertEqual(d.scheduledSalary(in: oct2026), 1_600)
        // Eigen uren zijn het totaal dat telt.
        d.editPlan(oct2026) { $0.hoursOverride = 60 }
        XCTAssertEqual(d.salaryHours(in: oct2026), 60)
        XCTAssertEqual(d.salaryAmount(in: oct2026), 1_200)
        XCTAssertEqual(d.salaryPayouts(in: oct2026, plan: d.plan(for: oct2026)).map { $0.cents }, [60_000, 60_000])
    }

    func testTheNextPayDateIsNeverBeforeTheStartDay() throws {
        let cal = YearMonth.calendar
        var d = weeklyData()
        let before = startMoment(oct2026, 1)
        XCTAssertEqual(CalendarDay(date: try XCTUnwrap(d.nextPayDate(after: before)), calendar: cal), startOct(2))
        d.setStart(startOct(10))
        XCTAssertEqual(CalendarDay(date: try XCTUnwrap(d.nextPayDate(after: before)), calendar: cal), startOct(16),
                       "ook als vandaag vóór de startdatum ligt")
        d.setStart(startOct(31))
        XCTAssertEqual(CalendarDay(date: try XCTUnwrap(d.nextPayDate(after: startMoment(oct2026, 31))), calendar: cal),
                       CalendarDay(year: 2026, month: 11, day: 13))
    }

    func testTheNextPayDateOfAMonthlySalaryNeverPrecedesTheStartDay() throws {
        let cal = YearMonth.calendar
        var d = startBaseData()
        d.setStart(startOct(26))
        // De salarisdag (de 25e) is voorbij de startdag niet meer te halen in oktober: de volgende is 25 november.
        XCTAssertEqual(CalendarDay(date: try XCTUnwrap(d.nextPayDate(after: startMoment(oct2026, 3))), calendar: cal),
                       CalendarDay(year: 2026, month: 11, day: 25))
        var later = startBaseData()
        later.setStart(startOct(20))
        XCTAssertEqual(CalendarDay(date: try XCTUnwrap(later.nextPayDate(after: startMoment(oct2026, 3))), calendar: cal), startOct(25))
    }

    // MARK: Korte maanden en de laatste dag

    func testExpensesOnDay31InAShortMonthCountOnTheLastDay() {
        let feb = YearMonth(year: 2027, month: 2)
        var d = FinanceData(startMonth: feb)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 0, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var plan = MonthPlan()
        plan.expenses = [
            MoneyLine(name: "Dag 31", amount: 50, isRecurring: false, kind: .fixed, day: 31),
            MoneyLine(name: "Dag 27", amount: 70, isRecurring: false, kind: .fixed, day: 27),
            MoneyLine(name: "Dag 28", amount: 10, isRecurring: false, kind: .fixed, day: 28)
        ]
        d.months[feb.key] = plan
        XCTAssertEqual(d.expensesTotal(in: feb), 130)
        d.setStart(CalendarDay(year: 2027, month: 2, day: 28))
        XCTAssertEqual(d.expensesTotal(in: feb), 60, "dag 31 is in februari de 28e: telt mee, net als de 28e zelf")
        XCTAssertEqual(d.planEvents(in: feb).filter { $0.kind == .expense }.map { $0.day }, [28, 28])
        XCTAssertEqual(d.monthLedger(feb, asOf: day(feb, 28)).allReconciles, true)
    }

    func testStartingOnTheLastDayOfAMonthKeepsOnlyThatDay() {
        let d = started(31)
        XCTAssertEqual(figures(d), StartFigures(income: 0, expenses: 0))
        XCTAssertEqual(figures(d, nov2026), StartFigures(income: 3_120, expenses: 1_270))
    }

    // MARK: Het dagboek sluit

    func testTheLedgerOfThePartialMonthReconciles() {
        for day in [1, 2, 10, 15, 21, 25, 26, 31] {
            var d = started(day)
            var pot = Pot(name: "Spaar", monthlyContribution: 120, startMonth: oct2026)
            pot.transferDay = 12
            d.addPot(pot)
            d.addBankSnapshot(balance: 500, note: "Begin", date: startMoment(oct2026, day, hour: 9))
            let ledger = d.monthLedger(oct2026, asOf: startMoment(oct2026, 28))
            XCTAssertTrue(ledger.allReconciles, "start \(day) oktober")
            XCTAssertEqual(ledger.income, d.income(in: oct2026))
            XCTAssertEqual(ledger.remaining, d.remaining(in: oct2026))
            for dayTotals in ledger.days where dayTotals.day < day {
                XCTAssertEqual(dayTotals.events.count, 0, "geen gebeurtenissen vóór de startdag (\(dayTotals.day))")
                XCTAssertNil(dayTotals.bankBalance, "geen banksaldo vóór de startdag (\(dayTotals.day))")
                XCTAssertEqual(dayTotals.potsTotal, 0, "niets in de potten vóór de startdag (\(dayTotals.day))")
            }
        }
    }
}
