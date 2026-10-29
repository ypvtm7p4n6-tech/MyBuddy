import XCTest
import Foundation
@testable import MyBuddyCore

/// Schattingen (buffer, aankoopcheck, versnellers, doelen, toekomstschatting) rekenen met een HELE startmaand (docs/work/plan.md B6):
/// anders onderschat je in je eerste maand je inkomen en je uitgaven. De cijfers van de maand zelf blijven een deelmaand.
final class StartDateEstimatesTests: XCTestCase {
    private let nov2026 = YearMonth(year: 2026, month: 11)

    private func data(startingOn day: Int?, weekly: Bool = false) -> FinanceData {
        var d = startBaseData()
        var pot = Pot(name: "Percentage", monthlyContribution: 0, startMonth: oct2026)
        pot.id = startFixtureID(1)
        pot.contributionMode = .percentage
        pot.contributionPercent = 10
        pot.contributionBasis = .allIncome
        d.addPot(pot)
        var holding = Holding(name: "Fonds", kind: .etf, monthlyContribution: 50, startMonth: oct2026)
        holding.id = startFixtureID(2)
        holding.transferDay = 3
        d.holdings = [holding]
        if weekly {
            d.salary = SalarySettings(mode: .fixed, fixedMonthly: 1_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
            d.salary.setSchedule(.weeks, interval: 2, anchor: CalendarDay(year: 2026, month: 10, day: 2))
        }
        if let day { d.setStart(startOct(day)) }
        return d
    }

    private let days = [2, 10, 15, 21, 26, 31]

    func testForEstimatesIsTheDataItselfWithoutAPartialMonth() {
        let plain = data(startingOn: nil)
        XCTAssertEqual(plain.forEstimates, plain)
        let first = data(startingOn: 1)
        XCTAssertEqual(first.forEstimates, first)
    }

    func testForEstimatesOnlyMovesTheStartDayToTheFirst() {
        let partial = data(startingOn: 15)
        let whole = partial.forEstimates
        XCTAssertEqual(whole.startDay, startOct(1))
        XCTAssertEqual(whole.startMonth, partial.startMonth)
        XCTAssertEqual(whole.months, partial.months)
        XCTAssertEqual(whole.pots, partial.pots)
        XCTAssertEqual(whole.firstCountedDay(in: oct2026), 1)
        XCTAssertEqual(partial.firstCountedDay(in: oct2026), 15, "het origineel is niet veranderd")
    }

    func testEstimatesOfTheStartMonthAreThoseOfAWholeMonth() {
        let whole = data(startingOn: 1)
        for day in days {
            let d = data(startingOn: day)
            let tag = "start \(day) oktober"
            XCTAssertEqual(d.estimatedFigures(oct2026), whole.estimatedFigures(oct2026), tag)
            XCTAssertEqual(d.estimatedMonthlyIncome(in: oct2026), whole.estimatedMonthlyIncome(in: oct2026), tag)
            XCTAssertEqual(d.estimatedRemaining(in: oct2026), whole.estimatedRemaining(in: oct2026), tag)
            XCTAssertEqual(d.estimatedIncomeBases(in: oct2026), whole.estimatedIncomeBases(in: oct2026), tag)
            for pot in d.pots {
                XCTAssertEqual(d.estimatedAllocation(pot.id, in: oct2026), whole.estimatedAllocation(pot.id, in: oct2026), tag)
                XCTAssertEqual(d.estimatedDefaultAllocation(pot.id, in: oct2026), whole.estimatedDefaultAllocation(pot.id, in: oct2026), tag)
            }
            for holding in d.holdings {
                XCTAssertEqual(d.estimatedAllocation(holding.id, in: oct2026), whole.estimatedAllocation(holding.id, in: oct2026), tag)
            }
            let rule = AllocationRule.percent(PercentRule(percent: 10, basis: .allIncome))
            XCTAssertEqual(d.estimatedAmount(of: rule, in: oct2026), whole.estimatedAmount(of: rule, in: oct2026), tag)
            XCTAssertEqual(d.monthlyInvestment(current: oct2026), whole.monthlyInvestment(current: oct2026), tag)
        }
    }

    func testTheFiguresOfTheMonthItselfStayAPartialMonth() {
        let whole = data(startingOn: 1)
        let partial = data(startingOn: 15)
        XCTAssertEqual(whole.estimatedFigures(oct2026).income, 332_000)
        XCTAssertEqual(partial.estimatedFigures(oct2026).income, 332_000, "de schatting is de hele maand")
        XCTAssertEqual(partial.monthFigures(oct2026).income, 332_000, "alle inkomsten vallen na de 15e")
        XCTAssertEqual(partial.monthFigures(oct2026).expenses, 0, "alle uitgaven vallen vóór de 15e")
        XCTAssertEqual(partial.estimatedFigures(oct2026).expenses, 127_000, "maar de schatting rekent met alle uitgaven")
        XCTAssertNotEqual(partial.monthFigures(oct2026), partial.estimatedFigures(oct2026))
    }

    func testEstimatesWithAWeeklySalaryAreThoseOfAWholeMonth() {
        let whole = data(startingOn: 1, weekly: true)
        for day in days {
            let d = data(startingOn: day, weekly: true)
            let tag = "weekschema, start \(day) oktober"
            XCTAssertEqual(d.estimatedFigures(oct2026), whole.estimatedFigures(oct2026), tag)
            XCTAssertEqual(d.estimatedIncomeBases(in: oct2026), whole.estimatedIncomeBases(in: oct2026), tag)
            for pot in d.pots {
                XCTAssertEqual(d.estimatedAllocation(pot.id, in: oct2026), whole.estimatedAllocation(pot.id, in: oct2026), tag)
            }
        }
    }

    func testEstimatesOfOtherMonthsAreUnchanged() {
        let plain = data(startingOn: nil)
        for day in days {
            let d = data(startingOn: day)
            XCTAssertEqual(d.estimatedFigures(nov2026), plain.estimatedFigures(nov2026), "start \(day) oktober")
            XCTAssertEqual(d.estimatedFigures(oct2026.adding(-1)), MonthFigures(), "voor de startmaand")
        }
    }

    func testTheAverageMonthlyExpensesAreThoseOfAWholeStartMonth() {
        let whole = data(startingOn: 1)
        for day in days {
            let d = data(startingOn: day)
            XCTAssertEqual(d.averageMonthlyExpenses(current: oct2026), whole.averageMonthlyExpenses(current: oct2026), "start \(day) oktober")
            XCTAssertEqual(d.bankBuffer(current: oct2026), whole.bankBuffer(current: oct2026))
        }
        XCTAssertEqual(whole.averageMonthlyExpenses(current: oct2026), 1_270)
        // Een jaar later telt de startmaand niet meer mee in de laatste drie maanden.
        let d = data(startingOn: 26)
        XCTAssertEqual(d.averageMonthlyExpenses(current: oct2026.adding(4)), whole.averageMonthlyExpenses(current: oct2026.adding(4)))
    }

    func testTheBufferChecksTheExpensesOfAWholeMonth() {
        let whole = data(startingOn: 1)
        for day in days {
            let d = data(startingOn: day)
            XCTAssertTrue(BufferCalc.hasExpenses(in: d, current: oct2026), "start \(day) oktober: er zijn uitgaven")
            let setup = BufferSetup()
            let a = BufferCalc.inputs(from: d, setup: setup, current: oct2026, monthlySaving: 100, fillWithin: 12,
                                      today: startMoment(oct2026, 28))
            let b = BufferCalc.inputs(from: whole, setup: setup, current: oct2026, monthlySaving: 100, fillWithin: 12,
                                      today: startMoment(oct2026, 28))
            XCTAssertEqual(a.fixedMonthly, 920, "huur en abonnement")
            XCTAssertEqual(a.variableMonthly, 350)
            XCTAssertEqual(a.fixedMonthly, b.fixedMonthly)
            XCTAssertEqual(a.variableMonthly, b.variableMonthly)
        }
        // De pagina Uitgaven blijft de deelmaand tonen.
        XCTAssertEqual(data(startingOn: 15).expenseOverview(in: oct2026).expenses, 0)
        XCTAssertEqual(data(startingOn: 15).forEstimates.expenseOverview(in: oct2026).expenses, 1_270)
    }

    func testThePurchaseCheckUsesTheIncomeAndTheExpensesOfAWholeMonth() {
        let whole = data(startingOn: 1)
        let today = startMoment(oct2026, 28)
        for day in days {
            let d = data(startingOn: day)
            let a = PurchaseContext.make(from: d, current: oct2026, today: today)
            let b = PurchaseContext.make(from: whole, current: oct2026, today: today)
            XCTAssertEqual(a.monthlyIncome, b.monthlyIncome, "start \(day) oktober")
            XCTAssertEqual(a.remainingThisMonth, b.remainingThisMonth, "start \(day) oktober")
            XCTAssertEqual(a.expensesExceedIncome, b.expensesExceedIncome, "start \(day) oktober")
            XCTAssertEqual(a.pots.map { $0.monthlyContribution }, b.pots.map { $0.monthlyContribution })
        }
    }

    func testGoalsAndAcceleratorsCalculateWithAWholeMonth() {
        let whole = data(startingOn: 1)
        var goal = LifeGoal(name: "Vakantie", kind: .vacation)
        goal.targetAmount = 3_000
        goal.funding = .portfolio
        for day in days {
            let d = data(startingOn: day)
            let a = d.goalInputs(for: goal, current: oct2026, today: startMoment(oct2026, 28))
            let b = whole.goalInputs(for: goal, current: oct2026, today: startMoment(oct2026, 28))
            XCTAssertEqual(a.monthly, b.monthly, "start \(day) oktober")
        }
    }
}
