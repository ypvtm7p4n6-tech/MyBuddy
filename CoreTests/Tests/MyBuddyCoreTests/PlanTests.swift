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

// MARK: - Dagen, potdelen en één formule voor "over"

final class PlanDayAndFigureTests: XCTestCase {
    func testSalaryIncomeAndExpenseDays() {
        var d = makeBaseData()
        XCTAssertEqual(d.salaryDay(), 25)
        d.salary.payDay = 20
        XCTAssertEqual(d.salaryDay(), 20)
        d.salary.payDay = 0
        XCTAssertEqual(d.salaryDay(), 1)
        d.salary.payDay = 99
        XCTAssertEqual(d.salaryDay(), 31)

        d.salary.payDay = 20
        var line = MoneyLine(name: "Regel", amount: 10)
        XCTAssertEqual(d.incomeDay(of: line), 20, "inkomsten zonder eigen dag: de salarisdag")
        XCTAssertEqual(d.expenseDay(of: line), 1, "uitgaven zonder eigen dag: de 1e")
        line.day = 7
        XCTAssertEqual(d.incomeDay(of: line), 7)
        XCTAssertEqual(d.expenseDay(of: line), 7)
        line.day = 45
        XCTAssertEqual(d.incomeDay(of: line), 31)
        XCTAssertEqual(d.expenseDay(of: line), 31)
        line.day = -3
        XCTAssertEqual(d.incomeDay(of: line), 1)
        XCTAssertEqual(d.expenseDay(of: line), 1)
    }

