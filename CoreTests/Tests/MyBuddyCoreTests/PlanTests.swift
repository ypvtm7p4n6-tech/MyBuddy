import XCTest
@testable import MyBuddyCore

final class PlanTests: XCTestCase {
    func testFixedSalaryAndRemaining() {
        var d = makeBaseData()
        _ = addBufferPot(&d)
        // Augustus: salaris 3000 + toeslag 100, uitgaven 1000 + 50, pot 200.
        XCTAssertEqual(d.income(in: aug2026), 3100, accuracy: 0.001)
        XCTAssertEqual(d.expensesTotal(in: aug2026), 1050, accuracy: 0.001)
        XCTAssertEqual(d.savedTotal(in: aug2026), 200, accuracy: 0.001)
        XCTAssertEqual(d.remaining(in: aug2026), 1850, accuracy: 0.001)
    }

    func testHourlySalary() {
        var s = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        XCTAssertEqual(s.defaultMonthlyHours, 156, accuracy: 0.0001)
        XCTAssertEqual(s.monthlyAmount(), 3120, accuracy: 0.001)
        XCTAssertEqual(s.monthlyAmount(hoursOverride: 100), 2000, accuracy: 0.001)
        s.mode = .fixed
        s.fixedMonthly = 2500
        XCTAssertEqual(s.monthlyAmount(hoursOverride: 100), 2500, accuracy: 0.001)
    }

    func testSalaryOverridesPerMonth() {
        var d = makeBaseData()
        d.editPlan(sep2026) { $0.salaryOverride = 3500 }
        XCTAssertEqual(d.salaryAmount(in: sep2026), 3500, accuracy: 0.001)
        XCTAssertEqual(d.salaryAmount(in: aug2026), 3000, accuracy: 0.001)

        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 20, hoursPerWeek: 36)
        d.editPlan(oct2026) { $0.hoursOverride = 100 }
        XCTAssertEqual(d.salaryAmount(in: oct2026), 2000, accuracy: 0.001)
    }

    func testMonthsBeforeStartAreEmpty() {
        let d = makeBaseData()
        let july = YearMonth(year: 2026, month: 7)
        XCTAssertEqual(d.income(in: july), 0)
        XCTAssertEqual(d.remaining(in: july), 0)
    }

    func testRecurringLinesAreCopiedAndOneOffsAreNot() {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        let sep = d.plan(for: sep2026)
        XCTAssertEqual(sep.expenses.map(\.name), ["Huur"])
        XCTAssertEqual(sep.extraIncome.map(\.name), ["Toeslag"])
        // Nieuwe id's, zodat een regel per maand los te bewerken is.
        XCTAssertNotEqual(sep.expenses.first?.id, d.plan(for: aug2026).expenses.first?.id)
        XCTAssertEqual(d.remaining(in: sep2026), 2100, accuracy: 0.001) // 3000 + 100 - 1000
    }

    func testFutureMonthsAreSynthesisedFromDefaults() {
        var d = makeBaseData()
        _ = addBufferPot(&d)
        d.materialize(upTo: oct2026)
        let december = YearMonth(year: 2026, month: 12)
        XCTAssertNil(d.months[december.key])
        XCTAssertEqual(d.income(in: december), 3100, accuracy: 0.001)
        XCTAssertEqual(d.expensesTotal(in: december), 1000, accuracy: 0.001)
        XCTAssertEqual(d.savedTotal(in: december), 200, accuracy: 0.001)
    }

    func testMaterializeFreezesPastAllocations() {
        var d = makeBaseData()
        var pot = addBufferPot(&d)
        d.materialize(upTo: oct2026)
        pot.monthlyContribution = 300
        d.pots[0] = pot
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 200, accuracy: 0.001) // bevroren
        XCTAssertEqual(d.allocation(pot.id, in: YearMonth(year: 2026, month: 11)), 300, accuracy: 0.001)
    }

    func testUpdatePotChangesCurrentMonthToo() {
        var d = makeBaseData()
        var pot = addBufferPot(&d)
        d.materialize(upTo: oct2026)
        pot.monthlyContribution = 350
        d.updatePot(pot, current: oct2026)
        XCTAssertEqual(d.allocation(pot.id, in: oct2026), 350, accuracy: 0.001)
        XCTAssertEqual(d.allocation(pot.id, in: sep2026), 200, accuracy: 0.001)
    }

    func testPotCreatedLaterOnlyCountsFromItsStartMonth() {
        var d = makeBaseData()
        d.materialize(upTo: oct2026)
        let late = Pot(name: "Laat", monthlyContribution: 100, startMonth: oct2026)
        d.addPot(late)
        XCTAssertEqual(d.allocation(late.id, in: sep2026), 0)
        XCTAssertEqual(d.allocation(late.id, in: oct2026), 100, accuracy: 0.001)
    }

    func testLinesAddEditDelete() {
        var d = makeBaseData()
        // De terugkerende huur (1000) wordt automatisch meegenomen.
        var line = MoneyLine(name: "Gym", amount: 30)
        d.upsertLine(line, kind: .expense, in: oct2026)
        XCTAssertEqual(d.expensesTotal(in: oct2026), 1030, accuracy: 0.001)
        line.amount = 40
        d.upsertLine(line, kind: .expense, in: oct2026)
        XCTAssertEqual(d.plan(for: oct2026).expenses.count, 2)
        XCTAssertEqual(d.expensesTotal(in: oct2026), 1040, accuracy: 0.001)
        d.deleteLine(id: line.id, kind: .expense, in: oct2026)
        XCTAssertEqual(d.expensesTotal(in: oct2026), 1000, accuracy: 0.001)
    }

    func testPeriodSummaryAndProjectedFlag() {
        var d = makeBaseData()
        _ = addBufferPot(&d)
        d.materialize(upTo: oct2026)
        let half = d.periodSummary(.halfYear, containing: oct2026, current: oct2026)
        XCTAssertEqual(half.count, 6)
        // Juli telt niet mee (voor de startmaand), november en december zijn verwacht.
        XCTAssertEqual(half.months.first?.income, 0)
        XCTAssertTrue(half.hasProjected)
        XCTAssertFalse(half.isFullyProjected)
        let future = d.periodSummary(.month, containing: YearMonth(year: 2027, month: 3), current: oct2026)
        XCTAssertTrue(future.isFullyProjected)
        // Gemiddelde van 5 maanden met inkomen (aug t/m dec).
        XCTAssertEqual(half.income, 5 * 3100, accuracy: 0.01)
    }

    func testDistributionHelpers() {
        var d = makeBaseData()
        let a = addBufferPot(&d)
        let b = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: aug2026)
        d.addPot(b)
        d.materialize(upTo: oct2026)

        d.clearAllocations(in: oct2026)
        XCTAssertEqual(d.savedTotal(in: oct2026), 0, accuracy: 0.001)
        XCTAssertEqual(d.remaining(in: oct2026), 2100, accuracy: 0.001)

        d.spreadRemainingOverPots(in: oct2026)
        XCTAssertEqual(d.remaining(in: oct2026), 0, accuracy: 0.02)
        XCTAssertEqual(d.allocation(a.id, in: oct2026), 1050, accuracy: 0.001)

        d.applyDefaultAllocations(in: oct2026)
        XCTAssertEqual(d.allocation(a.id, in: oct2026), 200, accuracy: 0.001)
        XCTAssertEqual(d.allocation(b.id, in: oct2026), 0, accuracy: 0.001)
    }
}