    func testRemainingIsTheSameEverywhere() {
        var (d, vakantie, buffer) = engTwoPotData()
        d.pots[0].monthlyContribution = 100
        d.addHolding(Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, monthlyContribution: 50, startMonth: aug2026))
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 300, day: 12,
                               potShares: [PotShare(potID: vakantie.id, amount: 100), PotShare(potID: buffer.id, amount: 50)]),
                     kind: .expense, in: oct2026)

        // Oktober: inkomen 3100, uitgaven 1000 + 300 waarvan 150 uit potten, verdeeld 100, belegd 50.
        XCTAssertEqual(d.income(in: oct2026), 3_100)
        XCTAssertEqual(d.expensesTotal(in: oct2026), 1_300)
        XCTAssertEqual(d.expensesFromPots(in: oct2026), 150)
        XCTAssertEqual(d.expensesFromBank(in: oct2026), 1_150)
        XCTAssertEqual(d.savedTotal(in: oct2026), 100)
        XCTAssertEqual(d.investedTotal(in: oct2026), 50)
        XCTAssertEqual(d.remaining(in: oct2026), 1_800)

        let summary = d.summary(of: oct2026, current: oct2026)
        XCTAssertEqual(summary.income, 3_100)
        XCTAssertEqual(summary.expenses, 1_300, "het totaal")
        XCTAssertEqual(summary.fromPots, 150)
        XCTAssertEqual(summary.saved, 100)
        XCTAssertEqual(summary.invested, 50)
        XCTAssertEqual(summary.remaining, 1_800)
        XCTAssertEqual(d.periodSummary(.month, containing: oct2026, current: oct2026).remaining, 1_800)

        let overview = d.expenseOverview(in: oct2026)
        XCTAssertEqual(overview.expenses, 1_300)
        XCTAssertEqual(overview.fromPots, 150)
        XCTAssertEqual(overview.expensesFromBank, 1_150)
        XCTAssertEqual(overview.leftAfterExpenses, 1_950)
        XCTAssertEqual(overview.leftAfterTransfers, 1_800)
        XCTAssertEqual(overview.leftAfterTransfers, d.remaining(in: oct2026))
    }

    func testPeriodRemainingEqualsTheSumOfItsMonths() {
        var (d, vakantie, buffer) = engTwoPotData()
        d.pots[0].monthlyContribution = 100
        d.addHolding(Holding(name: "ETF", kind: .etf, ticker: nil, units: nil, monthlyContribution: 50, startMonth: aug2026))
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 300, day: 12,
                               potShares: [PotShare(potID: vakantie.id, amount: 100), PotShare(potID: buffer.id, amount: 50)]),
                     kind: .expense, in: oct2026)
        let half = d.periodSummary(.halfYear, containing: oct2026, current: oct2026)
        // Juli telt niet mee. Augustus 1900, september 1950, oktober 1800, november en december 1950.
        XCTAssertEqual(half.months.map(\.remaining), [0, 1_900, 1_950, 1_800, 1_950, 1_950])
        XCTAssertEqual(half.income, 15_500)
        XCTAssertEqual(half.expenses, 5_350)
        XCTAssertEqual(half.fromPots, 150)
        XCTAssertEqual(half.saved, 500)
        XCTAssertEqual(half.invested, 250)
        XCTAssertEqual(half.remaining, 9_550)
        XCTAssertEqual(half.remaining, half.months.reduce(0) { $0 + $1.remaining })
        XCTAssertEqual(half.average(half.remaining), 1_591.67, accuracy: 0.001)
    }

    func testNoFloatingPointResidue() {
        // In gewone decimalen is 0,1 + 0,2 niet precies 0,3; in hele centen wel.
        XCTAssertNotEqual(0.1 + 0.2, 0.3)
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 0.30, hourlyRate: 0, hoursPerWeek: 0)
        d.upsertLine(MoneyLine(name: "a", amount: 0.10), kind: .expense, in: aug2026)
        d.upsertLine(MoneyLine(name: "b", amount: 0.20), kind: .expense, in: aug2026)
        XCTAssertEqual(d.remaining(in: aug2026), 0)
        XCTAssertEqual(d.expensesTotal(in: aug2026), 0.30)
        XCTAssertEqual(d.summary(of: aug2026, current: aug2026).remaining, 0)
        XCTAssertEqual(d.periodSummary(.month, containing: aug2026, current: aug2026).remaining, 0)
        XCTAssertEqual(d.expenseOverview(in: aug2026).leftAfterTransfers, 0)
    }

    func testRemainingWithCentsFromHourlyPay() {
        // Uurloon 21,50 x 156 uur = 3354,00.
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 21.5, hoursPerWeek: 36)
        let pots = (0..<3).map { Pot(name: "Pot \($0)", monthlyContribution: 0, startMonth: aug2026) }
        pots.forEach { d.addPot($0) }
        d.upsertLine(MoneyLine(name: "Huur", amount: 1_234.56), kind: .expense, in: aug2026)
        d.upsertLine(MoneyLine(name: "Boodschappen", amount: 987.65), kind: .expense, in: aug2026)
        pots.forEach { d.setAllocation($0.id, in: aug2026, amount: 33.33) }
        XCTAssertEqual(d.savedTotal(in: aug2026), 99.99)
        XCTAssertEqual(d.remaining(in: aug2026), 1_031.80)
        XCTAssertEqual(d.summary(of: aug2026, current: aug2026).remaining, 1_031.80)
    }

    func testSpreadingTheRemainderLeavesNoCentBehind() {
        var d = FinanceData(startMonth: aug2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 100, hourlyRate: 0, hoursPerWeek: 0)
        let pots = (0..<3).map { Pot(name: "Pot \($0)", monthlyContribution: 0, startMonth: aug2026) }
        pots.forEach { d.addPot($0) }
        XCTAssertEqual(d.remaining(in: aug2026), 100)
        d.spreadRemainingOverPots(in: aug2026)
        XCTAssertEqual(pots.map { d.allocation($0.id, in: aug2026) }, [33.34, 33.33, 33.33])
        XCTAssertEqual(d.remaining(in: aug2026), 0, "precies nul, geen 0,01 of 0,03 over")
        XCTAssertEqual(d.savedTotal(in: aug2026), 100)

        // Twee centen over: de eerste twee potten krijgen er elk een.
        d.salary.fixedMonthly = 100.01
        d.clearAllocations(in: aug2026)
        d.spreadRemainingOverPots(in: aug2026)
        XCTAssertEqual(pots.map { d.allocation($0.id, in: aug2026) }, [33.34, 33.34, 33.33])
        XCTAssertEqual(d.remaining(in: aug2026), 0)

        // Bestaande verdeling blijft staan: 90 over is 30 per pot erbij.
        d.salary.fixedMonthly = 100
        d.setAllocation(pots[0].id, in: aug2026, amount: 10)
        d.setAllocation(pots[1].id, in: aug2026, amount: 0)
        d.setAllocation(pots[2].id, in: aug2026, amount: 0)
        d.spreadRemainingOverPots(in: aug2026)
        XCTAssertEqual(pots.map { d.allocation($0.id, in: aug2026) }, [40, 30, 30])
        XCTAssertEqual(d.remaining(in: aug2026), 0)

        // Is er niets over (of te weinig), dan verandert er niets.
        let before = d.months
        d.spreadRemainingOverPots(in: aug2026)
        XCTAssertEqual(d.months, before)
    }

    func testRecurringCopiesKeepDayPotSharesAndStableIDs() {
        var (d, vakantie, _) = engTwoPotData()
        let line = MoneyLine(name: "Abonnement", amount: 30, isRecurring: true, day: 15,
                             potShares: [PotShare(potID: vakantie.id, amount: 10)])
        d.upsertLine(line, kind: .expense, in: aug2026)
        let first = d.synthesizedPlan(for: engDec2026)
        let second = d.synthesizedPlan(for: engDec2026)
        let copy = first.expenses.first { $0.name == "Abonnement" }
        XCTAssertEqual(copy?.day, 15)
        XCTAssertEqual(copy?.potShares.count, 1)
        XCTAssertEqual(copy?.potShares.first?.potID, vakantie.id)
        XCTAssertNotEqual(copy?.id, line.id)
        XCTAssertEqual(first.expenses.map(\.id), second.expenses.map(\.id), "elke keer dezelfde id's")
        XCTAssertNotEqual(first.expenses.map(\.id), d.synthesizedPlan(for: engNov2026).expenses.map(\.id))
        // Een regel uit zo'n maand is dus terug te vinden en te bewerken.
        var edited = copy!
        edited.amount = 40
        d.upsertLine(edited, kind: .expense, in: engDec2026)
        XCTAssertEqual(d.plan(for: engDec2026).expenses.filter { $0.name == "Abonnement" }.count, 1)
        XCTAssertEqual(d.plan(for: engDec2026).expenses.first { $0.name == "Abonnement" }?.amount, 40)
    }

    func testMonthsBeforeTheStartAreEmptyInEveryFigure() {
        let d = makeBaseData()
        let july = YearMonth(year: 2026, month: 7)
        XCTAssertEqual(d.monthFigures(july), MonthFigures())
        XCTAssertEqual(d.expensesFromPots(in: july), 0)
        XCTAssertEqual(d.expensesFromBank(in: july), 0)
        XCTAssertEqual(d.summary(of: july, current: oct2026).remaining, 0)
    }
}
